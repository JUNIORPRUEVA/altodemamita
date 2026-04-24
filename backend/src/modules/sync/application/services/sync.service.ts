import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Prisma, RoleCode, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { LoanAccountingService } from 'src/shared/services/loan-accounting.service';
import { RealtimeEventsService } from 'src/modules/realtime/realtime-events.service';
import { SyncDownloadDto } from '../dto/sync-download.dto';
import { SyncJobResponseDto } from '../dto/sync-job-response.dto';
import { SyncRecordsDto, SyncUploadDto } from '../dto/sync-upload.dto';

interface SyncQueuedJob extends SyncJobResponseDto {
  batch: SyncUploadDto;
}

interface SyncDomainEvent {
  channel: 'sale.created' | 'payment.created' | 'entity.updated';
  id: string;
  recordSyncId: string;
  updatedAt: string;
  payload: Record<string, unknown>;
}

interface SyncRecordCollections {
  users: Record<string, unknown>[];
  clients: Record<string, unknown>[];
  products: Record<string, unknown>[];
  sellers: Record<string, unknown>[];
  sales: Record<string, unknown>[];
  installments: Record<string, unknown>[];
  payments: Record<string, unknown>[];
}

@Injectable()
export class SyncService {
  private readonly jobs = new Map<string, SyncQueuedJob>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly accountingService: LoanAccountingService,
    private readonly realtimeEvents: RealtimeEventsService,
  ) {}

  async upload(batch: SyncUploadDto) {
    const records = this.normalizeRecords(batch.records);
    const counts = this.extractCounts(records);
    if (Object.values(counts).every((value) => value === 0)) {
      throw new BadRequestException('El lote de sincronización está vacío.');
    }

    const validationErrors = this.validateBatch(records);
    if (validationErrors.length > 0) {
      throw new BadRequestException(validationErrors.join(' | '));
    }

    const jobId = randomUUID();
    const receivedAt = new Date().toISOString();
    this.realtimeEvents.publishSyncAccepted(jobId, counts);

    const job: SyncQueuedJob = {
      jobId,
      status: 'processing',
      receivedAt,
      startedAt: receivedAt,
      counts,
      batch,
    };
    this.jobs.set(jobId, job);
    this.pruneJobs();
    this.realtimeEvents.publishSyncStarted(jobId);

    try {
      const result = await this.persistBatch(records);
      const acknowledgedRecords = await this.buildUploadAckRecords(records);
      job.status = 'completed';
      job.finishedAt = new Date().toISOString();
      job.result = result;
      this.realtimeEvents.publishSyncCompleted(jobId, result);

      return {
        jobId,
        status: 'completed',
        receivedAt,
        finishedAt: job.finishedAt,
        device_id: batch.device_id ?? null,
        server_time: new Date().toISOString(),
        counts,
        records: acknowledgedRecords,
        result,
      };
    } catch (error) {
      job.status = 'failed';
      job.finishedAt = new Date().toISOString();
      job.error = error instanceof Error ? error.message : 'Error desconocido durante la sincronización.';
      this.realtimeEvents.publishSyncFailed(jobId, job.error);
      throw error;
    }
  }

  getJob(jobId: string) {
    const job = this.jobs.get(jobId);
    if (!job) {
      throw new NotFoundException('Trabajo de sincronización no encontrado.');
    }

    return this.sanitizeJob(job);
  }

  async resetDatabase() {
    const result = await this.prisma.$transaction(async (tx) => {
      const payments = await tx.payment.deleteMany({});
      const installments = await tx.installment.deleteMany({});
      const sales = await tx.sale.deleteMany({});
      const clients = await tx.client.deleteMany({});
      const products = await tx.product.deleteMany({});

      return {
        payments: payments.count,
        installments: installments.count,
        sales: sales.count,
        clients: clients.count,
        products: products.count,
      };
    });

    return {
      message: 'Base de datos nube reseteada correctamente.',
      deleted: result,
      reset_at: new Date().toISOString(),
    };
  }

  private async persistBatch(records: SyncRecordCollections) {
    const affectedSales = new Set<string>();
    const domainEvents: SyncDomainEvent[] = [];

    await this.prisma.$transaction(async (tx) => {
      await this.ensureSyncUserRoles(tx);

      for (const user of records.users) {
        const payload = user as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const existing = await this.findExistingUserRecord(tx, payload, recordSyncId);
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }

        if (deletedAt != null) {
          if (!existing) {
            continue;
          }

          await tx.user.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              isActive: false,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
          });
          await tx.userRole.updateMany({
            where: { userId: existing.id, deletedAt: null },
            data: { deletedAt, syncStatus: SyncStatus.synced },
          });
          continue;
        }

        const email = this.readRequiredString(payload, ['email']);
        const fullName = this.readRequiredString(payload, [
          'full_name',
          'fullName',
          'name',
          'nombre',
        ]);
        const username = this.normalizeUsername(
          this.readString(payload, ['username']),
          email,
          fullName,
        );
        const passwordHash = this.readRequiredString(payload, [
          'password_hash',
          'passwordHash',
        ]);
        const roleCode = this.mapSyncedUserRole(payload['role']);
        const role = await this.ensureSyncRole(tx, roleCode);

        const persisted = existing
          ? await tx.user.update({
              where: { id: existing.id },
              data: {
                syncId: recordSyncId,
                email,
                username,
                fullName,
                passwordHash,
                isActive: this.readBoolean(payload, ['is_active', 'activo']) ?? true,
                deletedAt: null,
                syncStatus: SyncStatus.synced,
                ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              },
              select: { id: true },
            })
          : await tx.user.create({
              data: {
                syncId: recordSyncId,
                email,
                username,
                fullName,
                passwordHash,
                isActive: this.readBoolean(payload, ['is_active', 'activo']) ?? true,
                syncStatus: SyncStatus.synced,
                createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
                updatedAt: incomingUpdatedAt ?? undefined,
              },
              select: { id: true },
            });

        await this.assignSingleUserRole(tx, persisted.id, role.id);
      }

      for (const client of records.clients) {
        const payload = client as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        if (deletedAt != null) {
          const existing = await tx.client.findUnique({
            where: { syncId: recordSyncId },
            select: { id: true, syncId: true, updatedAt: true },
          });
          if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
            continue;
          }
          if (!existing) {
            continue;
          }

          const persisted = await tx.client.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          domainEvents.push({
            channel: 'entity.updated',
            id: persisted.id,
            recordSyncId: persisted.syncId,
            updatedAt: persisted.updatedAt.toISOString(),
            payload: {
              entity: 'client',
              action: 'deleted',
              id: persisted.id,
              record_sync_id: persisted.syncId,
              sync_id: persisted.syncId,
              source: 'sync',
            },
          });
          continue;
        }

        const { firstName, lastName } = this.resolveClientNames(payload);
        const existing = await this.findExistingClientRecord(tx, payload, recordSyncId, firstName, lastName);
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }

        const clientData = {
          syncId: recordSyncId,
          code: this.readString(payload, ['code']),
          firstName,
          lastName,
          documentId: this.readString(payload, ['documentId', 'document_id']),
          email: this.readString(payload, ['email']),
          phone: this.readString(payload, ['phone']),
          address: this.readString(payload, ['address']),
          notes: this.readString(payload, ['notes']),
          deletedAt,
          syncStatus: SyncStatus.synced,
        };

        const persisted = existing
          ? await tx.client.update({
              where: { id: existing.id },
              data: {
                ...clientData,
                ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              },
              select: { id: true, syncId: true, updatedAt: true },
            })
          : await tx.client.create({
              data: {
                ...clientData,
                createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
                updatedAt: incomingUpdatedAt ?? undefined,
              },
              select: { id: true, syncId: true, updatedAt: true },
            });
        domainEvents.push({
          channel: 'entity.updated',
          id: persisted.id,
          recordSyncId: persisted.syncId,
          updatedAt: persisted.updatedAt.toISOString(),
          payload: {
            entity: 'client',
            action: existing ? 'updated' : 'created',
            id: persisted.id,
            record_sync_id: persisted.syncId,
            sync_id: persisted.syncId,
            source: 'sync',
          },
        });
      }

      for (const product of records.products) {
        const payload = product as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const existing = await tx.product.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }
        if (deletedAt != null) {
          if (!existing) {
            continue;
          }

          const persisted = await tx.product.update({
            where: { id: existing.id },
            data: {
              isActive: false,
              stock: 0,
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          domainEvents.push({
            channel: 'entity.updated',
            id: persisted.id,
            recordSyncId: persisted.syncId,
            updatedAt: persisted.updatedAt.toISOString(),
            payload: {
              entity: 'product',
              action: 'deleted',
              id: persisted.id,
              record_sync_id: persisted.syncId,
              sync_id: persisted.syncId,
              source: 'sync',
            },
          });
          continue;
        }

        const blockNumber = this.readRequiredString(payload, ['block_number']);
        const lotNumber = this.readRequiredString(payload, ['lot_number']);
        const area = this.readRequiredNumber(payload, ['area']);
        const pricePerSquareMeter = this.readRequiredNumber(payload, ['price_per_square_meter']);
        const localStatus = this.readString(payload, ['status']) ?? 'disponible';
        const totalPrice = this.roundCurrency(area * pricePerSquareMeter);

        const persisted = await tx.product.upsert({
          where: { syncId: recordSyncId },
          create: {
            syncId: recordSyncId,
            code: recordSyncId,
            name: `Solar M${blockNumber}-S${lotNumber}`,
            description: null,
            price: totalPrice,
            financingPrice: totalPrice,
            stock: localStatus === 'disponible' ? 1 : 0,
            isActive: this.readDate(payload, ['deletedAt', 'deleted_at']) == null,
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              block_number: blockNumber,
              lot_number: lotNumber,
              area,
              price_per_square_meter: pricePerSquareMeter,
              status: localStatus,
            }),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt,
            syncStatus: SyncStatus.synced,
          },
          update: {
            code: recordSyncId,
            name: `Solar M${blockNumber}-S${lotNumber}`,
            description: null,
            price: totalPrice,
            financingPrice: totalPrice,
            stock: localStatus === 'disponible' ? 1 : 0,
            isActive: this.readDate(payload, ['deletedAt', 'deleted_at']) == null,
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              block_number: blockNumber,
              lot_number: lotNumber,
              area,
              price_per_square_meter: pricePerSquareMeter,
              status: localStatus,
            }),
            deletedAt,
            ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
            syncStatus: SyncStatus.synced,
          },
          select: { id: true, syncId: true, updatedAt: true },
        });
        domainEvents.push({
          channel: 'entity.updated',
          id: persisted.id,
          recordSyncId: persisted.syncId,
          updatedAt: persisted.updatedAt.toISOString(),
          payload: {
            entity: 'product',
            action: existing ? 'updated' : 'created',
            id: persisted.id,
            record_sync_id: persisted.syncId,
            sync_id: persisted.syncId,
            source: 'sync',
          },
        });
      }

      for (const seller of records.sellers) {
        const payload = seller as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const existing = await tx.seller.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }
        if (deletedAt != null) {
          if (!existing) {
            continue;
          }

          const persisted = await tx.seller.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          domainEvents.push({
            channel: 'entity.updated',
            id: persisted.id,
            recordSyncId: persisted.syncId,
            updatedAt: persisted.updatedAt.toISOString(),
            payload: {
              entity: 'seller',
              action: 'deleted',
              id: persisted.id,
              record_sync_id: persisted.syncId,
              sync_id: persisted.syncId,
              source: 'sync',
            },
          });
          continue;
        }

        const name = this.readString(payload, ['name', 'full_name']) ?? 'Sin nombre';

        const persisted = await tx.seller.upsert({
          where: { syncId: recordSyncId },
          create: {
            syncId: recordSyncId,
            name,
            documentId: this.readString(payload, ['document_id', 'documentId']),
            phone: this.readString(payload, ['phone']),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt,
            syncStatus: SyncStatus.synced,
          },
          update: {
            name,
            documentId: this.readString(payload, ['document_id', 'documentId']),
            phone: this.readString(payload, ['phone']),
            deletedAt,
            ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
            syncStatus: SyncStatus.synced,
          },
          select: { id: true, syncId: true, updatedAt: true },
        });
        domainEvents.push({
          channel: 'entity.updated',
          id: persisted.id,
          recordSyncId: persisted.syncId,
          updatedAt: persisted.updatedAt.toISOString(),
          payload: {
            entity: 'seller',
            action: existing ? 'updated' : 'created',
            id: persisted.id,
            record_sync_id: persisted.syncId,
            sync_id: persisted.syncId,
            source: 'sync',
          },
        });
      }

      for (const sale of records.sales) {
        const payload = sale as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const existing = await tx.sale.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          if (existing?.id) {
            affectedSales.add(existing.id);
          }
          continue;
        }
        if (deletedAt != null) {
          if (!existing) {
            continue;
          }

          const persisted = await tx.sale.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          domainEvents.push({
            channel: 'entity.updated',
            id: persisted.id,
            recordSyncId: persisted.syncId,
            updatedAt: persisted.updatedAt.toISOString(),
            payload: {
              entity: 'sale',
              action: 'deleted',
              id: persisted.id,
              record_sync_id: persisted.syncId,
              sync_id: persisted.syncId,
              source: 'sync',
            },
          });
          continue;
        }

        const salePrice = this.readRequiredNumber(payload, ['sale_price']);
        const financedBalance = this.readRequiredNumber(payload, ['financed_balance']);
        const downPaymentAmount = this.readRequiredNumber(payload, ['down_payment_amount']);
        const pendingBalance = this.readRequiredNumber(payload, ['pending_balance']);
        const monthlyInterest = this.readRequiredNumber(payload, ['monthly_interest']);
        const installmentCount = this.readRequiredInt(payload, ['installment_count']);
        const localStatus = this.readString(payload, ['status']) ?? 'activa';

        const client = await this.resolveClientReference(tx, payload);
        const user = await this.resolveSyncUser(tx, payload);
        const product = await this.resolveProductReference(tx, payload);
        const seller = await this.resolveSellerReference(tx, payload);
        if (!client || !user || !product) {
          throw new BadRequestException('No se pudieron resolver las referencias de la venta.');
        }
        const persisted = await tx.sale.upsert({
          where: { syncId: recordSyncId },
          create: {
            syncId: recordSyncId,
            clientId: client.id,
            userId: user.id,
            productId: product.id,
            sellerId: seller?.id,
            contractNumber: recordSyncId,
            saleDate: this.readRequiredDate(payload, ['sale_date']),
            principalAmount: salePrice,
            financedAmount: financedBalance,
            downPayment: downPaymentAmount,
            interestRate: monthlyInterest,
            totalAmount: salePrice,
            termMonths: installmentCount,
            paidAmount: this.roundCurrency(salePrice - pendingBalance),
            outstandingBalance: pendingBalance,
            status: this.mapSaleStatusToBackend(localStatus),
            notes: null,
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              client_sync_id: client.syncId,
              product_sync_id: product.syncId,
              seller_sync_id: seller?.syncId,
              status: localStatus,
            }),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt,
            syncStatus: SyncStatus.synced,
          },
          update: {
            clientId: client.id,
            userId: user.id,
            productId: product.id,
            sellerId: seller?.id,
            contractNumber: recordSyncId,
            saleDate: this.readRequiredDate(payload, ['sale_date']),
            principalAmount: salePrice,
            financedAmount: financedBalance,
            downPayment: downPaymentAmount,
            interestRate: monthlyInterest,
            totalAmount: salePrice,
            termMonths: installmentCount,
            paidAmount: this.roundCurrency(salePrice - pendingBalance),
            outstandingBalance: pendingBalance,
            status: this.mapSaleStatusToBackend(localStatus),
            notes: null,
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              client_sync_id: client.syncId,
              product_sync_id: product.syncId,
              seller_sync_id: seller?.syncId,
              status: localStatus,
            }),
            deletedAt,
            ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
            syncStatus: SyncStatus.synced,
          },
          select: { id: true, syncId: true, updatedAt: true },
        });
        affectedSales.add(persisted.id);
        domainEvents.push({
          channel: existing ? 'entity.updated' : 'sale.created',
          id: persisted.id,
          recordSyncId: persisted.syncId,
          updatedAt: persisted.updatedAt.toISOString(),
          payload: existing
            ? {
                entity: 'sale',
                action: 'updated',
                id: persisted.id,
                record_sync_id: persisted.syncId,
                sync_id: persisted.syncId,
                source: 'sync',
              }
            : {
                id: persisted.id,
                record_sync_id: persisted.syncId,
                sync_id: persisted.syncId,
                contractNumber: recordSyncId,
                clientId: client.id,
                productId: product.id,
                source: 'sync',
              },
        });
      }

      for (const installment of records.installments) {
        const payload = installment as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const existing = await tx.installment.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true, saleId: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          if (existing?.saleId) {
            affectedSales.add(existing.saleId);
          }
          continue;
        }
        if (deletedAt != null) {
          if (!existing) {
            continue;
          }

          affectedSales.add(existing.saleId);
          const persisted = await tx.installment.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          domainEvents.push({
            channel: 'entity.updated',
            id: persisted.id,
            recordSyncId: persisted.syncId,
            updatedAt: persisted.updatedAt.toISOString(),
            payload: {
              entity: 'installment',
              action: 'deleted',
              id: persisted.id,
              record_sync_id: persisted.syncId,
              sync_id: persisted.syncId,
              source: 'sync',
            },
          });
          continue;
        }

        const installmentNumber = this.readRequiredInt(payload, ['installment_number']);
        const dueDate = this.readRequiredDate(payload, ['due_date']);
        const totalAmount = this.readRequiredNumber(payload, ['total_amount']);
        const principalAmount = this.readRequiredNumber(payload, ['principal_amount']);
        const interestAmount = this.readRequiredNumber(payload, ['interest_amount']);
        const paidAmount = this.readNumber(payload, ['paid_amount']) ?? 0;
        const localStatus = this.readString(payload, ['status']) ?? 'pendiente';
        const saleRecord = await this.resolveSaleReference(tx, payload);
        if (!saleRecord) {
          throw new BadRequestException('No se pudo resolver la venta de la cuota.');
        }
        affectedSales.add(saleRecord.id);

        const persisted = await tx.installment.upsert({
          where: { syncId: recordSyncId },
          create: {
            syncId: recordSyncId,
            saleId: saleRecord.id,
            installmentNumber,
            dueDate,
            amount: totalAmount,
            principalAmount,
            interestAmount,
            paidAmount,
            status: this.mapInstallmentStatusToBackend(localStatus),
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              sale_sync_id: saleRecord.syncId,
              status: localStatus,
            }),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt,
            syncStatus: SyncStatus.synced,
          },
          update: {
            saleId: saleRecord.id,
            installmentNumber,
            dueDate,
            amount: totalAmount,
            principalAmount,
            interestAmount,
            paidAmount,
            status: this.mapInstallmentStatusToBackend(localStatus),
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              sale_sync_id: saleRecord.syncId,
              status: localStatus,
            }),
            deletedAt,
            ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
            syncStatus: SyncStatus.synced,
          },
          select: { id: true, syncId: true, updatedAt: true },
        });
        domainEvents.push({
          channel: 'entity.updated',
          id: persisted.id,
          recordSyncId: persisted.syncId,
          updatedAt: persisted.updatedAt.toISOString(),
          payload: {
            entity: 'installment',
            action: existing ? 'updated' : 'created',
            id: persisted.id,
            record_sync_id: persisted.syncId,
            sync_id: persisted.syncId,
            saleId: saleRecord.id,
            source: 'sync',
          },
        });
      }

      for (const payment of records.payments) {
        const payload = payment as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const existing = await tx.payment.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true, saleId: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          if (existing?.saleId) {
            affectedSales.add(existing.saleId);
          }
          continue;
        }
        if (deletedAt != null) {
          if (!existing) {
            continue;
          }

          affectedSales.add(existing.saleId);
          const persisted = await tx.payment.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          domainEvents.push({
            channel: 'entity.updated',
            id: persisted.id,
            recordSyncId: persisted.syncId,
            updatedAt: persisted.updatedAt.toISOString(),
            payload: {
              entity: 'payment',
              action: 'deleted',
              id: persisted.id,
              record_sync_id: persisted.syncId,
              sync_id: persisted.syncId,
              saleId: existing.saleId,
              source: 'sync',
            },
          });
          continue;
        }

        const paymentDate = this.readRequiredDate(payload, ['payment_date']);
        const amountPaid = this.readRequiredNumber(payload, ['amount_paid']);
        const paymentMethod = this.readString(payload, ['payment_method']) ?? 'efectivo';
        const paymentType = this.readString(payload, ['payment_type']) ?? 'cuota';
        const saleRecord = await this.resolveSaleReference(tx, payload);
        const installmentRecord = await this.resolveInstallmentReference(tx, payload, true);
        if (!saleRecord) {
          throw new BadRequestException('No se pudo resolver la venta del pago.');
        }
        affectedSales.add(saleRecord.id);

        const persisted = await tx.payment.upsert({
          where: { syncId: recordSyncId },
          create: {
            syncId: recordSyncId,
            saleId: saleRecord.id,
            installmentId: installmentRecord?.id,
            paymentDate,
            amount: amountPaid,
            principalAmount: this.readNumber(payload, ['principal_amount']) ?? amountPaid,
            interestAmount: this.readNumber(payload, ['interest_amount']) ?? 0,
            method: this.mapPaymentMethodToBackend(paymentMethod),
            reference: this.readString(payload, ['reference']),
            notes: null,
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              sale_sync_id: saleRecord.syncId,
              installment_sync_id: installmentRecord?.syncId,
              payment_type: paymentType,
              payment_method: paymentMethod,
            }),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt,
            syncStatus: SyncStatus.synced,
          },
          update: {
            saleId: saleRecord.id,
            installmentId: installmentRecord?.id,
            paymentDate,
            amount: amountPaid,
            principalAmount: this.readNumber(payload, ['principal_amount']) ?? amountPaid,
            interestAmount: this.readNumber(payload, ['interest_amount']) ?? 0,
            method: this.mapPaymentMethodToBackend(paymentMethod),
            reference: this.readString(payload, ['reference']),
            notes: null,
            syncPayload: this.toJsonValue({
              ...payload,
              sync_id: recordSyncId,
              sale_sync_id: saleRecord.syncId,
              installment_sync_id: installmentRecord?.syncId,
              payment_type: paymentType,
              payment_method: paymentMethod,
            }),
            deletedAt,
            ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
            syncStatus: SyncStatus.synced,
          },
          select: { id: true, syncId: true, updatedAt: true },
        });
        domainEvents.push({
          channel: existing ? 'entity.updated' : 'payment.created',
          id: persisted.id,
          recordSyncId: persisted.syncId,
          updatedAt: persisted.updatedAt.toISOString(),
          payload: existing
            ? {
                entity: 'payment',
                action: 'updated',
                id: persisted.id,
                record_sync_id: persisted.syncId,
                sync_id: persisted.syncId,
                saleId: saleRecord.id,
                source: 'sync',
              }
            : {
                id: persisted.id,
                record_sync_id: persisted.syncId,
                sync_id: persisted.syncId,
                saleId: saleRecord.id,
                installmentId: installmentRecord?.id,
                amount: amountPaid,
                source: 'sync',
              },
        });
      }
    });

    for (const saleId of affectedSales) {
      await this.accountingService.syncSaleAggregates(this.prisma, saleId);
      await this.prisma.sale.update({
        where: { id: saleId },
        data: { syncStatus: SyncStatus.synced },
      });
    }

    for (const event of domainEvents) {
      if (event.channel === 'sale.created') {
        this.realtimeEvents.publishSaleCreated(
          event.id,
          event.recordSyncId,
          event.payload,
          'sync',
          event.updatedAt,
        );
        continue;
      }

      if (event.channel === 'payment.created') {
        this.realtimeEvents.publishPaymentCreated(
          event.id,
          event.recordSyncId,
          event.payload,
          'sync',
          event.updatedAt,
        );
        continue;
      }

      this.realtimeEvents.publishEntityUpdated({
        entity: event.payload.entity as string,
        action: event.payload.action as 'created' | 'updated' | 'deleted',
        id: event.id,
        recordSyncId: event.recordSyncId,
        data: event.payload,
        source: 'sync',
        updatedAt: event.updatedAt,
      });
    }

    return {
      uploaded: {
        users: records.users.length,
        clients: records.clients.length,
        products: records.products.length,
        sellers: records.sellers.length,
        sales: records.sales.length,
        installments: records.installments.length,
        payments: records.payments.length,
      },
      affectedSales: Array.from(affectedSales),
    };
  }

  async download(query: SyncDownloadDto) {
    const updatedSince = query.updatedSince ? new Date(query.updatedSince) : undefined;
    const where = updatedSince
      ? { updatedAt: { gt: updatedSince } }
      : {};

    const [users, roles, permissions, clients, products, sellers, sales, installments, payments] = await this.prisma.$transaction([
      this.prisma.user.findMany({
        where,
        include: {
          userRoles: {
            where: { deletedAt: null },
            include: { role: true },
          },
        },
      }),
      this.prisma.role.findMany({ where }),
      this.prisma.permission.findMany({ where }),
      this.prisma.client.findMany({ where }),
      this.prisma.product.findMany({ where }),
      this.prisma.seller.findMany({ where }),
      this.prisma.sale.findMany({
        where,
        include: {
          client: { select: { syncId: true } },
          product: { select: { syncId: true } },
          seller: { select: { syncId: true } },
        },
      }),
      this.prisma.installment.findMany({
        where,
        include: {
          sale: { select: { syncId: true } },
        },
      }),
      this.prisma.payment.findMany({
        where,
        include: {
          sale: {
            select: {
              syncId: true,
              client: { select: { syncId: true } },
            },
          },
          installment: { select: { syncId: true } },
        },
      }),
    ]);

    return {
      device_id: query.device_id ?? null,
      updatedSince: query.updatedSince ?? null,
      server_time: new Date().toISOString(),
      records: {
        users: users.map((item) => this.serializeUserRecord(item)),
        clients: clients.map((item) => this.serializeClientRecord(item)),
        products: products.map((item) => this.serializeProductRecord(item)),
        sellers: sellers.map((item) => this.serializeSellerRecord(item)),
        sales: sales.map((item) => this.serializeSaleRecord(item)),
        installments: installments.map((item) => this.serializeInstallmentRecord(item)),
        payments: payments.map((item) => this.serializePaymentRecord(item)),
      },
      metadata: {
        users,
        roles,
        permissions,
      },
    };
  }

  private validateBatch(records: SyncRecordCollections): string[] {
    const errors: string[] = [];
    const seenRecordSyncIds = new Map<string, string>();

    const validateCollection = (
      scope: keyof SyncRecordCollections,
      records: Record<string, unknown>[],
      requiredFields: Array<string | string[]>,
      referenceGroups: string[][] = [],
    ) => {
      for (const [index, record] of records.entries()) {
        const recordSyncId = this.normalizeRecordSyncId(record);
        if (!recordSyncId) {
          errors.push(`${String(scope)}[${index}] requiere record_sync_id o sync_id.`);
        } else {
          const duplicatedAt = seenRecordSyncIds.get(recordSyncId);
          if (duplicatedAt) {
            errors.push(`${String(scope)}[${index}] repite record_sync_id '${recordSyncId}' ya usado en ${duplicatedAt}.`);
          } else {
            seenRecordSyncIds.set(recordSyncId, `${String(scope)}[${index}]`);
          }
        }

        if (!this.hasAnyValue(record, ['updatedAt', 'updated_at'])) {
          errors.push(`${String(scope)}[${index}] requiere updatedAt o updated_at.`);
        }

        if (this.isDeletePayload(record)) {
          continue;
        }

        for (const field of requiredFields) {
          const keys = Array.isArray(field) ? field : [field];
          if (!this.hasAnyValue(record, keys)) {
            errors.push(`${String(scope)}[${index}] requiere ${keys.join(' o ')}.`);
          }
        }

        for (const group of referenceGroups) {
          if (!this.hasAnyValue(record, group)) {
            errors.push(`${String(scope)}[${index}] requiere una referencia en [${group.join(', ')}].`);
          }
        }
      }
    };

    validateCollection(
      'users',
      records.users,
      [
        ['email'],
        ['password_hash', 'passwordHash'],
        ['role'],
        ['full_name', 'fullName', 'name', 'nombre'],
      ],
    );

    validateCollection('clients', records.clients, [], []);
    for (const [index, client] of records.clients.entries()) {
      const payload = client as Record<string, unknown>;
      if (this.isDeletePayload(payload)) {
        continue;
      }
      const hasSplitName =
        this.hasAnyValue(payload, ['firstName', 'first_name']) &&
        this.hasAnyValue(payload, ['lastName', 'last_name']);
      const hasFullName = this.hasAnyValue(payload, ['full_name', 'fullName']);
      if (!hasSplitName && !hasFullName) {
        errors.push(`clients[${index}] requiere firstName y lastName, o full_name.`);
      }
    }

    validateCollection(
      'products',
      records.products,
      ['block_number', 'lot_number', 'area', 'price_per_square_meter'],
    );
    validateCollection(
      'sellers',
      records.sellers,
      [['name', 'full_name']],
    );
    validateCollection(
      'sales',
      records.sales,
      [
        ['sale_date'],
        ['sale_price'],
        ['financed_balance'],
        ['down_payment_amount'],
        ['monthly_interest'],
        ['installment_count'],
        'status',
      ],
      [
        ['client_sync_id', 'clientId', 'client_id'],
        ['product_sync_id', 'productId', 'product_id'],
      ],
    );
    validateCollection(
      'installments',
      records.installments,
      [
        ['installment_number'],
        ['due_date'],
        ['total_amount'],
        ['principal_amount'],
        ['interest_amount'],
        'status',
      ],
      [['sale_sync_id', 'saleId', 'sale_id']],
    );
    validateCollection(
      'payments',
      records.payments,
      [
        ['payment_date'],
        ['amount_paid'],
        ['payment_method'],
      ],
      [['sale_sync_id', 'saleId', 'sale_id']],
    );

    return errors;
  }

  private normalizeRecords(records?: SyncRecordsDto): SyncRecordCollections {
    return {
      users: records?.users ?? [],
      clients: records?.clients ?? [],
      products: records?.products ?? [],
      sellers: records?.sellers ?? [],
      sales: records?.sales ?? [],
      installments: records?.installments ?? [],
      payments: records?.payments ?? [],
    };
  }

  private emptyRecords(): SyncRecordCollections {
    return {
      users: [],
      clients: [],
      products: [],
      sellers: [],
      sales: [],
      installments: [],
      payments: [],
    };
  }

  private async buildUploadAckRecords(
    records: SyncRecordCollections,
  ): Promise<SyncRecordCollections> {
    const userSyncIds = this.collectInputSyncIds(records.users);
    const clientSyncIds = this.collectInputSyncIds(records.clients);
    const productSyncIds = this.collectInputSyncIds(records.products);
    const sellerSyncIds = this.collectInputSyncIds(records.sellers);
    const saleSyncIds = this.collectInputSyncIds(records.sales);
    const installmentSyncIds = this.collectInputSyncIds(records.installments);
    const paymentSyncIds = this.collectInputSyncIds(records.payments);

    const [users, clients, products, sellers, sales, installments, payments] = await Promise.all([
      userSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.user.findMany({
            where: { syncId: { in: userSyncIds } },
            include: {
              userRoles: {
                where: { deletedAt: null },
                include: { role: true },
              },
            },
            orderBy: { updatedAt: 'asc' },
          }),
      clientSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.client.findMany({
            where: { syncId: { in: clientSyncIds } },
            orderBy: { updatedAt: 'asc' },
          }),
      productSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.product.findMany({
            where: { syncId: { in: productSyncIds } },
            orderBy: { updatedAt: 'asc' },
          }),
      sellerSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.seller.findMany({
            where: { syncId: { in: sellerSyncIds } },
            orderBy: { updatedAt: 'asc' },
          }),
      saleSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.sale.findMany({
            where: { syncId: { in: saleSyncIds } },
            include: {
              client: { select: { syncId: true } },
              product: { select: { syncId: true } },
              seller: { select: { syncId: true } },
            },
            orderBy: { updatedAt: 'asc' },
          }),
      installmentSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.installment.findMany({
            where: { syncId: { in: installmentSyncIds } },
            include: {
              sale: { select: { syncId: true } },
            },
            orderBy: { updatedAt: 'asc' },
          }),
      paymentSyncIds.length === 0
        ? Promise.resolve([])
        : this.prisma.payment.findMany({
            where: { syncId: { in: paymentSyncIds } },
            include: {
              sale: {
                select: {
                  syncId: true,
                  client: { select: { syncId: true } },
                },
              },
              installment: { select: { syncId: true } },
            },
            orderBy: { updatedAt: 'asc' },
          }),
    ]);

    return {
      users: this.mergeAcknowledgedRecords(
        records.users,
        users.map((item) => this.serializeUserRecord(item)),
      ),
      clients: this.mergeAcknowledgedRecords(
        records.clients,
        clients.map((item) => this.serializeClientRecord(item)),
      ),
      products: this.mergeAcknowledgedRecords(
        records.products,
        products.map((item) => this.serializeProductRecord(item)),
      ),
      sellers: this.mergeAcknowledgedRecords(
        records.sellers,
        sellers.map((item) => this.serializeSellerRecord(item)),
      ),
      sales: this.mergeAcknowledgedRecords(
        records.sales,
        sales.map((item) => this.serializeSaleRecord(item)),
      ),
      installments: this.mergeAcknowledgedRecords(
        records.installments,
        installments.map((item) => this.serializeInstallmentRecord(item)),
      ),
      payments: this.mergeAcknowledgedRecords(
        records.payments,
        payments.map((item) => this.serializePaymentRecord(item)),
      ),
    };
  }

  private collectInputSyncIds(records: Record<string, unknown>[]): string[] {
    return Array.from(
      new Set(
        records
          .map((record) => this.normalizeRecordSyncId(record))
          .filter((value): value is string => Boolean(value)),
      ),
    );
  }

  private mergeAcknowledgedRecords(
    inputRecords: Record<string, unknown>[],
    persistedRecords: Record<string, unknown>[],
  ): Record<string, unknown>[] {
    const persistedBySyncId = new Map(
      persistedRecords
        .map((record) => [this.normalizeRecordSyncId(record), record] as const)
        .filter((entry): entry is readonly [string, Record<string, unknown>] => Boolean(entry[0])),
    );

    return inputRecords
      .map((record) => {
        const syncId = this.normalizeRecordSyncId(record);
        if (!syncId) {
          return null;
        }

        const persisted = persistedBySyncId.get(syncId);
        if (persisted) {
          return persisted;
        }

        if (this.isDeletePayload(record)) {
          return this.buildDeleteAckRecord(record, syncId);
        }

        return null;
      })
      .filter((record): record is Record<string, unknown> => record != null);
  }

  private buildDeleteAckRecord(
    payload: Record<string, unknown>,
    syncId: string,
  ): Record<string, unknown> {
    const updatedAt =
      this.readDate(payload, ['updatedAt', 'updated_at']) ??
      this.readDate(payload, ['deletedAt', 'deleted_at']) ??
      new Date();
    const deletedAt =
      this.readDate(payload, ['deletedAt', 'deleted_at']) ?? updatedAt;

    return {
      sync_id: syncId,
      version: this.readNumber(payload, ['version']) ?? 1,
      updated_at: updatedAt.toISOString(),
      deleted_at: deletedAt.toISOString(),
      sync_status: SyncStatus.synced,
    };
  }

  private normalizeRecordSyncId(payload: Record<string, unknown>): string | null {
    const value = payload.record_sync_id ?? payload.sync_id;
    const normalized = value?.toString().trim();
    return normalized ? normalized : null;
  }

  private isDeletePayload(payload: Record<string, unknown>): boolean {
    return this.hasAnyValue(payload, ['deletedAt', 'deleted_at']);
  }

  private readRecordSyncId(payload: Record<string, unknown>): string {
    const recordSyncId = this.normalizeRecordSyncId(payload);
    if (!recordSyncId) {
      throw new BadRequestException('Cada registro requiere record_sync_id o sync_id.');
    }
    return recordSyncId;
  }

  private hasAnyValue(payload: Record<string, unknown>, keys: string[]): boolean {
    return keys.some((key) => {
      const value = payload[key];
      if (value == null) {
        return false;
      }
      if (typeof value === 'string') {
        return value.trim().length > 0;
      }
      return true;
    });
  }

  private readString(payload: Record<string, unknown>, keys: string[]): string | undefined {
    for (const key of keys) {
      const value = payload[key]?.toString().trim();
      if (value) {
        return value;
      }
    }
    return undefined;
  }

  private readRequiredString(payload: Record<string, unknown>, keys: string[]): string {
    const value = this.readString(payload, keys);
    if (!value) {
      throw new BadRequestException(`Falta uno de los campos requeridos: ${keys.join(', ')}.`);
    }
    return value;
  }

  private readNumber(payload: Record<string, unknown>, keys: string[]): number | null {
    for (const key of keys) {
      const rawValue = payload[key];
      if (rawValue == null || rawValue == '') {
        continue;
      }
      const resolved = Number(rawValue);
      if (!Number.isNaN(resolved)) {
        return resolved;
      }
    }
    return null;
  }

  private readRequiredNumber(payload: Record<string, unknown>, keys: string[]): number {
    const value = this.readNumber(payload, keys);
    if (value == null) {
      throw new BadRequestException(`Falta uno de los campos numéricos requeridos: ${keys.join(', ')}.`);
    }
    return value;
  }

  private readRequiredInt(payload: Record<string, unknown>, keys: string[]): number {
    return Math.trunc(this.readRequiredNumber(payload, keys));
  }

  private readDate(payload: Record<string, unknown>, keys: string[]): Date | null {
    for (const key of keys) {
      const value = payload[key]?.toString().trim();
      if (!value) {
        continue;
      }
      const parsed = new Date(value);
      if (!Number.isNaN(parsed.getTime())) {
        return parsed;
      }
    }
    return null;
  }

  private readRequiredDate(payload: Record<string, unknown>, keys: string[]): Date {
    const value = this.readDate(payload, keys);
    if (!value) {
      throw new BadRequestException(`Falta una fecha valida en: ${keys.join(', ')}.`);
    }
    return value;
  }

  private shouldSkipWrite(existingUpdatedAt?: Date, incomingUpdatedAt?: Date | null): boolean {
    if (!existingUpdatedAt) {
      return false;
    }
    if (!incomingUpdatedAt) {
      return true;
    }
    return existingUpdatedAt.getTime() >= incomingUpdatedAt.getTime();
  }

  private resolveClientNames(payload: Record<string, unknown>): { firstName: string; lastName: string } {
    const firstName = this.readString(payload, ['firstName', 'first_name']);
    const lastName = this.readString(payload, ['lastName', 'last_name']);
    if (firstName && lastName) {
      return { firstName, lastName };
    }

    const fullName = this.readRequiredString(payload, ['full_name', 'fullName']);
    const parts = fullName.split(/\s+/).filter(Boolean);
    if (parts.length === 1) {
      return { firstName: parts[0], lastName: parts[0] };
    }

    return {
      firstName: parts.shift() ?? fullName,
      lastName: parts.join(' '),
    };
  }

  private async findExistingClientRecord(
    tx: Prisma.TransactionClient,
    payload: Record<string, unknown>,
    recordSyncId: string,
    firstName: string,
    lastName: string,
  ) {
    const bySyncId = await tx.client.findUnique({
      where: { syncId: recordSyncId },
      select: { id: true, syncId: true, updatedAt: true },
    });
    if (bySyncId) {
      return bySyncId;
    }

    const documentId = this.normalizeIdentityValue(
      this.readString(payload, ['documentId', 'document_id']),
    );
    if (documentId) {
      const byDocumentId = await tx.client.findFirst({
        where: {
          deletedAt: null,
          documentId: {
            equals: documentId,
            mode: 'insensitive',
          },
        },
        orderBy: [
          { updatedAt: 'desc' },
          { createdAt: 'desc' },
        ],
        select: { id: true, syncId: true, updatedAt: true },
      });
      if (byDocumentId) {
        return byDocumentId;
      }
    }

    const phone = this.normalizeIdentityValue(this.readString(payload, ['phone']));
    if (!phone) {
      return null;
    }

    return tx.client.findFirst({
      where: {
        deletedAt: null,
        firstName: {
          equals: firstName.trim(),
          mode: 'insensitive',
        },
        lastName: {
          equals: lastName.trim(),
          mode: 'insensitive',
        },
        phone: {
          equals: phone,
          mode: 'insensitive',
        },
      },
      orderBy: [
        { updatedAt: 'desc' },
        { createdAt: 'desc' },
      ],
      select: { id: true, syncId: true, updatedAt: true },
    });
  }

  private normalizeIdentityValue(value?: string): string | undefined {
    const normalized = value?.trim();
    if (!normalized) {
      return undefined;
    }
    return normalized;
  }

  private async ensureSyncUserRoles(tx: Prisma.TransactionClient) {
    for (const code of Object.values(PERMISSIONS)) {
      await tx.permission.upsert({
        where: { code },
        update: { deletedAt: null, syncStatus: SyncStatus.synced, name: code },
        create: {
          code,
          name: code,
          syncStatus: SyncStatus.synced,
        },
      });
    }

    await this.ensureSyncRole(tx, RoleCode.SUPER_ADMIN);
    await this.ensureSyncRole(tx, RoleCode.SALES_AGENT);
  }

  private async ensureSyncRole(
    tx: Prisma.TransactionClient,
    code: RoleCode,
  ) {
    const definition = code === RoleCode.SUPER_ADMIN
      ? {
          name: 'Super Admin',
          description: 'Acceso total al sistema',
          permissionCodes: Object.values(PERMISSIONS),
        }
      : {
          name: 'Sales Agent',
          description: 'Operacion comercial sincronizada desde escritorio',
          permissionCodes: [
            PERMISSIONS.clientsRead,
            PERMISSIONS.clientsWrite,
            PERMISSIONS.productsRead,
            PERMISSIONS.sellersRead,
            PERMISSIONS.sellersWrite,
            PERMISSIONS.salesRead,
            PERMISSIONS.salesWrite,
            PERMISSIONS.paymentsRead,
            PERMISSIONS.paymentsWrite,
            PERMISSIONS.installmentsRead,
            PERMISSIONS.installmentsWrite,
            PERMISSIONS.reportsRead,
          ],
        };

    const role = await tx.role.upsert({
      where: { code },
      update: {
        deletedAt: null,
        syncStatus: SyncStatus.synced,
        name: definition.name,
        description: definition.description,
      },
      create: {
        code,
        name: definition.name,
        description: definition.description,
        syncStatus: SyncStatus.synced,
      },
      select: { id: true },
    });

    const permissions = await tx.permission.findMany({
      where: {
        code: { in: definition.permissionCodes },
        deletedAt: null,
      },
      select: { id: true },
    });

    await tx.rolePermission.updateMany({
      where: {
        roleId: role.id,
        deletedAt: null,
        permissionId: { notIn: permissions.map((item) => item.id) },
      },
      data: { deletedAt: new Date(), syncStatus: SyncStatus.synced },
    });

    for (const permission of permissions) {
      await tx.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: role.id,
            permissionId: permission.id,
          },
        },
        update: { deletedAt: null, syncStatus: SyncStatus.synced },
        create: {
          roleId: role.id,
          permissionId: permission.id,
          syncStatus: SyncStatus.synced,
        },
      });
    }

    return role;
  }

  private async findExistingUserRecord(
    tx: Prisma.TransactionClient,
    payload: Record<string, unknown>,
    recordSyncId: string,
  ) {
    const bySyncId = await tx.user.findUnique({
      where: { syncId: recordSyncId },
      select: { id: true, updatedAt: true },
    });
    if (bySyncId) {
      return bySyncId;
    }

    const email = this.readString(payload, ['email']);
    if (email) {
      const byEmail = await tx.user.findFirst({
        where: {
          email: { equals: email, mode: 'insensitive' },
        },
        select: { id: true, updatedAt: true },
      });
      if (byEmail) {
        return byEmail;
      }
    }

    const username = this.readString(payload, ['username']);
    if (!username) {
      return null;
    }

    return tx.user.findFirst({
      where: {
        username: { equals: username, mode: 'insensitive' },
      },
      select: { id: true, updatedAt: true },
    });
  }

  private normalizeUsername(rawUsername: string | undefined, email: string, fullName: string) {
    const baseValue = rawUsername?.trim() || email.split('@')[0] || fullName;
    const normalized = baseValue
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9._-]+/g, '.')
      .replace(/\.{2,}/g, '.')
      .replace(/^\.|\.$/g, '');

    return normalized || 'admin';
  }

  private mapSyncedUserRole(rawRole: unknown) {
    const normalized = rawRole?.toString().trim().toLowerCase();
    return normalized === 'admin' ? RoleCode.SUPER_ADMIN : RoleCode.SALES_AGENT;
  }

  private async assignSingleUserRole(
    tx: Prisma.TransactionClient,
    userId: string,
    roleId: string,
  ) {
    await tx.userRole.updateMany({
      where: {
        userId,
        deletedAt: null,
        roleId: { not: roleId },
      },
      data: { deletedAt: new Date(), syncStatus: SyncStatus.synced },
    });

    await tx.userRole.upsert({
      where: {
        userId_roleId: { userId, roleId },
      },
      update: { deletedAt: null, syncStatus: SyncStatus.synced },
      create: { userId, roleId, syncStatus: SyncStatus.synced },
    });
  }

  private readBoolean(payload: Record<string, unknown>, keys: string[]) {
    for (const key of keys) {
      const value = payload[key];
      if (typeof value === 'boolean') {
        return value;
      }
      if (typeof value === 'number') {
        return value !== 0;
      }
      if (typeof value === 'string') {
        const normalized = value.trim().toLowerCase();
        if (normalized === 'true' || normalized === '1') {
          return true;
        }
        if (normalized === 'false' || normalized === '0') {
          return false;
        }
      }
    }
    return null;
  }

  private async resolveClientReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.client, payload, ['client_sync_id'], ['clientId', 'client_id'], 'cliente');
  }

  private async resolveUserReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.user, payload, ['user_sync_id'], ['userId', 'user_id'], 'usuario');
  }

  private async resolveSyncUser(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    const hasExplicitUserReference = this.hasAnyValue(payload, [
      'user_sync_id',
      'userId',
      'user_id',
    ]);
    if (hasExplicitUserReference) {
      const explicitUser = await this.resolveUserReference(tx, payload);
      if (explicitUser) {
        return explicitUser;
      }
    }

    const fallbackUser = await tx.user.findFirst({
      where: { deletedAt: null, isActive: true },
      select: { id: true, syncId: true },
      orderBy: { createdAt: 'asc' },
    });
    if (!fallbackUser) {
      throw new BadRequestException('No existe un usuario backend activo para asociar la venta.');
    }
    return fallbackUser;
  }

  private async resolveProductReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.product, payload, ['product_sync_id'], ['productId', 'product_id'], 'producto');
  }

  private async resolveSellerReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.seller, payload, ['seller_sync_id'], ['sellerId', 'seller_id'], 'vendedor', true);
  }

  private async resolveSaleReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.sale, payload, ['sale_sync_id'], ['saleId', 'sale_id'], 'venta');
  }

  private async resolveInstallmentReference(
    tx: Prisma.TransactionClient,
    payload: Record<string, unknown>,
    optional = false,
  ) {
    return this.resolveReference(
      tx.installment,
      payload,
      ['installment_sync_id'],
      ['installmentId', 'installment_id'],
      'cuota',
      optional,
    );
  }

  private async resolveReference(
    delegate: {
      findFirst(args: {
        where: { OR: Array<Record<string, string>> };
        select: { id: true; syncId: true };
      }): Promise<{ id: string; syncId: string } | null>;
    },
    payload: Record<string, unknown>,
    syncKeys: string[],
    idKeys: string[],
    label: string,
    optional = false,
  ): Promise<{ id: string; syncId: string } | null> {
    const reference = this.readString(payload, [...syncKeys, ...idKeys]);
    if (!reference) {
      if (optional) {
        return null;
      }
      throw new BadRequestException(`No se recibió referencia para ${label}.`);
    }

    const entity = await delegate.findFirst({
      where: {
        OR: this.isUuid(reference)
          ? [{ syncId: reference }, { id: reference }]
          : [{ syncId: reference }],
      },
      select: { id: true, syncId: true },
    });

    if (!entity && !optional) {
      throw new BadRequestException(`No existe ${label} para la referencia '${reference}'.`);
    }

    return entity;
  }

  private isUuid(value: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  }

  private extractCounts(records: SyncRecordCollections): Record<string, number> {
    return {
      users: records.users.length,
      clients: records.clients.length,
      products: records.products.length,
      sellers: records.sellers.length,
      sales: records.sales.length,
      installments: records.installments.length,
      payments: records.payments.length,
    };
  }

  private roundCurrency(value: number): number {
    return Number(value.toFixed(2));
  }

  private mapSaleStatusToBackend(status: string) {
    switch (status.trim().toLowerCase()) {
      case 'apartado':
      case 'inicial_incompleto':
        return 'draft' as const;
      case 'pagada':
      case 'completada':
      case 'vendido':
        return 'completed' as const;
      case 'cancelada':
        return 'cancelled' as const;
      case 'vencida':
        return 'overdue' as const;
      default:
        return 'active' as const;
    }
  }

  private mapSaleStatusToLocal(status: string) {
    switch (status.trim().toLowerCase()) {
      case 'draft':
        return 'apartado';
      case 'completed':
        return 'pagada';
      case 'cancelled':
        return 'cancelada';
      case 'overdue':
        return 'vencida';
      default:
        return 'activa';
    }
  }

  private mapInstallmentStatusToBackend(status: string) {
    switch (status.trim().toLowerCase()) {
      case 'pagada':
      case 'paid':
        return 'paid' as const;
      case 'parcial':
      case 'partial':
        return 'partial' as const;
      case 'vencida':
      case 'overdue':
        return 'overdue' as const;
      case 'cancelada':
      case 'cancelled':
        return 'cancelled' as const;
      default:
        return 'pending' as const;
    }
  }

  private mapInstallmentStatusToLocal(status: string) {
    switch (status.trim().toLowerCase()) {
      case 'paid':
        return 'pagada';
      case 'partial':
        return 'parcial';
      case 'overdue':
        return 'vencida';
      case 'cancelled':
        return 'cancelada';
      default:
        return 'pendiente';
    }
  }

  private mapPaymentMethodToBackend(method: string) {
    switch (method.trim().toLowerCase()) {
      case 'transferencia':
        return 'transfer' as const;
      case 'tarjeta':
        return 'card' as const;
      case 'cheque':
        return 'check' as const;
      case 'billetera':
      case 'wallet':
      case 'mobile_wallet':
        return 'mobile_wallet' as const;
      case 'mixto':
        return 'mixed' as const;
      default:
        return 'cash' as const;
    }
  }

  private mapPaymentMethodToLocal(method: string) {
    switch (method.trim().toLowerCase()) {
      case 'transfer':
        return 'transferencia';
      case 'card':
        return 'tarjeta';
      case 'check':
        return 'cheque';
      case 'mobile_wallet':
        return 'billetera';
      case 'mixed':
        return 'mixto';
      default:
        return 'efectivo';
    }
  }

  private toJsonValue(payload: Record<string, unknown>): Prisma.InputJsonValue {
    return JSON.parse(JSON.stringify(payload)) as Prisma.InputJsonValue;
  }

  private readJsonRecord(value: unknown): Record<string, unknown> | null {
    if (!value || Array.isArray(value) || typeof value !== 'object') {
      return null;
    }
    return value as Record<string, unknown>;
  }

  private serializeUserRecord(user: {
    id: string;
    syncId: string;
    fullName: string;
    email: string;
    username: string;
    passwordHash: string;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    userRoles: Array<{
      role: {
        code: RoleCode;
      };
    }>;
  }) {
    const primaryRole = user.userRoles[0]?.role.code;
    return {
      id: user.id,
      sync_id: user.syncId,
      version: 1,
      full_name: user.fullName,
      email: user.email,
      username: user.username,
      password_hash: user.passwordHash,
      password_reset_required: false,
      role: primaryRole === RoleCode.SUPER_ADMIN ? 'admin' : 'vendedor',
      is_active: user.isActive,
      created_at: user.createdAt.toISOString(),
      updated_at: user.updatedAt.toISOString(),
      password_updated_at: user.updatedAt.toISOString(),
      deleted_at: user.deletedAt?.toISOString(),
      sync_status: user.syncStatus,
    };
  }

  private serializeClientRecord(client: {
    id: string;
    syncId: string;
    firstName: string;
    lastName: string;
    documentId: string | null;
    phone: string | null;
    address: string | null;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
  }) {
    return {
      id: client.id,
      sync_id: client.syncId,
      version: 1,
      full_name: `${client.firstName} ${client.lastName}`.trim(),
      document_id: client.documentId ?? '',
      phone: client.phone,
      address: client.address,
      created_at: client.createdAt.toISOString(),
      updated_at: client.updatedAt.toISOString(),
      deleted_at: client.deletedAt?.toISOString(),
      sync_status: client.syncStatus,
    };
  }

  private serializeProductRecord(product: {
    id: string;
    syncId: string;
    code: string;
    name: string;
    price: Prisma.Decimal;
    financingPrice: Prisma.Decimal | null;
    stock: number;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    syncPayload: Prisma.JsonValue | null;
  }) {
    const payload = this.readJsonRecord(product.syncPayload);
    const productSyncData = this.buildProductSyncData(product, payload);
    return {
      ...(payload ?? {}),
      ...productSyncData,
      id: product.id,
      sync_id: product.syncId,
      version: Number(payload?.['version'] ?? 1),
      created_at: payload?.['created_at']?.toString() ?? product.createdAt.toISOString(),
      updated_at: payload?.['updated_at']?.toString() ?? product.updatedAt.toISOString(),
      deleted_at: payload?.['deleted_at']?.toString() ?? product.deletedAt?.toISOString(),
      sync_status: product.syncStatus,
    };
  }

  private serializeSellerRecord(seller: {
    id: string;
    syncId: string;
    name: string;
    documentId: string | null;
    phone: string | null;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
  }) {
    return {
      id: seller.id,
      sync_id: seller.syncId,
      version: 1,
      name: seller.name,
      full_name: seller.name,
      document_id: seller.documentId ?? '',
      phone: seller.phone,
      created_at: seller.createdAt.toISOString(),
      updated_at: seller.updatedAt.toISOString(),
      deleted_at: seller.deletedAt?.toISOString(),
      sync_status: seller.syncStatus,
    };
  }

  private serializeSaleRecord(sale: {
    id: string;
    syncId: string;
    saleDate: Date;
    principalAmount: Prisma.Decimal;
    financedAmount: Prisma.Decimal;
    downPayment: Prisma.Decimal;
    outstandingBalance: Prisma.Decimal;
    interestRate: Prisma.Decimal;
    termMonths: number;
    status: string;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    syncPayload: Prisma.JsonValue | null;
    client: { syncId: string };
    product: { syncId: string };
    seller: { syncId: string } | null;
  }) {
    const payload = this.readJsonRecord(sale.syncPayload);
    const salePrice = Number(payload?.['sale_price'] ?? sale.principalAmount);
    const downPaymentAmount = Number(payload?.['down_payment_amount'] ?? sale.downPayment);
    const requiredInitialPayment = Number(
      payload?.['required_initial_payment'] ?? downPaymentAmount,
    );
    const paidInitialPayment = Number(
      payload?.['paid_initial_payment'] ?? downPaymentAmount,
    );
    const pendingInitialPayment = Number(
      payload?.['pending_initial_payment'] ??
        Math.max(requiredInitialPayment - paidInitialPayment, 0),
    );
    return {
      ...(payload ?? {}),
      id: sale.id,
      sync_id: sale.syncId,
      version: Number(payload?.['version'] ?? 1),
      client_sync_id: payload?.['client_sync_id']?.toString() ?? sale.client.syncId,
      product_sync_id: payload?.['product_sync_id']?.toString() ?? sale.product.syncId,
      seller_sync_id: payload?.['seller_sync_id']?.toString() ?? sale.seller?.syncId,
      sale_date: payload?.['sale_date']?.toString() ?? sale.saleDate.toISOString(),
      sale_price: salePrice,
      financed_balance: Number(payload?.['financed_balance'] ?? sale.financedAmount),
      down_payment_percentage: Number(
        payload?.['down_payment_percentage'] ??
          (salePrice > 0
            ? this.roundCurrency((downPaymentAmount / salePrice) * 100)
            : 0),
      ),
      down_payment_amount: downPaymentAmount,
      required_initial_payment: requiredInitialPayment,
      paid_initial_payment: paidInitialPayment,
      pending_initial_payment: pendingInitialPayment,
      minimum_reserve_amount: payload?.['minimum_reserve_amount'] == null
          ? null
          : Number(payload?.['minimum_reserve_amount']),
      activation_date:
        payload?.['activation_date']?.toString() ??
        (sale.status === 'active' || sale.status === 'completed' || sale.status === 'overdue'
            ? sale.saleDate.toISOString()
            : null),
      monthly_interest: Number(payload?.['monthly_interest'] ?? sale.interestRate),
      installment_count: Number(payload?.['installment_count'] ?? sale.termMonths),
      pending_balance: Number(payload?.['pending_balance'] ?? sale.outstandingBalance),
      status: payload?.['status']?.toString() ?? this.mapSaleStatusToLocal(sale.status),
      created_at: payload?.['created_at']?.toString() ?? sale.createdAt.toISOString(),
      updated_at: payload?.['updated_at']?.toString() ?? sale.updatedAt.toISOString(),
      deleted_at: payload?.['deleted_at']?.toString() ?? sale.deletedAt?.toISOString(),
      sync_status: sale.syncStatus,
    };
  }

  private serializeInstallmentRecord(installment: {
    id: string;
    syncId: string;
    installmentNumber: number;
    dueDate: Date;
    amount: Prisma.Decimal;
    principalAmount: Prisma.Decimal;
    interestAmount: Prisma.Decimal;
    paidAmount: Prisma.Decimal;
    status: string;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    syncPayload: Prisma.JsonValue | null;
    sale: { syncId: string };
  }) {
    const payload = this.readJsonRecord(installment.syncPayload);
    const totalAmount = Number(payload?.['total_amount'] ?? installment.amount);
    const principalAmount = Number(payload?.['principal_amount'] ?? installment.principalAmount);
    const paidAmount = Number(payload?.['paid_amount'] ?? installment.paidAmount);
    const paidPrincipalAmount = Number(
      payload?.['paid_principal_amount'] ?? Math.min(principalAmount, paidAmount),
    );
    return {
      ...(payload ?? {}),
      id: installment.id,
      sync_id: installment.syncId,
      version: Number(payload?.['version'] ?? 1),
      sale_sync_id: payload?.['sale_sync_id']?.toString() ?? installment.sale.syncId,
      installment_number: Number(payload?.['installment_number'] ?? installment.installmentNumber),
      due_date: payload?.['due_date']?.toString() ?? installment.dueDate.toISOString(),
      opening_balance: Number(payload?.['opening_balance'] ?? totalAmount),
      total_amount: totalAmount,
      principal_amount: principalAmount,
      interest_amount: Number(payload?.['interest_amount'] ?? installment.interestAmount),
      paid_amount: paidAmount,
      paid_principal_amount: paidPrincipalAmount,
      paid_interest_amount: Number(
        payload?.['paid_interest_amount'] ?? Math.max(paidAmount - paidPrincipalAmount, 0),
      ),
      ending_balance: Number(
        payload?.['ending_balance'] ?? Math.max(totalAmount - paidAmount, 0),
      ),
      status: payload?.['status']?.toString() ?? this.mapInstallmentStatusToLocal(installment.status),
      created_at: payload?.['created_at']?.toString() ?? installment.createdAt.toISOString(),
      updated_at: payload?.['updated_at']?.toString() ?? installment.updatedAt.toISOString(),
      deleted_at: payload?.['deleted_at']?.toString() ?? installment.deletedAt?.toISOString(),
      sync_status: installment.syncStatus,
    };
  }

  private serializePaymentRecord(payment: {
    id: string;
    syncId: string;
    paymentDate: Date;
    amount: Prisma.Decimal;
    method: string;
    reference: string | null;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    syncPayload: Prisma.JsonValue | null;
    sale: { syncId: string; client: { syncId: string } };
    installment: { syncId: string } | null;
  }) {
    const payload = this.readJsonRecord(payment.syncPayload);
    return {
      ...(payload ?? {}),
      id: payment.id,
      sync_id: payment.syncId,
      version: Number(payload?.['version'] ?? 1),
      sale_sync_id: payload?.['sale_sync_id']?.toString() ?? payment.sale.syncId,
      client_sync_id: payload?.['client_sync_id']?.toString() ?? payment.sale.client.syncId,
      installment_sync_id: payload?.['installment_sync_id']?.toString() ?? payment.installment?.syncId,
      payment_date: payload?.['payment_date']?.toString() ?? payment.paymentDate.toISOString(),
      amount_paid: Number(payload?.['amount_paid'] ?? payment.amount),
      payment_method: payload?.['payment_method']?.toString() ?? this.mapPaymentMethodToLocal(payment.method),
      payment_type: payload?.['payment_type']?.toString() ?? (payment.installment == null ? 'inicial' : 'cuota'),
      reference: payload?.['reference']?.toString() ?? payment.reference,
      year_to_pay: payload?.['year_to_pay']?.toString() ?? payment.paymentDate.getFullYear().toString(),
      created_at: payload?.['created_at']?.toString() ?? payment.createdAt.toISOString(),
      updated_at: payload?.['updated_at']?.toString() ?? payment.updatedAt.toISOString(),
      deleted_at: payload?.['deleted_at']?.toString() ?? payment.deletedAt?.toISOString(),
      sync_status: payment.syncStatus,
    };
  }

  private buildProductSyncData(
    product: {
      syncId: string;
      code: string;
      name: string;
      price: Prisma.Decimal;
      stock: number;
      isActive: boolean;
    },
    payload: Record<string, unknown> | null,
  ) {
    const parsedCode = this.parseLotReference(product.code);
    const parsedName = this.parseLotReference(product.name);
    const blockNumber =
      payload?.['block_number']?.toString().trim() ||
      parsedCode?.blockNumber ||
      parsedName?.blockNumber ||
      'GEN';
    const lotNumber =
      payload?.['lot_number']?.toString().trim() ||
      parsedCode?.lotNumber ||
      parsedName?.lotNumber ||
      product.code.trim() ||
      product.syncId.slice(0, 8);
    const totalPrice = Number(product.price);
    const area = Number(payload?.['area'] ?? 0);
    const pricePerSquareMeter = Number(
      payload?.['price_per_square_meter'] ??
        (area > 0 ? this.roundCurrency(totalPrice / area) : totalPrice),
    );
    const status =
      payload?.['status']?.toString() ??
      (!product.isActive
          ? 'inactivo'
          : product.stock > 0
              ? 'disponible'
              : 'vendido');

    return {
      block_number: blockNumber,
      lot_number: lotNumber,
      area,
      price_per_square_meter: pricePerSquareMeter,
      status,
    };
  }

  private parseLotReference(value: string | null | undefined) {
    const normalized = value?.trim();
    if (!normalized) {
      return null;
    }

    const patterns = [
      /m(?:anzana)?\s*[-#:]*\s*([a-z0-9]+)\s*[-/ ]+s(?:olar)?\s*[-#:]*\s*([a-z0-9]+)/i,
      /^([a-z0-9]+)\s*[-/]\s*([a-z0-9]+)$/i,
      /([a-z0-9]+)\s+([a-z0-9]+)$/i,
    ];

    for (const pattern of patterns) {
      const match = pattern.exec(normalized);
      if (!match) {
        continue;
      }

      const blockNumber = match[1]?.trim();
      const lotNumber = match[2]?.trim();
      if (blockNumber && lotNumber) {
        return { blockNumber, lotNumber };
      }
    }

    return null;
  }

  private sanitizeJob(job: SyncQueuedJob): SyncJobResponseDto {
    return {
      jobId: job.jobId,
      status: job.status,
      receivedAt: job.receivedAt,
      startedAt: job.startedAt,
      finishedAt: job.finishedAt,
      counts: job.counts,
      result: job.result,
      error: job.error,
    };
  }

  private pruneJobs(): void {
    const maxJobs = 200;
    if (this.jobs.size <= maxJobs) {
      return;
    }

    const oldestKey = this.jobs.keys().next().value as string | undefined;
    if (oldestKey) {
      this.jobs.delete(oldestKey);
    }
  }
}