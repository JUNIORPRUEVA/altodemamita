import 'dart:async';
import 'dart:convert';

import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import '../../repositories/products_sync_repository.dart';
import 'sync_api_client.dart';
import 'sync_queue_service.dart';

class SyncConflictRecord {
  const SyncConflictRecord({
    required this.scope,
    required this.recordSyncId,
    required this.strategy,
    required this.message,
    required this.conflictReason,
    required this.detectedAt,
    this.localVersion,
    this.serverVersion,
    this.serverTime,
    this.localPayload,
    this.serverPayload,
  });

  final String scope;
  final String recordSyncId;
  final String strategy;
  final String message;
  final String conflictReason;
  final int? localVersion;
  final int? serverVersion;
  final DateTime detectedAt;
  final DateTime? serverTime;
  final Map<String, dynamic>? localPayload;
  final Map<String, dynamic>? serverPayload;

  bool get hasServerPayload =>
      serverPayload != null && serverPayload!.isNotEmpty;

  factory SyncConflictRecord.fromRow(Map<String, Object?> row) {
    return SyncConflictRecord(
      scope: row['scope']?.toString().trim() ?? '',
      recordSyncId: row['record_sync_id']?.toString().trim() ?? '',
      strategy: row['strategy']?.toString().trim() ?? 'manual',
      message:
          row['message']?.toString().trim() ?? 'Conflicto de sincronizacion.',
      conflictReason:
          row['conflict_reason']?.toString().trim() ??
          row['message']?.toString().trim() ??
          'Conflicto de sincronizacion.',
      localVersion: _readInt(row['local_version']),
      serverVersion: _readInt(row['server_version']),
      detectedAt:
          DateTime.tryParse(row['detected_at']?.toString().trim() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      serverTime: DateTime.tryParse(
        row['server_time']?.toString().trim() ?? '',
      ),
      localPayload: _decodePayload(row['local_payload_json']),
      serverPayload: _decodePayload(row['server_payload_json']),
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic>? _decodePayload(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, data) => MapEntry(key.toString(), data));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class SyncConflictService {
  SyncConflictService({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;
  final StreamController<int> _countController =
      StreamController<int>.broadcast();
  int _lastUnresolvedCount = 0;

  Stream<int> get unresolvedCountStream => _countController.stream;
  int get unresolvedCount => _lastUnresolvedCount;

  Future<int> unresolvedConflictCount() async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM ${DatabaseSchema.conflictLogsTable} WHERE resolved_at IS NULL',
      );
      final value = rows.isEmpty ? 0 : rows.first['total'];
      if (value is num) {
        final count = value.toInt();
        _emitCount(count);
        return count;
      }
      final count = int.tryParse(value?.toString() ?? '') ?? 0;
      _emitCount(count);
      return count;
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        return _lastUnresolvedCount;
      }
      rethrow;
    }
  }

  bool _isDatabaseClosedError(Object error) {
    return error.toString().toLowerCase().contains('database_closed');
  }

  Future<List<SyncConflictRecord>> listOpenConflicts({String? scope}) async {
    final db = await _appDatabase.database;
    final normalizedScope = scope?.trim();
    final rows = await db.query(
      DatabaseSchema.conflictLogsTable,
      where: normalizedScope == null || normalizedScope.isEmpty
          ? 'resolved_at IS NULL'
          : 'resolved_at IS NULL AND scope = ?',
      whereArgs: normalizedScope == null || normalizedScope.isEmpty
          ? null
          : [normalizedScope],
      orderBy: 'detected_at DESC, id DESC',
    );
    return rows.map(SyncConflictRecord.fromRow).toList(growable: false);
  }

  Future<void> logUploadConflicts({
    required String scope,
    required Iterable<SyncQueueItem> queuedItems,
    required SyncConflictException exception,
    String? strategyOverride,
    DateTime? serverTime,
    String? conflictReason,
  }) async {
    try {
      final db = await _appDatabase.database;
      final detectedAt = DateTime.now().toIso8601String();
      final serverTimeIso = (serverTime ?? exception.serverTime)
          ?.toIso8601String();
      final resolvedConflictReason = conflictReason?.trim().isNotEmpty == true
          ? conflictReason!.trim()
          : exception.message.trim();
      final queuedBySyncId = {
        for (final item in queuedItems) item.recordSyncId: item,
      };
      final conflicts = exception.conflicts.isEmpty
          ? queuedBySyncId.keys
                .map((recordSyncId) {
                  return SyncConflictItem(
                    scope: scope,
                    recordSyncId: recordSyncId,
                    localVersion: _readVersion(
                      queuedBySyncId[recordSyncId]?.payload,
                    ),
                    serverVersion: null,
                    localRecord: queuedBySyncId[recordSyncId]?.payload
                        .cast<String, dynamic>(),
                    serverRecord: null,
                    message: exception.message,
                  );
                })
                .toList(growable: false)
          : exception.conflicts;

      await db.transaction((txn) async {
        for (final conflict in conflicts) {
          final recordSyncId = conflict.recordSyncId.trim();
          if (recordSyncId.isEmpty) {
            continue;
          }

          final localRecord =
              conflict.localRecord ??
              queuedBySyncId[recordSyncId]?.payload.cast<String, dynamic>();
          final localPayloadJson = localRecord == null
              ? null
              : jsonEncode(localRecord);
          final serverPayloadJson = conflict.serverRecord == null
              ? null
              : jsonEncode(conflict.serverRecord);

          final updated = await txn.rawUpdate(
            'UPDATE ${DatabaseSchema.conflictLogsTable} '
            'SET local_version = ?, server_version = ?, strategy = ?, '
            'local_payload_json = ?, server_payload_json = ?, message = ?, '
            'conflict_reason = ?, server_time = ?, '
            'detected_at = ? '
            'WHERE scope = ? AND record_sync_id = ? AND resolved_at IS NULL',
            [
              conflict.localVersion ?? _readVersion(localRecord),
              conflict.serverVersion ?? _readVersion(conflict.serverRecord),
              strategyOverride ?? exception.strategy.storageValue,
              localPayloadJson,
              serverPayloadJson,
              conflict.message ?? exception.message,
              resolvedConflictReason,
              serverTimeIso,
              detectedAt,
              scope,
              recordSyncId,
            ],
          );

          if (updated > 0) {
            continue;
          }

          await txn.insert(DatabaseSchema.conflictLogsTable, {
            'scope': scope,
            'record_sync_id': recordSyncId,
            'local_version': conflict.localVersion ?? _readVersion(localRecord),
            'server_version':
                conflict.serverVersion ?? _readVersion(conflict.serverRecord),
            'strategy': strategyOverride ?? exception.strategy.storageValue,
            'local_payload_json': localPayloadJson,
            'server_payload_json': serverPayloadJson,
            'message': conflict.message ?? exception.message,
            'conflict_reason': resolvedConflictReason,
            'server_time': serverTimeIso,
            'resolution': null,
            'detected_at': detectedAt,
            'resolved_at': null,
          });
        }
      });
      await unresolvedConflictCount();
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> resolveUsingServerVersion(SyncConflictRecord conflict) async {
    if (conflict.scope != 'products') {
      throw UnsupportedError(
        'La resolucion automatica desde servidor solo esta habilitada para products.',
      );
    }
    final serverPayload = conflict.serverPayload;
    if (serverPayload == null || serverPayload.isEmpty) {
      throw StateError(
        'No hay payload del servidor para resolver este conflicto.',
      );
    }

    final repository = ProductsSyncRepository(appDatabase: _appDatabase);
    await repository.mergeRemoteRecords([serverPayload]);
    await repository.markAsSynced([conflict.recordSyncId]);
    await resolveConflicts(
      scope: conflict.scope,
      recordSyncIds: [conflict.recordSyncId],
      resolution: 'server_won',
    );
  }

  Future<void> retryKeepLocalOverwrite(SyncConflictRecord conflict) async {
    final localPayload = conflict.localPayload;
    if (localPayload == null || localPayload.isEmpty) {
      throw StateError('No hay payload local para reintentar este conflicto.');
    }

    final queueService = SyncQueueService.instance;
    final payload = localPayload.map<String, Object?>(
      (key, value) => MapEntry(key, value),
    );
    final deletedAt =
        payload['deleted_at']?.toString().trim().isNotEmpty == true ||
        payload['deletedAt']?.toString().trim().isNotEmpty == true;
    if (deletedAt) {
      await queueService.enqueueDelete(
        scope: conflict.scope,
        recordSyncId: conflict.recordSyncId,
        payload: payload,
        triggerProcessing: false,
      );
    } else {
      await queueService.enqueueUpsert(
        scope: conflict.scope,
        recordSyncId: conflict.recordSyncId,
        payload: payload,
        triggerProcessing: false,
      );
    }
    await queueService.processQueue(includeDeferred: true);
  }

  Future<void> ignoreLocalConflict(SyncConflictRecord conflict) async {
    if (conflict.hasServerPayload && conflict.scope == 'products') {
      await resolveUsingServerVersion(conflict);
      return;
    }

    final tableName = switch (conflict.scope) {
      'products' => DatabaseSchema.lotsTable,
      'clients' => DatabaseSchema.clientsTable,
      'sellers' => DatabaseSchema.sellersTable,
      'sales' => DatabaseSchema.salesTable,
      'installments' => DatabaseSchema.installmentsTable,
      'payments' => DatabaseSchema.paymentsTable,
      _ => null,
    };
    if (tableName != null) {
      final db = await _appDatabase.database;
      await db.update(
        tableName,
        {'sync_status': DatabaseSchema.syncStatusSynced},
        where: 'sync_id = ?',
        whereArgs: [conflict.recordSyncId],
      );
    }

    await resolveConflicts(
      scope: conflict.scope,
      recordSyncIds: [conflict.recordSyncId],
      resolution: 'ignored_local',
    );
  }

  Future<void> resolveConflicts({
    required String scope,
    required Iterable<String> recordSyncIds,
    required String resolution,
  }) async {
    try {
      final ids = recordSyncIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (ids.isEmpty) {
        return;
      }

      final db = await _appDatabase.database;
      final placeholders = List.filled(ids.length, '?').join(', ');
      await db.rawUpdate(
        'UPDATE ${DatabaseSchema.conflictLogsTable} '
        'SET resolution = ?, resolved_at = ? '
        'WHERE scope = ? AND record_sync_id IN ($placeholders) AND resolved_at IS NULL',
        [resolution, DateTime.now().toIso8601String(), scope, ...ids],
      );
      await unresolvedConflictCount();
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        return;
      }
      rethrow;
    }
  }

  void dispose() {
    if (!_countController.isClosed) {
      unawaited(_countController.close());
    }
  }

  void _emitCount(int count) {
    _lastUnresolvedCount = count;
    if (!_countController.isClosed) {
      _countController.add(count);
    }
  }

  int? _readVersion(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }
    final value = payload['version'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
