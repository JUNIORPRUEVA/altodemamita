import { BadRequestException, HttpException, HttpStatus, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { InstallmentStatus, Prisma, RoleCode, SaleStatus, SyncStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';

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

type SyncDownloadScope =
  | 'users'
  | 'roles'
  | 'user_roles'
  | 'role_permissions'
  | 'permissions'
  | 'clients'
  | 'products'
  | 'sellers'
  | 'sales'
  | 'installments'
  | 'payments';

type ManualRestoreScope =
  | 'company_profiles'
  | 'clients'
  | 'sellers'
  | 'products'
  | 'sales'
  | 'installments'
  | 'payments';

@Injectable()
export class SyncService {
  private readonly jobs = new Map<string, SyncQueuedJob>();
  private readonly logger = new Logger(SyncService.name);
  private static readonly manualRestoreScopes: ManualRestoreScope[] = [
    'company_profiles',
    'clients',
    'sellers',
    'products',
    'sales',
    'installments',
    'payments',
  ];

  constructor(
    private readonly prisma: PrismaService,
    private readonly accountingService: LoanAccountingService,
    private readonly realtimeEvents: RealtimeEventsService,
  ) {}

  async upload(batch: SyncUploadDto, context: { isPrimary: boolean } = { isPrimary: false }) {
    const records = this.normalizeRecords(batch.records);
    const counts = this.extractCounts(records);
    this.logger.log(
      `[sync-upload] service_start deviceId=${(batch.device_id ?? '').trim() || '<missing>'} ` +
        `counts=${this.formatCountsForLog(counts)}`,
    );
    const isLocalMaster = context.isPrimary && process.env['LOCAL_MASTER_MODE'] === 'true';
    if (isLocalMaster) {
      this.logger.warn(
        `[sync-upload] LOCAL_MASTER_MODE activo: conflictos de timestamp en scopes comerciales se resuelven a favor del local. deviceId=${(batch.device_id ?? '').trim() || '<missing>'}`,
      );
    }
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
      const result = await this.persistBatch(records, { isLocalMaster });
      const acknowledgedRecords = await this.buildUploadAckRecords(records);
      const acknowledgedCounts = this.extractCounts(acknowledgedRecords);
      const ackDiscrepancies = this.buildAckDiscrepancies(
        records,
        acknowledgedRecords,
      );
      job.status = 'completed';
      job.finishedAt = new Date().toISOString();
      job.result = result;
      this.logger.log(
        `[sync-upload] service_completed jobId=${jobId} ` +
          `input=${this.formatCountsForLog(counts)} ` +
          `acked=${this.formatCountsForLog(acknowledgedCounts)} ` +
          `uploaded=${this.formatCountsForLog(result.uploaded)} ` +
          `affectedSales=${result.affectedSales.length}`,
      );
      if (ackDiscrepancies.length > 0) {
        this.logger.warn(
          `[sync-upload] ack_discrepancy jobId=${jobId} ${ackDiscrepancies.join(' | ')}`,
        );
      }
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
      this.logger.error(
        `[sync-upload] service_failed jobId=${jobId} deviceId=${(batch.device_id ?? '').trim() || '<missing>'} error=${job.error}`,
      );
      this.realtimeEvents.publishSyncFailed(jobId, job.error);
      throw error;
    }
  }

  private formatCountsForLog(counts: Record<string, number>): string {
    return `{${Object.entries(counts)
      .map(([scope, count]) => `${scope}:${count}`)
      .join(', ')}}`;
  }

  getJob(jobId: string) {
    const job = this.jobs.get(jobId);
    if (!job) {
      throw new NotFoundException('Trabajo de sincronización no encontrado.');
    }

    return this.sanitizeJob(job);
  }

  async resetDatabase() {
    const now = new Date();
    const result = await this.prisma.$transaction(async (tx) => {
      const payments = await tx.payment.updateMany({
        data: { deletedAt: now, syncStatus: 'synced' },
      });
      const installments = await tx.installment.updateMany({
        data: { deletedAt: now, syncStatus: 'synced' },
      });
      const sales = await tx.sale.updateMany({
        data: { deletedAt: now, syncStatus: 'synced' },
      });
      const clients = await tx.client.updateMany({
        data: { deletedAt: now, syncStatus: 'synced' },
      });
      const sellers = await tx.seller.updateMany({
        data: { deletedAt: now, syncStatus: 'synced' },
      });
      const products = await tx.product.updateMany({
        data: { deletedAt: now, syncStatus: 'synced' },
      });

      return {
        payments: payments.count,
        installments: installments.count,
        sales: sales.count,
        clients: clients.count,
        sellers: sellers.count,
        products: products.count,
      };
    });

    return {
      message: 'Base de datos nube reseteada correctamente (soft-delete aplicado).',
      softDeleted: result,
      reset_at: new Date().toISOString(),
      recovery_note: 'Todos los registros han sido marcados como eliminados pero pueden ser recuperados si es necesario.',
    };
  }

  private async persistBatch(records: SyncRecordCollections, options: { isLocalMaster: boolean } = { isLocalMaster: false }) {
    const { isLocalMaster } = options;
    const affectedSales = new Set<string>();
    const domainEvents: SyncDomainEvent[] = [];
    const deletedSaleSyncIds = new Set(
      records.sales
        .map((sale) => sale as Record<string, unknown>)
        .filter((payload) => this.readDate(payload, ['deletedAt', 'deleted_at']) != null)
        .map((payload) => this.readRecordSyncId(payload)),
    );

    await this.prisma.$transaction(async (tx) => {
      await this.ensureSyncUserRoles(tx);

      for (const user of records.users) {
        const payload = user as Record<string, unknown>;
        const recordSyncId = this.readRecordSyncId(payload);
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        const existing = await this.findExistingUserRecord(tx, payload, recordSyncId);
        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.user.findUnique({
              where: { id: existing.id },
              include: {
                userRoles: {
                  where: { deletedAt: null },
                  include: { role: true },
                },
              },
            });
            this.throwManualConflict({
              scope: 'users',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeUserRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }

          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (existingMs > incomingMs) {
            const server = await tx.user.findUnique({
              where: { id: existing.id },
              include: {
                userRoles: {
                  where: { deletedAt: null },
                  include: { role: true },
                },
              },
            });
            this.throwManualConflict({
              scope: 'users',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeUserRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (deletedAt == null && existingMs === incomingMs) {
            continue;
          }
        }

        if (deletedAt != null) {
          if (!existing) {
            this.logger.warn(
              `[sync-upload][users] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
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
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        if (deletedAt != null) {
          const existing = await tx.client.findUnique({
            where: { syncId: recordSyncId },
            select: { id: true, syncId: true, updatedAt: true },
          });
          if (existing?.updatedAt) {
            if (!incomingUpdatedAt) {
              const server = await tx.client.findUnique({
                where: { id: existing.id },
                select: {
                  id: true,
                  syncId: true,
                  firstName: true,
                  lastName: true,
                  documentId: true,
                  phone: true,
                  address: true,
                  createdAt: true,
                  updatedAt: true,
                  deletedAt: true,
                  syncStatus: true,
                },
              });
              this.throwManualConflict({
                scope: 'clients',
                recordSyncId,
                localRecord: payload,
                serverRecord: server ? this.serializeClientRecord(server) : null,
                message:
                  'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
              });
            }
            if (existing.updatedAt.getTime() > incomingUpdatedAt.getTime() && !isLocalMaster) {
              const server = await tx.client.findUnique({
                where: { id: existing.id },
                select: {
                  id: true,
                  syncId: true,
                  firstName: true,
                  lastName: true,
                  documentId: true,
                  phone: true,
                  address: true,
                  createdAt: true,
                  updatedAt: true,
                  deletedAt: true,
                  syncStatus: true,
                },
              });
              this.throwManualConflict({
                scope: 'clients',
                recordSyncId,
                localRecord: payload,
                serverRecord: server ? this.serializeClientRecord(server) : null,
                message:
                  'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
              });
            }
          }
          if (!existing) {
            this.logger.warn(
              `[sync-upload][clients] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
            continue;
          }

          // Blindaje: no aplicar borrado si el cliente tiene ventas activas
          {
            const activeSaleCount = await tx.sale.count({
              where: {
                clientId: existing.id,
                deletedAt: null,
                status: { not: SaleStatus.cancelled },
              },
            });
            if (activeSaleCount > 0) {
              const server = await tx.client.findUnique({
                where: { id: existing.id },
                select: {
                  id: true,
                  syncId: true,
                  firstName: true,
                  lastName: true,
                  documentId: true,
                  phone: true,
                  address: true,
                  createdAt: true,
                  updatedAt: true,
                  deletedAt: true,
                  syncStatus: true,
                },
              });
              this.throwManualConflict({
                scope: 'clients',
                recordSyncId,
                localRecord: payload,
                serverRecord: server ? this.serializeClientRecord(server) : null,
                message:
                  'ENTITY_HAS_ACTIVE_SALES: No puedes eliminar este cliente porque tiene una venta activa relacionada. ' +
                  'Primero debes ir a Ventas y anular o eliminar esa venta.',
              });
            }
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
        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.client.findUnique({
              where: { id: existing.id },
              select: {
                id: true,
                syncId: true,
                firstName: true,
                lastName: true,
                documentId: true,
                phone: true,
                address: true,
                createdAt: true,
                updatedAt: true,
                deletedAt: true,
                syncStatus: true,
              },
            });
            this.throwManualConflict({
              scope: 'clients',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeClientRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }
          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (existingMs > incomingMs && !isLocalMaster) {
            const server = await tx.client.findUnique({
              where: { id: existing.id },
              select: {
                id: true,
                syncId: true,
                firstName: true,
                lastName: true,
                documentId: true,
                phone: true,
                address: true,
                createdAt: true,
                updatedAt: true,
                deletedAt: true,
                syncStatus: true,
              },
            });
            this.throwManualConflict({
              scope: 'clients',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeClientRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (deletedAt == null && existingMs === incomingMs) {
            continue;
          }
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
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const syncStatus = this.readString(payload, ['sync_status'])?.toLowerCase();
        const explicitOperation = this.readString(payload, ['operation'])?.toLowerCase();
        const isDeleteMutation =
          deletedAt != null ||
          explicitOperation === 'delete' ||
          syncStatus === 'pending_delete';
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        const existing = await tx.product.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });

        if (isDeleteMutation && existing && isLocalMaster) {
          const effectiveDeletedAt = deletedAt ?? incomingUpdatedAt ?? new Date();
          const persisted = await tx.product.update({
            where: { id: existing.id },
            data: {
              isActive: false,
              stock: 0,
              deletedAt: effectiveDeletedAt,
              updatedAt: incomingUpdatedAt ?? effectiveDeletedAt,
              syncStatus: SyncStatus.synced,
            },
            select: { id: true, syncId: true, updatedAt: true },
          });
          this.logger.warn(
            `[sync-upload][products] local_master_delete_wins syncId=${recordSyncId} deletedAt=${effectiveDeletedAt.toISOString()} localMaster=${isLocalMaster ? 'yes' : 'no'}`,
          );
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

        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.product.findUnique({
              where: { id: existing.id },
              select: {
                id: true,
                syncId: true,
                code: true,
                name: true,
                price: true,
                financingPrice: true,
                stock: true,
                isActive: true,
                createdAt: true,
                updatedAt: true,
                deletedAt: true,
                syncStatus: true,
                syncPayload: true,
              },
            });
            this.throwManualConflict({
              scope: 'products',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeProductRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }

          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (existingMs > incomingMs && !isLocalMaster) {
            const server = await tx.product.findUnique({
              where: { id: existing.id },
              select: {
                id: true,
                syncId: true,
                code: true,
                name: true,
                price: true,
                financingPrice: true,
                stock: true,
                isActive: true,
                createdAt: true,
                updatedAt: true,
                deletedAt: true,
                syncStatus: true,
                syncPayload: true,
              },
            });
            this.throwManualConflict({
              scope: 'products',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeProductRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (!isDeleteMutation && deletedAt == null && existingMs === incomingMs) {
            continue;
          }
        }
        if (isDeleteMutation && deletedAt != null) {
          if (!existing) {
            this.logger.warn(
              `[sync-upload][products] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
            continue;
          }

          // Permitir soft delete (mark as deleted_at) incluso con ventas activas
          // El blindaje contra deletes debe estar en la lógica de UI/hard-delete, no en soft delete
          // Soft delete solo marca el registro como inactivo, no lo elimina de la BD

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
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        const existing = await tx.seller.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.seller.findUnique({
              where: { id: existing.id },
              select: {
                id: true,
                syncId: true,
                name: true,
                documentId: true,
                phone: true,
                createdAt: true,
                updatedAt: true,
                deletedAt: true,
                syncStatus: true,
              },
            });
            this.throwManualConflict({
              scope: 'sellers',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeSellerRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }

          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (existingMs > incomingMs && !isLocalMaster) {
            const server = await tx.seller.findUnique({
              where: { id: existing.id },
              select: {
                id: true,
                syncId: true,
                name: true,
                documentId: true,
                phone: true,
                createdAt: true,
                updatedAt: true,
                deletedAt: true,
                syncStatus: true,
              },
            });
            this.throwManualConflict({
              scope: 'sellers',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeSellerRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (deletedAt == null && existingMs === incomingMs) {
            continue;
          }
        }
        if (deletedAt != null) {
          if (!existing) {
            this.logger.warn(
              `[sync-upload][sellers] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
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
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        const existing = await tx.sale.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true },
        });
        const saleDeleteContext = deletedAt != null && existing
          ? await this.loadSaleDeleteContext(tx, existing.id)
          : null;
        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.sale.findUnique({
              where: { id: existing.id },
              include: {
                client: { select: { syncId: true } },
                product: { select: { syncId: true } },
                seller: { select: { syncId: true } },
              },
            });
            this.throwManualConflict({
              scope: 'sales',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeSaleRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }

          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (
            existingMs > incomingMs &&
            !(deletedAt != null && this.canApplySafeSaleDelete(saleDeleteContext)) &&
            !isLocalMaster
          ) {
            const server = await tx.sale.findUnique({
              where: { id: existing.id },
              include: {
                client: { select: { syncId: true } },
                product: { select: { syncId: true } },
                seller: { select: { syncId: true } },
              },
            });
            this.throwManualConflict({
              scope: 'sales',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeSaleRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (deletedAt == null && existingMs === incomingMs) {
            affectedSales.add(existing.id);
            continue;
          }
        }
        if (deletedAt != null) {
          if (!existing) {
            this.logger.warn(
              `[sync-upload][sales] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
            continue;
          }

          const saleWithRelations =
            saleDeleteContext ?? (await this.loadSaleDeleteContext(tx, existing.id));

          const saleWasAlreadyDeleted = saleWithRelations?.deletedAt != null;

          await tx.payment.updateMany({
            where: { saleId: existing.id, deletedAt: null },
            data: {
              deletedAt,
              ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
              syncStatus: SyncStatus.synced,
            },
          });

          if (!saleWasAlreadyDeleted) {
            await tx.installment.updateMany({
              where: { saleId: existing.id, deletedAt: null },
              data: {
                deletedAt,
                status: InstallmentStatus.cancelled,
                ...(incomingUpdatedAt ? { updatedAt: incomingUpdatedAt } : {}),
                syncStatus: SyncStatus.synced,
              },
            });

            if (saleWithRelations?.product?.id) {
              await tx.product.update({
                where: { id: saleWithRelations.product.id },
                data: {
                  stock: { increment: 1 },
                  syncStatus: SyncStatus.synced,
                },
              });
            }
          }

          const persisted = await tx.sale.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              status: SaleStatus.cancelled,
              syncPayload: this.toJsonValue({
                ...payload,
                sync_id: recordSyncId,
                deleted_at: deletedAt.toISOString(),
                updated_at: (incomingUpdatedAt ?? deletedAt).toISOString(),
                status: 'cancelada',
              }),
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
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        const existing = await tx.installment.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true, saleId: true },
        });
        const installmentDeleteContext = deletedAt != null && existing
          ? await this.loadInstallmentDeleteContext(tx, existing.id)
          : null;
        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.installment.findUnique({
              where: { id: existing.id },
              include: { sale: { select: { syncId: true } } },
            });
            this.throwManualConflict({
              scope: 'installments',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializeInstallmentRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }

          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (
            existingMs > incomingMs &&
            !this.canApplyDependentInstallmentDelete(
              installmentDeleteContext,
              deletedSaleSyncIds,
            ) &&
            !isLocalMaster
          ) {
            const server = await tx.installment.findUnique({
              where: { id: existing.id },
              include: { sale: { select: { syncId: true } } },
            });
            this.throwManualConflict({
              scope: 'installments',
              recordSyncId,
              entity: 'installment',
              id: existing.id,
              saleId: existing.saleId,
              reason: 'server_newer_installment',
              localRecord: payload,
              serverRecord: server ? this.serializeInstallmentRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (deletedAt == null && existingMs === incomingMs) {
            if (existing.saleId) {
              affectedSales.add(existing.saleId);
            }
            continue;
          }
        }
        if (deletedAt != null) {
          if (!existing) {
            this.logger.warn(
              `[sync-upload][installments] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
            continue;
          }

          if (
            !this.canApplyDependentInstallmentDelete(
              installmentDeleteContext,
              deletedSaleSyncIds,
            )
          ) {
            this.throwManualConflict({
              scope: 'installments',
              recordSyncId,
              entity: 'installment',
              id: existing.id,
              saleId: existing.saleId,
              reason: 'parent_sale_not_deleted',
              localRecord: payload,
              serverRecord: installmentDeleteContext
                ? this.serializeInstallmentRecord(installmentDeleteContext)
                : null,
              message:
                'Conflicto de sincronizacion: no se puede borrar la cuota mientras la venta padre siga activa en la nube.',
            });
          }

          affectedSales.add(existing.saleId);
          const persisted = await tx.installment.update({
            where: { id: existing.id },
            data: {
              deletedAt,
              status: InstallmentStatus.cancelled,
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
        const deletedAt = this.readDate(payload, ['deletedAt', 'deleted_at']);
        const incomingUpdatedAt =
          this.readDate(payload, ['updatedAt', 'updated_at']) ?? deletedAt;
        const existing = await tx.payment.findUnique({
          where: { syncId: recordSyncId },
          select: { id: true, syncId: true, updatedAt: true, saleId: true },
        });
        if (existing?.updatedAt) {
          if (!incomingUpdatedAt) {
            const server = await tx.payment.findUnique({
              where: { id: existing.id },
              include: {
                sale: {
                  select: {
                    syncId: true,
                    client: { select: { syncId: true } },
                  },
                },
                installment: { select: { syncId: true } },
              },
            });
            this.throwManualConflict({
              scope: 'payments',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializePaymentRecord(server) : null,
              message:
                'Conflicto de sincronizacion: falta updated_at/deleted_at en el registro entrante.',
            });
          }

          const existingMs = existing.updatedAt.getTime();
          const incomingMs = incomingUpdatedAt.getTime();
          if (existingMs > incomingMs && !isLocalMaster) {
            const server = await tx.payment.findUnique({
              where: { id: existing.id },
              include: {
                sale: {
                  select: {
                    syncId: true,
                    client: { select: { syncId: true } },
                  },
                },
                installment: { select: { syncId: true } },
              },
            });
            this.throwManualConflict({
              scope: 'payments',
              recordSyncId,
              localRecord: payload,
              serverRecord: server ? this.serializePaymentRecord(server) : null,
              message:
                'Conflicto de sincronizacion: el servidor tiene una version mas reciente. No se aplico el cambio local automaticamente.',
            });
          }

          if (deletedAt == null && existingMs === incomingMs) {
            if (existing.saleId) {
              affectedSales.add(existing.saleId);
            }
            continue;
          }
        }
        if (deletedAt != null) {
          if (!existing) {
            this.logger.warn(
              `[sync-upload][payments] delete_ignored_not_found sync_id=${recordSyncId}`,
            );
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

      // Process user-specific permissions from desktop upload
      for (const permissionRecord of records.permissions) {
        const payload = permissionRecord as Record<string, unknown>;
        const usuarioId = this.readRequiredNumber(payload, ['usuario_id', 'userId']);
        const modulo = this.readRequiredString(payload, ['modulo', 'module']);
        const acciones = this.readRequiredString(payload, ['acciones', 'actions']);
        const syncStatus = this.readString(payload, ['sync_status', 'syncStatus']) ?? 'synced';

        // Soft-delete: mark permission as pending_delete
        if (syncStatus === 'pending_delete') {
          await tx.userPermission.updateMany({
            where: {
              user: { syncId: usuarioId.toString() },
              module: modulo,
            },
            data: { deletedAt: new Date(), syncStatus: SyncStatus.synced },
          });
          continue;
        }

        // Find user by syncId
        const user = await tx.user.findFirst({
          where: { syncId: usuarioId.toString() },
        });

        if (!user) {
          this.logger.warn(
            `[sync-upload][permissions] user_not_found usuario_sync_id=${usuarioId} module=${modulo}`,
          );
          continue;
        }

        // Upsert user permission
        const existingPerm = await tx.userPermission.findFirst({
          where: {
            userId: user.id,
            module: modulo,
          },
        });

        if (existingPerm) {
          await tx.userPermission.update({
            where: { id: existingPerm.id },
            data: {
              actions: acciones,
              deletedAt: null,
              syncStatus: SyncStatus.synced,
            },
          });
        } else {
          await tx.userPermission.create({
            data: {
              userId: user.id,
              module: modulo,
              actions: acciones,
              syncStatus: SyncStatus.synced,
            },
          });
        }
      }
    });

    for (const saleId of affectedSales) {
      const sale = await this.prisma.sale.findUnique({
        where: { id: saleId },
        select: { deletedAt: true },
      });
      if (!sale) {
        continue;
      }
      if (sale.deletedAt == null) {
        await this.accountingService.syncSaleAggregates(this.prisma, saleId);
      }
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
      this.prisma.client.findMany({
        where: this.buildDownloadWhere(scopeCursorDates.clients),
      }),
      this.prisma.product.findMany({
        where: this.buildDownloadWhere(scopeCursorDates.products),
      }),
      this.prisma.seller.findMany({
        where: this.buildDownloadWhere(scopeCursorDates.sellers),
      }),
      this.prisma.sale.findMany({
        where: this.buildDownloadWhere(scopeCursorDates.sales),
        include: {
          client: { select: { syncId: true } },
          product: { select: { syncId: true } },
          seller: { select: { syncId: true } },
        },
      }),
      this.prisma.installment.findMany({
        where: this.buildDownloadWhere(scopeCursorDates.installments),
        include: {
          sale: { select: { syncId: true } },
        },
      }),
      this.prisma.payment.findMany({
        where: this.buildDownloadWhere(scopeCursorDates.payments),
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

    const records = {
      users: users.map((item) => this.serializeUserRecord(item)),
      roles: roles.map((item) => this.serializeRoleRecord(item)),
      user_roles: userRoles.map((item) => this.serializeUserRoleRecord(item)),
      role_permissions: rolePermissions.map((item) =>
        this.serializeRolePermissionRecord(item),
      ),
      permissions: permissions.map((item) => this.serializePermissionRecord(item)),
      clients: clients.map((item) => this.serializeClientRecord(item)),
      products: products.map((item) => this.serializeProductRecord(item)),
      sellers: sellers.map((item) => this.serializeSellerRecord(item)),
      sales: sales.map((item) => this.serializeSaleRecord(item)),
      installments: installments.map((item) =>
        this.serializeInstallmentRecord(item),
      ),
      payments: payments.map((item) => this.serializePaymentRecord(item)),
    };

    return {
      device_id: query.device_id ?? null,
      updatedSince: query.updatedSince ?? null,
      server_time: requestStartedAt.toISOString(),
      scope_cursors: {
        users: this.resolveDownloadCursor(users, requestStartedAt),
        roles: this.resolveDownloadCursor(roles, requestStartedAt),
        user_roles: this.resolveDownloadCursor(userRoles, requestStartedAt),
        role_permissions: this.resolveDownloadCursor(
          rolePermissions,
          requestStartedAt,
        ),
        permissions: this.resolveDownloadCursor(permissions, requestStartedAt),
        clients: this.resolveDownloadCursor(clients, requestStartedAt),
        products: this.resolveDownloadCursor(products, requestStartedAt),
        sellers: this.resolveDownloadCursor(sellers, requestStartedAt),
        sales: this.resolveDownloadCursor(sales, requestStartedAt),
        installments: this.resolveDownloadCursor(
          installments,
          requestStartedAt,
        ),
        payments: this.resolveDownloadCursor(payments, requestStartedAt),
      },
      records,
      metadata: {
        users,
        roles,
        permissions,
      },
    };
  }

  async previewManualRestoreExport(params: {
    adminUserId: string;
    deviceId: string;
    requestIp?: string;
  }) {
    await this.assertManualRestoreAllowed(params.adminUserId);

    const [companyProfilesCount, clientsCount, sellersCount, productsCount, salesCount, installmentsCount, paymentsCount] =
      await this.prisma.$transaction([
        this.prisma.companyProfile.count({}),
        this.prisma.client.count({}),
        this.prisma.seller.count({}),
        this.prisma.product.count({}),
        this.prisma.sale.count({}),
        this.prisma.installment.count({}),
        this.prisma.payment.count({}),
      ]);

    const counts = {
      company_profiles: companyProfilesCount,
      clients: clientsCount,
      sellers: sellersCount,
      products: productsCount,
      sales: salesCount,
      installments: installmentsCount,
      payments: paymentsCount,
    };

    this.logger.warn(
      `[sync-restore-preview] userId=${params.adminUserId} deviceId=${params.deviceId || '<missing>'} ip=${params.requestIp ?? '<unknown>'} counts=${JSON.stringify(counts)}`,
    );

    return {
      server_time: new Date().toISOString(),
      ordered_scopes: SyncService.manualRestoreScopes,
      counts,
      has_data: Object.values(counts).some((value) => value > 0),
      mode: 'manual_emergency_restore',
    };
  }

  async downloadManualRestoreExport(params: {
    adminUserId: string;
    adminPassword: string;
    confirmationText: string;
    deviceId: string;
    requestIp?: string;
  }) {
    await this.assertManualRestoreAllowed(params.adminUserId);
    await this.assertManualRestoreCredentials(
      params.adminUserId,
      params.adminPassword,
      params.confirmationText,
    );

    const [companyProfiles, clients, sellers, products, sales, installments, payments] = await this.prisma.$transaction([
      this.prisma.companyProfile.findMany({ 
        orderBy: { updatedAt: 'asc' } 
      }),
      this.prisma.client.findMany({ 
        where: { deletedAt: null },
        orderBy: { updatedAt: 'asc' } 
      }),
      this.prisma.seller.findMany({ 
        where: { deletedAt: null },
        orderBy: { updatedAt: 'asc' } 
      }),
      this.prisma.product.findMany({ 
        where: { deletedAt: null },
        orderBy: { updatedAt: 'asc' } 
      }),
      this.prisma.sale.findMany({
        where: { deletedAt: null },
        include: {
          client: { select: { syncId: true } },
          product: { select: { syncId: true } },
          seller: { select: { syncId: true } },
        },
        orderBy: { updatedAt: 'asc' },
      }),
      this.prisma.installment.findMany({
        where: { deletedAt: null },
        include: {
          sale: { select: { syncId: true } },
        },
        orderBy: { updatedAt: 'asc' },
      }),
      this.prisma.payment.findMany({
        where: { deletedAt: null },
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

    const records = {
      company_profiles: companyProfiles.map((item) =>
        this.serializeCompanyProfileRecord(item),
      ),
      clients: clients.map((item) => this.serializeClientRecord(item)),
      sellers: sellers.map((item) => this.serializeSellerRecord(item)),
      products: products.map((item) => this.serializeProductRecord(item)),
      sales: sales.map((item) => this.serializeSaleRecord(item)),
      installments: installments.map((item) =>
        this.serializeInstallmentRecord(item),
      ),
      payments: payments.map((item) => this.serializePaymentRecord(item)),
    };

    const counts = {
      company_profiles: records.company_profiles.length,
      clients: records.clients.length,
      sellers: records.sellers.length,
      products: records.products.length,
      sales: records.sales.length,
      installments: records.installments.length,
      payments: records.payments.length,
    };

    this.logger.warn(
      `[sync-restore-download] exported_by=${params.adminUserId} deviceId=${params.deviceId || '<missing>'} ip=${params.requestIp ?? '<unknown>'} counts=${JSON.stringify(counts)}`,
    );

    return {
      server_time: new Date().toISOString(),
      mode: 'manual_emergency_restore',
      ordered_scopes: SyncService.manualRestoreScopes,
      counts,
      records,
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

  private async assertManualRestoreAllowed(adminUserId: string): Promise<void> {
    if (process.env['ALLOW_MANUAL_CLOUD_RESTORE'] !== 'true') {
      throw new HttpException(
        'RESTORE_FROM_CLOUD_DISABLED',
        HttpStatus.FORBIDDEN,
      );
    }

    const user = await this.prisma.user.findUnique({
      where: { id: adminUserId },
      include: {
        userRoles: {
          where: { deletedAt: null },
          include: { role: true },
        },
      },
    });

    if (!user || user.deletedAt != null || user.isActive !== true) {
      throw new HttpException('USER_NOT_ACTIVE', HttpStatus.FORBIDDEN);
    }

    const roleCodes = user.userRoles
      .map((item) => item.role.code)
      .filter((code) => code != null);
    const adminRoles = new Set<RoleCode>([RoleCode.SUPER_ADMIN, RoleCode.ADMIN]);
    const isAdmin = roleCodes.some((code) => adminRoles.has(code));

    if (!isAdmin) {
      throw new HttpException('RESTORE_ADMIN_REQUIRED', HttpStatus.FORBIDDEN);
    }
  }

  private async assertManualRestoreCredentials(
    adminUserId: string,
    adminPassword: string,
    confirmationText: string,
  ): Promise<void> {
    const normalizedPassword = adminPassword.trim();
    if (normalizedPassword.length === 0) {
      throw new BadRequestException('ADMIN_PASSWORD_REQUIRED');
    }

    if (confirmationText.trim().toUpperCase() != 'RESTAURAR') {
      throw new BadRequestException('RESTORE_CONFIRMATION_TEXT_INVALID');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: adminUserId },
      select: {
        passwordHash: true,
      },
    });
    if (!user) {
      throw new HttpException('USER_NOT_FOUND', HttpStatus.FORBIDDEN);
    }

    const passwordOk = await this.verifyStoredPassword(
      normalizedPassword,
      user.passwordHash,
    );
    if (!passwordOk) {
      throw new HttpException('ADMIN_PASSWORD_INVALID', HttpStatus.FORBIDDEN);
    }
  }

  private async verifyStoredPassword(
    password: string,
    storedHash: string,
  ): Promise<boolean> {
    const normalizedHash = storedHash.trim();
    if (!normalizedHash) {
      return false;
    }

    if (normalizedHash.startsWith('$2')) {
      return bcrypt.compare(password, normalizedHash);
    }

    if (normalizedHash.startsWith('v2$')) {
      const parts = normalizedHash.split('$');
      if (parts.length !== 4) {
        return false;
      }

      const iterations = Number(parts[1]);
      if (!Number.isFinite(iterations) || iterations <= 0) {
        return false;
      }

      const expected = this.buildLegacyV2PasswordHash(
        password,
        parts[2],
        iterations,
      );
      return this.safeEquals(expected, normalizedHash);
    }

    const separatorIndex = normalizedHash.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex >= normalizedHash.length - 1) {
      return false;
    }

    const salt = normalizedHash.slice(0, separatorIndex);
    const digest = createHash('sha256')
      .update(`${salt}::${password}`)
      .digest('hex');
    return this.safeEquals(`${salt}:${digest}`, normalizedHash);
  }

  private buildLegacyV2PasswordHash(
    password: string,
    salt: string,
    iterations: number,
  ): string {
    let bytes = Buffer.from(`${salt}::${password}`, 'utf8');
    const passwordBytes = Buffer.from(password, 'utf8');
    const saltBytes = Buffer.from(salt, 'utf8');

    for (let round = 0; round < iterations; round += 1) {
      bytes = createHash('sha256')
        .update(
          Buffer.concat([
            bytes,
            passwordBytes,
            saltBytes,
            Buffer.from([
              round & 0xff,
              (round >> 8) & 0xff,
              (round >> 16) & 0xff,
              (round >> 24) & 0xff,
            ]),
          ]),
        )
        .digest();
    }

    return `v2$${iterations}$${salt}$${bytes.toString('hex')}`;
  }

  private safeEquals(left: string, right: string): boolean {
    const leftBuffer = Buffer.from(left);
    const rightBuffer = Buffer.from(right);
    if (leftBuffer.length !== rightBuffer.length) {
      return false;
    }
    return timingSafeEqual(leftBuffer, rightBuffer);
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
                include: {
                  role: {
                    include: {
                      rolePermissions: {
                        where: { deletedAt: null },
                        include: { permission: true },
                      },
                    },
                  },
                },
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

  private buildAckDiscrepancies(
    inputRecords: SyncRecordCollections,
    acknowledgedRecords: SyncRecordCollections,
  ): string[] {
    const scopes: Array<keyof SyncRecordCollections> = [
      'users',
      'clients',
      'products',
      'sellers',
      'sales',
      'installments',
      'payments',
    ];
    const details: string[] = [];

    for (const scope of scopes) {
      const inputIds = new Set(this.collectInputSyncIds(inputRecords[scope]));
      const ackIds = new Set(this.collectInputSyncIds(acknowledgedRecords[scope]));
      const missingIds = [...inputIds].filter((syncId) => !ackIds.has(syncId));
      if (missingIds.length === 0) {
        continue;
      }

      const preview = missingIds.slice(0, 5).join(',');
      const suffix = missingIds.length > 5 ? ',...' : '';
      details.push(
        `scope=${scope} missing=${missingIds.length} sync_ids=[${preview}${suffix}]`,
      );
    }

    return details;
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

  private buildManualConflictPayload(params: {
    scope: string;
    recordSyncId: string;
    message: string;
    localRecord: Record<string, unknown>;
    serverRecord: Record<string, unknown> | null;
    entity?: string;
    id?: string;
    saleId?: string;
    reason?: string;
  }): Record<string, unknown> {
    const localVersion = this.readNumber(params.localRecord, ['version']);
    const serverVersion = params.serverRecord
      ? this.readNumber(params.serverRecord, ['version'])
      : null;

    return {
      message: params.message,
      scope: params.scope,
      strategy: 'manual',
      entity: params.entity ?? null,
      id: params.id ?? null,
      saleId: params.saleId ?? null,
      reason: params.reason ?? null,
      server_time: new Date().toISOString(),
      conflicts: [
        {
          scope: params.scope,
          record_sync_id: params.recordSyncId,
          entity: params.entity ?? null,
          id: params.id ?? null,
          saleId: params.saleId ?? null,
          reason: params.reason ?? null,
          local_version: localVersion,
          server_version: serverVersion,
          local_record: params.localRecord,
          server_record: params.serverRecord,
          message: params.message,
        },
      ],
      records: params.serverRecord ? [params.serverRecord] : [],
    };
  }

  private throwManualConflict(params: {
    scope: string;
    recordSyncId: string;
    message: string;
    localRecord: Record<string, unknown>;
    serverRecord: Record<string, unknown> | null;
    entity?: string;
    id?: string;
    saleId?: string;
    reason?: string;
  }): never {
    throw new HttpException(
      this.buildManualConflictPayload(params),
      HttpStatus.CONFLICT,
    );
  }

  private async loadSaleDeleteContext(tx: Prisma.TransactionClient, saleId: string) {
    return tx.sale.findUnique({
      where: { id: saleId },
      include: {
        client: { select: { syncId: true } },
        product: { select: { id: true, syncId: true } },
        seller: { select: { syncId: true } },
        payments: {
          where: { deletedAt: null },
          select: { id: true, syncId: true, updatedAt: true },
        },
        installments: {
          where: { deletedAt: null },
          select: { id: true },
        },
      },
    });
  }

  private canApplySafeSaleDelete(
    sale:
      | Awaited<ReturnType<SyncService['loadSaleDeleteContext']>>
      | null,
  ): boolean {
    return sale != null;
  }

  private async loadInstallmentDeleteContext(
    tx: Prisma.TransactionClient,
    installmentId: string,
  ) {
    return tx.installment.findUnique({
      where: { id: installmentId },
      include: {
        sale: {
          select: {
            id: true,
            syncId: true,
            status: true,
            deletedAt: true,
            payments: {
              where: { deletedAt: null },
              select: { id: true },
            },
          },
        },
      },
    });
  }

  private canApplyDependentInstallmentDelete(
    installment:
      | Awaited<ReturnType<SyncService['loadInstallmentDeleteContext']>>
      | null,
    deletedSaleSyncIds: Set<string>,
  ): boolean {
    if (!installment?.sale) {
      return false;
    }

    if (
      installment.sale.deletedAt != null ||
      installment.sale.status === SaleStatus.cancelled
    ) {
      return true;
    }

    if (deletedSaleSyncIds.has(installment.sale.syncId)) {
      return true;
    }

    return false;
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

  private parseScopeCursorDates(
    rawScopeCursors?: string,
    fallbackUpdatedSince?: string,
  ): Partial<Record<SyncDownloadScope, Date>> {
    const fallback = fallbackUpdatedSince ? new Date(fallbackUpdatedSince) : undefined;
    const parsed = rawScopeCursors
      ? this.readJsonRecord(this.safeParseJson(rawScopeCursors))
      : null;
    const scopes: SyncDownloadScope[] = [
      'users',
      'roles',
      'user_roles',
      'role_permissions',
      'permissions',
      'clients',
      'products',
      'sellers',
      'sales',
      'installments',
      'payments',
    ];

    return scopes.reduce<Partial<Record<SyncDownloadScope, Date>>>(
      (acc, scope) => {
        const value = parsed?.[scope];
        const parsedDate = typeof value === 'string' ? new Date(value) : fallback;
        if (parsedDate && !Number.isNaN(parsedDate.getTime())) {
          acc[scope] = parsedDate;
        }
        return acc;
      },
      {},
    );
  }

  private buildDownloadWhere(updatedSince?: Date) {
    const where: any = { deletedAt: null };
    if (updatedSince) {
      where.updatedAt = { gt: updatedSince };
    }
    return where;
  }

  private resolveDownloadCursor<T extends { updatedAt: Date }>(
    records: T[],
    requestStartedAt: Date,
  ): string {
    let latest = requestStartedAt;
    for (const record of records) {
      if (record.updatedAt.getTime() > latest.getTime()) {
        latest = record.updatedAt;
      }
    }
    return latest.toISOString();
  }

  private safeParseJson(value: string): unknown {
    try {
      return JSON.parse(value);
    } catch {
      return null;
    }
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
        rolePermissions?: Array<{ permission: { code: string } }>;
      };
    }>;
  }) {
    const primaryRole = user.userRoles[0]?.role.code;
    const permissions = primaryRole === RoleCode.SUPER_ADMIN
      ? Object.values(PERMISSIONS)
      : Array.from(
          new Set(
            user.userRoles.flatMap((item) =>
              item.role.rolePermissions?.map((permission) => permission.permission.code) ?? [],
            ),
          ),
        ).sort();
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
      permissions,
      created_at: user.createdAt.toISOString(),
      updated_at: user.updatedAt.toISOString(),
      password_updated_at: user.updatedAt.toISOString(),
      deleted_at: user.deletedAt?.toISOString(),
      sync_status: user.syncStatus,
    };
  }

  private serializeRoleRecord(role: {
    id: string;
    syncId: string;
    code: RoleCode;
    name: string;
    description: string | null;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
  }) {
    return {
      id: role.id,
      sync_id: role.syncId,
      version: 1,
      code: role.code,
      name: role.name,
      description: role.description,
      created_at: role.createdAt.toISOString(),
      updated_at: role.updatedAt.toISOString(),
      deleted_at: role.deletedAt?.toISOString(),
      sync_status: role.syncStatus,
    };
  }

  private serializeUserRoleRecord(link: {
    id: string;
    userId: string;
    roleId: string;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    user: { syncId: string };
    role: { syncId: string };
  }) {
    return {
      id: link.id,
      sync_id: `${link.user.syncId}:${link.role.syncId}`,
      version: 1,
      user_id: link.userId,
      role_id: link.roleId,
      user_sync_id: link.user.syncId,
      role_sync_id: link.role.syncId,
      created_at: link.createdAt.toISOString(),
      updated_at: link.updatedAt.toISOString(),
      deleted_at: link.deletedAt?.toISOString(),
      sync_status: link.syncStatus,
    };
  }

  private serializeRolePermissionRecord(link: {
    id: string;
    roleId: string;
    permissionId: string;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
    role: { syncId: string };
    permission: { syncId: string; code: string };
  }) {
    return {
      id: link.id,
      sync_id: `${link.role.syncId}:${link.permission.syncId}`,
      version: 1,
      role_id: link.roleId,
      permission_id: link.permissionId,
      role_sync_id: link.role.syncId,
      permission_sync_id: link.permission.syncId,
      permission_code: link.permission.code,
      created_at: link.createdAt.toISOString(),
      updated_at: link.updatedAt.toISOString(),
      deleted_at: link.deletedAt?.toISOString(),
      sync_status: link.syncStatus,
    };
  }

  private serializePermissionRecord(permission: {
    id: string;
    syncId: string;
    code: string;
    name: string;
    description: string | null;
    createdAt: Date;
    updatedAt: Date;
    deletedAt: Date | null;
    syncStatus: SyncStatus;
  }) {
    return {
      id: permission.id,
      sync_id: permission.syncId,
      version: 1,
      code: permission.code,
      name: permission.name,
      description: permission.description,
      created_at: permission.createdAt.toISOString(),
      updated_at: permission.updatedAt.toISOString(),
      deleted_at: permission.deletedAt?.toISOString(),
      sync_status: permission.syncStatus,
    };
  }

  private serializeCompanyProfileRecord(profile: {
    id: string;
    name: string;
    phone: string | null;
    address: string | null;
    logoBase64: string | null;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: profile.id,
      sync_id: profile.id,
      name: profile.name,
      phone: profile.phone,
      address: profile.address,
      logo_base64: profile.logoBase64,
      created_at: profile.createdAt.toISOString(),
      updated_at: profile.updatedAt.toISOString(),
      deleted_at: null,
      sync_status: SyncStatus.synced,
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
      // pending_balance: use syncPayload value (client's calculation) as primary — the
      // backend outstandingBalance uses a different accounting formula. The client
      // reconcile (_reconcileSalesFromPayments) corrects this after every merge.
      pending_balance: Number(payload?.['pending_balance'] ?? sale.outstandingBalance),
      // Live state/timestamp — always reflect current Prisma state after syncSaleAggregates:
      status: this.mapSaleStatusToLocal(sale.status),
      created_at: payload?.['created_at']?.toString() ?? sale.createdAt.toISOString(),
      updated_at: sale.updatedAt.toISOString(),
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
    // Structural/immutable fields come from syncPayload (set at creation, never change).
    const totalAmount = Number(payload?.['total_amount'] ?? installment.amount);
    const principalAmount = Number(payload?.['principal_amount'] ?? installment.principalAmount);
    // ─── CRITICAL FIX ───────────────────────────────────────────────────────────
    // Financial/state fields MUST come from live Prisma data, NOT from syncPayload.
    // syncSaleAggregates updates installment.paidAmount and installment.status in
    // Prisma after every payment upload, but it never updates syncPayload. Using
    // syncPayload here causes downloads to always return the original stale
    // paid_amount=0/status=vencida regardless of how many payments have been applied,
    // creating an infinite reset loop on the client.
    // ────────────────────────────────────────────────────────────────────────────
    const paidAmount = this.roundCurrency(Number(installment.paidAmount));
    // Interest is applied before principal (matches resolvePaymentSplit in payments.service.ts):
    const installmentInterest = Number(payload?.['interest_amount'] ?? installment.interestAmount);
    const paidInterestAmount = this.roundCurrency(Math.min(installmentInterest, paidAmount));
    const paidPrincipalAmount = this.roundCurrency(Math.max(paidAmount - paidInterestAmount, 0));
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
      // Live accounting fields — always reflect current Prisma state after syncSaleAggregates:
      paid_amount: paidAmount,
      paid_principal_amount: paidPrincipalAmount,
      paid_interest_amount: paidInterestAmount,
      ending_balance: this.roundCurrency(Math.max(totalAmount - paidAmount, 0)),
      status: this.mapInstallmentStatusToLocal(installment.status),
      created_at: payload?.['created_at']?.toString() ?? installment.createdAt.toISOString(),
      updated_at: installment.updatedAt.toISOString(),
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
