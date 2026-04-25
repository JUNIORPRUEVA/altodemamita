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
          'detected_at = ? '
          'WHERE scope = ? AND record_sync_id = ? AND resolved_at IS NULL',
          [
            conflict.localVersion ?? _readVersion(localRecord),
            conflict.serverVersion ?? _readVersion(conflict.serverRecord),
            exception.strategy.storageValue,
            localPayloadJson,
            serverPayloadJson,
            conflict.message ?? exception.message,
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
          'strategy': exception.strategy.storageValue,
          'local_payload_json': localPayloadJson,
          'server_payload_json': serverPayloadJson,
          'message': conflict.message ?? exception.message,
          'resolution': null,
          'detected_at': detectedAt,
          'resolved_at': null,
        });
      }
    });
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
