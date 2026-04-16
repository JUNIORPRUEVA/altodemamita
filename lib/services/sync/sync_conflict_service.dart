import 'dart:async';
import 'dart:convert';

import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import 'sync_api_client.dart';
import 'sync_queue_service.dart';

class SyncConflictService {
  SyncConflictService({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;
  final StreamController<int> _countController = StreamController<int>.broadcast();
  int _lastUnresolvedCount = 0;

  Stream<int> get unresolvedCountStream => _countController.stream;
  int get unresolvedCount => _lastUnresolvedCount;

  Future<int> unresolvedConflictCount() async {
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
  }

  Future<void> logUploadConflicts({
    required String scope,
    required Iterable<SyncQueueItem> queuedItems,
    required SyncConflictException exception,
  }) async {
    final db = await _appDatabase.database;
    final detectedAt = DateTime.now().toIso8601String();
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

    final batch = db.batch();
    for (final conflict in conflicts) {
      final localRecord =
          conflict.localRecord ??
          queuedBySyncId[conflict.recordSyncId]?.payload
              .cast<String, dynamic>();
      batch.insert(DatabaseSchema.conflictLogsTable, {
        'scope': scope,
        'record_sync_id': conflict.recordSyncId,
        'local_version': conflict.localVersion ?? _readVersion(localRecord),
        'server_version':
            conflict.serverVersion ?? _readVersion(conflict.serverRecord),
        'strategy': exception.strategy.storageValue,
        'local_payload_json': localRecord == null
            ? null
            : jsonEncode(localRecord),
        'server_payload_json': conflict.serverRecord == null
            ? null
            : jsonEncode(conflict.serverRecord),
        'message': conflict.message ?? exception.message,
        'resolution': null,
        'detected_at': detectedAt,
        'resolved_at': null,
      });
    }
    await batch.commit(noResult: true);
    await unresolvedConflictCount();
  }

  Future<void> resolveConflicts({
    required String scope,
    required Iterable<String> recordSyncIds,
    required String resolution,
  }) async {
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
