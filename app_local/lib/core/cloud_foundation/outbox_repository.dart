import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum OutboxStatus {
  pending('PENDING'),
  processing('PROCESSING'),
  synced('SYNCED'),
  failedRetryable('FAILED_RETRYABLE'),
  blockedConflict('BLOCKED_CONFLICT');

  const OutboxStatus(this.value);

  final String value;

  static OutboxStatus fromStorage(String value) {
    final normalized = value.trim().toUpperCase();
    final legacyAliases = {
      'SENDING': OutboxStatus.processing,
      'ACKNOWLEDGED': OutboxStatus.synced,
      'RETRYABLE_FAILURE': OutboxStatus.failedRetryable,
      'PERMANENT_FAILURE': OutboxStatus.blockedConflict,
    };
    final legacy = legacyAliases[normalized];
    if (legacy != null) {
      return legacy;
    }
    return OutboxStatus.values.firstWhere(
      (status) => status.value == normalized,
      orElse: () => OutboxStatus.pending,
    );
  }
}

class OutboxOperation {
  const OutboxOperation({
    required this.operationId,
    required this.operationType,
    required this.payload,
    required this.payloadHash,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.dependencyKey,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.lastSafeError,
    this.serverAck,
  });

  final String operationId;
  final String operationType;
  final Map<String, Object?> payload;
  final String payloadHash;
  final OutboxStatus status;
  final String? dependencyKey;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final String? lastSafeError;
  final Map<String, Object?>? serverAck;

  factory OutboxOperation.fromMap(Map<String, Object?> map) {
    return OutboxOperation(
      operationId: map['operation_id'] as String,
      operationType: map['operation_type'] as String,
      payload: _decodeMap(map['payload']),
      payloadHash: map['payload_hash'] as String,
      status: OutboxStatus.fromStorage(map['status'] as String),
      dependencyKey: map['dependency_key'] as String?,
      attemptCount: map['attempt_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastAttemptAt: _readDate(map['last_attempt_at']),
      nextRetryAt: _readDate(map['next_retry_at']),
      lastSafeError: map['last_safe_error'] as String?,
      serverAck: map['server_ack'] == null
          ? null
          : _decodeMap(map['server_ack']),
    );
  }
}

class OutboxRepository {
  const OutboxRepository(this.database);

  final Database database;

  Future<OutboxOperation> enqueue({
    required String operationId,
    required String operationType,
    required Map<String, Object?> payload,
    String? dependencyKey,
  }) async {
    final existing = await find(operationId);
    final payloadHash = hashPayload(operationType, payload);
    if (existing != null) {
      if (existing.payloadHash != payloadHash) {
        throw StateError(
          'Operation ID already exists with a different payload hash.',
        );
      }
      return existing;
    }

    final now = DateTime.now().toUtc();
    await database.insert('outbox_operations', {
      'operation_id': operationId,
      'operation_type': operationType,
      'payload': jsonEncode(payload),
      'payload_hash': payloadHash,
      'status': OutboxStatus.pending.value,
      'dependency_key': dependencyKey,
      'attempt_count': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'next_retry_at': now.toIso8601String(),
    });
    return (await find(operationId))!;
  }

  Future<OutboxOperation?> find(String operationId) async {
    final rows = await database.query(
      'outbox_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : OutboxOperation.fromMap(rows.first);
  }

  Future<List<OutboxOperation>> dueOperations({DateTime? now}) async {
    final reference = (now ?? DateTime.now().toUtc()).toIso8601String();
    final rows = await database.query(
      'outbox_operations',
      where:
          "status IN ('PENDING', 'FAILED_RETRYABLE', 'RETRYABLE_FAILURE') AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [reference],
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxOperation.fromMap).toList(growable: false);
  }

  Future<void> markSending(String operationId) async {
    final now = DateTime.now().toUtc();
    await database.update(
      'outbox_operations',
      {
        'status': OutboxStatus.processing.value,
        'last_attempt_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> acknowledge(
    String operationId,
    Map<String, Object?> serverAck,
  ) async {
    final now = DateTime.now().toUtc();
    await database.update(
      'outbox_operations',
      {
        'status': OutboxStatus.synced.value,
        'server_ack': jsonEncode(serverAck),
        'updated_at': now.toIso8601String(),
        'last_safe_error': null,
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> failRetryable(String operationId, String safeError) async {
    final current = await find(operationId);
    final attempts = (current?.attemptCount ?? 0) + 1;
    final now = DateTime.now().toUtc();
    final delaySeconds = _backoffSeconds(attempts);
    await database.update(
      'outbox_operations',
      {
        'status': OutboxStatus.failedRetryable.value,
        'attempt_count': attempts,
        'last_safe_error': safeError,
        'next_retry_at': now
            .add(Duration(seconds: delaySeconds))
            .toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> failPermanent(String operationId, String safeError) async {
    final current = await find(operationId);
    final now = DateTime.now().toUtc();
    await database.update(
      'outbox_operations',
      {
        'status': OutboxStatus.blockedConflict.value,
        'attempt_count': (current?.attemptCount ?? 0) + 1,
        'last_safe_error': safeError,
        'updated_at': now.toIso8601String(),
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }
}

String hashPayload(String operationType, Map<String, Object?> payload) {
  return sha256
      .convert(
        utf8.encode(
          _stableEncode({'operationType': operationType, 'payload': payload}),
        ),
      )
      .toString();
}

int _backoffSeconds(int attempts) {
  final clamped = attempts.clamp(1, 6);
  return 5 * (1 << (clamped - 1));
}

String _stableEncode(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(_stableEncode).join(',')}]';
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_stableEncode(value[key])}').join(',')}}';
  }
  return jsonEncode(value.toString());
}

Map<String, Object?> _decodeMap(Object? raw) {
  final decoded = jsonDecode(raw?.toString() ?? '{}');
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

DateTime? _readDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text);
}
