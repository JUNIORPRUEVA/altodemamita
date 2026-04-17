import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Prisma, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
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
  clients: Record<string, unknown>[];
  products: Record<string, unknown>[];
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
        records: this.emptyRecords(),
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

  private async persistBatch(records: SyncRecordCollections) {
    const affectedSales = new Set<string>();
    const domainEvents: SyncDomainEvent[] = [];

    await this.prisma.$transaction(async (tx) => {
      for (const client of records.clients) {
        const payload = client as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const { firstName, lastName } = this.resolveClientNames(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const existing = await tx.client.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }

        const persisted = await tx.client.upsert({
          where: { syncId: recordSyncId },
          create: {
            syncId: recordSyncId,
            code: this.readString(payload, ['code']),
            firstName,
            lastName,
            documentId: this.readString(payload, ['documentId', 'document_id']),
            email: this.readString(payload, ['email']),
            phone: this.readString(payload, ['phone']),
            address: this.readString(payload, ['address']),
            notes: this.readString(payload, ['notes']),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
            syncStatus: SyncStatus.synced,
          },
          update: {
            code: this.readString(payload, ['code']),
            firstName,
            lastName,
            documentId: this.readString(payload, ['documentId', 'document_id']),
            email: this.readString(payload, ['email']),
            phone: this.readString(payload, ['phone']),
            address: this.readString(payload, ['address']),
            notes: this.readString(payload, ['notes']),
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
        const blockNumber = this.readRequiredString(payload, ['block_number']);
        const lotNumber = this.readRequiredString(payload, ['lot_number']);
        const area = this.readRequiredNumber(payload, ['area']);
        const pricePerSquareMeter = this.readRequiredNumber(payload, ['price_per_square_meter']);
        const localStatus = this.readString(payload, ['status']) ?? 'disponible';
        const totalPrice = this.roundCurrency(area * pricePerSquareMeter);
        const existing = await tx.product.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }

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
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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

      for (const sale of records.sales) {
        const payload = sale as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const incomingUpdatedAt = this.readDate(payload, ['updatedAt', 'updated_at']);
        const salePrice = this.readRequiredNumber(payload, ['sale_price']);
        const financedBalance = this.readRequiredNumber(payload, ['financed_balance']);
        const downPaymentAmount = this.readRequiredNumber(payload, ['down_payment_amount']);
        const pendingBalance = this.readRequiredNumber(payload, ['pending_balance']);
        const monthlyInterest = this.readRequiredNumber(payload, ['monthly_interest']);
        const installmentCount = this.readRequiredInt(payload, ['installment_count']);
        const localStatus = this.readString(payload, ['status']) ?? 'activa';
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

        const client = await this.resolveClientReference(tx, payload);
        const user = await this.resolveSyncUser(tx, payload);
        const product = await this.resolveProductReference(tx, payload);
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
              status: localStatus,
            }),
            createdAt: this.readDate(payload, ['createdAt', 'created_at']) ?? undefined,
            updatedAt: incomingUpdatedAt ?? undefined,
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
            syncStatus: SyncStatus.synced,
          },
          update: {
            clientId: client.id,
            userId: user.id,
            productId: product.id,
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
              status: localStatus,
            }),
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
        const installmentNumber = this.readRequiredInt(payload, ['installment_number']);
        const dueDate = this.readRequiredDate(payload, ['due_date']);
        const totalAmount = this.readRequiredNumber(payload, ['total_amount']);
        const principalAmount = this.readRequiredNumber(payload, ['principal_amount']);
        const interestAmount = this.readRequiredNumber(payload, ['interest_amount']);
        const paidAmount = this.readNumber(payload, ['paid_amount']) ?? 0;
        const localStatus = this.readString(payload, ['status']) ?? 'pendiente';
        const existing = await tx.installment.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        const saleRecord = await this.resolveSaleReference(tx, payload);
        if (!saleRecord) {
          throw new BadRequestException('No se pudo resolver la venta de la cuota.');
        }
        affectedSales.add(saleRecord.id);
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }

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
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
        const paymentDate = this.readRequiredDate(payload, ['payment_date']);
        const amountPaid = this.readRequiredNumber(payload, ['amount_paid']);
        const paymentMethod = this.readString(payload, ['payment_method']) ?? 'efectivo';
        const paymentType = this.readString(payload, ['payment_type']) ?? 'cuota';
        const existing = await tx.payment.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        const saleRecord = await this.resolveSaleReference(tx, payload);
        const installmentRecord = await this.resolveInstallmentReference(tx, payload, true);
        if (!saleRecord) {
          throw new BadRequestException('No se pudo resolver la venta del pago.');
        }
        affectedSales.add(saleRecord.id);
        if (this.shouldSkipWrite(existing?.updatedAt, incomingUpdatedAt)) {
          continue;
        }

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
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
            deletedAt: this.readDate(payload, ['deletedAt', 'deleted_at']),
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
        clients: records.clients.length,
        products: records.products.length,
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

    const [users, roles, permissions, clients, products, sales, installments, payments] = await this.prisma.$transaction([
      this.prisma.user.findMany({ where }),
      this.prisma.role.findMany({ where }),
      this.prisma.permission.findMany({ where }),
      this.prisma.client.findMany({ where }),
      this.prisma.product.findMany({ where }),
      this.prisma.sale.findMany({
        where,
        include: {
          client: { select: { syncId: true } },
          product: { select: { syncId: true } },
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
        clients: clients.map((item) => this.serializeClientRecord(item)),
        products: products.map((item) => this.serializeProductRecord(item)),
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

    validateCollection('clients', records.clients, [], []);
    for (const [index, client] of records.clients.entries()) {
      const payload = client as Record<string, unknown>;
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
      clients: records?.clients ?? [],
      products: records?.products ?? [],
      sales: records?.sales ?? [],
      installments: records?.installments ?? [],
      payments: records?.payments ?? [],
    };
  }

  private emptyRecords(): SyncRecordCollections {
    return {
      clients: [],
      products: [],
      sales: [],
      installments: [],
      payments: [],
    };
  }

  private normalizeRecordSyncId(payload: Record<string, unknown>): string | null {
    const value = payload.record_sync_id ?? payload.sync_id;
    const normalized = value?.toString().trim();
    return normalized ? normalized : null;
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

  private async resolveClientReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.client, payload, ['client_sync_id'], ['clientId', 'client_id'], 'cliente');
  }

  private async resolveUserReference(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    return this.resolveReference(tx.user, payload, ['user_sync_id'], ['userId', 'user_id'], 'usuario');
  }

  private async resolveSyncUser(tx: Prisma.TransactionClient, payload: Record<string, unknown>) {
    const explicitUser = await this.resolveUserReference(tx, payload);
    if (explicitUser) {
      return explicitUser;
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
        OR: [
          { syncId: reference },
          { id: reference },
        ],
      },
      select: { id: true, syncId: true },
    });

    if (!entity && !optional) {
      throw new BadRequestException(`No existe ${label} para la referencia '${reference}'.`);
    }

    return entity;
  }

  private extractCounts(records: SyncRecordCollections): Record<string, number> {
    return {
      clients: records.clients.length,
      products: records.products.length,
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