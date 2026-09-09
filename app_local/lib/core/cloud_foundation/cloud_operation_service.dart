import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../config/app_flags.dart';
import 'cache_repository.dart';
import 'outbox_repository.dart';

class CloudOperationService {
  const CloudOperationService({
    required OutboxRepository outbox,
    required CacheRepository cache,
    required CloudCutoverMode mode,
  }) : _outbox = outbox,
       _cache = cache,
       _mode = mode;

  final OutboxRepository _outbox;
  final CacheRepository _cache;
  final CloudCutoverMode _mode;

  Future<QueuedCloudOperation> createSale({
    required String stableBusinessKey,
    required Map<String, Object?> payload,
  }) async {
    _ensureCloudMode();
    final operationId = stableOperationId('sale.create', stableBusinessKey);
    final operation = await _outbox.enqueue(
      operationId: operationId,
      operationType: 'sale.create',
      payload: {...payload, 'operationId': operationId},
      dependencyKey: payload['lotSyncId']?.toString(),
    );
    await _cache.upsertRecord(
      entity: 'sales',
      id: operationId,
      syncId: payload['syncId']?.toString(),
      payload: {
        ...payload,
        'operationId': operationId,
        'pending': true,
        'serverConfirmed': false,
      },
      status: 'PENDING',
    );
    return QueuedCloudOperation(operationId: operationId, operation: operation);
  }

  Future<QueuedCloudOperation> registerPayment({
    required String stableBusinessKey,
    required Map<String, Object?> payload,
  }) async {
    _ensureCloudMode();
    final operationId = stableOperationId(
      'payment.register',
      stableBusinessKey,
    );
    final operation = await _outbox.enqueue(
      operationId: operationId,
      operationType: 'payment.register',
      payload: {...payload, 'operationId': operationId},
      dependencyKey:
          payload['saleId']?.toString() ?? payload['saleSyncId']?.toString(),
    );
    await _cache.upsertRecord(
      entity: 'payments',
      id: operationId,
      syncId: payload['syncId']?.toString(),
      payload: {
        ...payload,
        'operationId': operationId,
        'pending': true,
        'serverConfirmed': false,
      },
      status: 'PENDING',
    );
    return QueuedCloudOperation(operationId: operationId, operation: operation);
  }

  void _ensureCloudMode() {
    if (!_mode.usesAuthoritativeBusinessWrites) {
      throw StateError(
        'Cloud operation service is disabled outside CLOUD_UAT/CLOUD_AUTHORITATIVE.',
      );
    }
  }
}

class QueuedCloudOperation {
  const QueuedCloudOperation({
    required this.operationId,
    required this.operation,
  });

  final String operationId;
  final OutboxOperation operation;
}

String stableOperationId(String operationType, String stableBusinessKey) {
  final source = '$operationType:$stableBusinessKey';
  return '$operationType:${sha256.convert(utf8.encode(source)).toString()}';
}
