import { createHash } from 'node:crypto';

import { Injectable } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { RealtimeGateway } from './realtime.gateway';

export interface RealtimeEntityPayload {
  entity: string;
  action: 'created' | 'updated' | 'deleted';
  id: string;
  recordSyncId: string;
  data?: Record<string, unknown>;
  source: 'api' | 'sync';
  updatedAt?: string;
}

@Injectable()
export class RealtimeEventsService {
  constructor(private readonly gateway: RealtimeGateway) {}

  publishSyncAccepted(jobId: string, counts: Record<string, number>): void {
    this.emit('sync.job.accepted', { jobId, counts }, [
      this.gateway.buildPermissionRoom(PERMISSIONS.syncManage),
    ]);
  }

  publishSyncStarted(jobId: string): void {
    this.emit('sync.job.started', { jobId }, [
      this.gateway.buildPermissionRoom(PERMISSIONS.syncManage),
    ]);
  }

  publishSyncCompleted(jobId: string, result: Record<string, unknown>): void {
    this.emit('sync.job.completed', { jobId, result }, [
      this.gateway.buildPermissionRoom(PERMISSIONS.syncManage),
    ]);
  }

  publishSyncFailed(jobId: string, error: string): void {
    this.emit('sync.job.failed', { jobId, error }, [
      this.gateway.buildPermissionRoom(PERMISSIONS.syncManage),
    ]);
  }

  publishSaleCreated(
    id: string,
    recordSyncId: string,
    data: Record<string, unknown>,
    source: 'api' | 'sync',
    updatedAt?: string,
  ): void {
    this.emit('sale.created', {
      id,
      record_sync_id: recordSyncId,
      sync_id: recordSyncId,
      data,
      source,
      updated_at: updatedAt,
    }, this.buildOperationalReadRooms());
  }

  publishPaymentCreated(
    id: string,
    recordSyncId: string,
    data: Record<string, unknown>,
    source: 'api' | 'sync',
    updatedAt?: string,
  ): void {
    this.emit('payment.created', {
      id,
      record_sync_id: recordSyncId,
      sync_id: recordSyncId,
      data,
      source,
      updated_at: updatedAt,
    }, this.buildOperationalReadRooms());
  }

  publishEntityUpdated(payload: RealtimeEntityPayload): void {
    this.emit('entity.updated', {
      ...payload,
      record_sync_id: payload.recordSyncId,
      sync_id: payload.recordSyncId,
      updated_at: payload.updatedAt,
    }, this.buildOperationalReadRooms());
  }

  private emit(event: string, payload: Record<string, unknown>, rooms: string[]): void {
    const emittedAt = new Date().toISOString();
    const eventId = this.buildEventId(event, payload);
    this.gateway.emitToRooms(event, {
      ...payload,
      event_id: eventId,
      emittedAt,
    }, rooms);
  }

  private buildOperationalReadRooms(): string[] {
    return [
      this.gateway.buildPermissionRoom(PERMISSIONS.reportsRead),
      this.gateway.buildPermissionRoom(PERMISSIONS.clientsRead),
      this.gateway.buildPermissionRoom(PERMISSIONS.productsRead),
      this.gateway.buildPermissionRoom(PERMISSIONS.salesRead),
      this.gateway.buildPermissionRoom(PERMISSIONS.paymentsRead),
      this.gateway.buildPermissionRoom(PERMISSIONS.installmentsRead),
      this.gateway.buildPermissionRoom(PERMISSIONS.usersRead),
    ];
  }

  private buildEventId(event: string, payload: Record<string, unknown>): string {
    const parts = [
      event,
      this.readString(payload.record_sync_id),
      this.readString(payload.sync_id),
      this.readString(payload.id),
      this.readString(payload.jobId),
      this.readString(payload.action),
      this.readString(payload.updated_at),
      this.readString(payload.source),
      JSON.stringify(payload.data ?? payload.result ?? payload.counts ?? null),
    ];

    return createHash('sha1').update(parts.join('::')).digest('hex');
  }

  private readString(value: unknown): string {
    return typeof value === 'string' ? value : value?.toString() ?? '';
  }
}