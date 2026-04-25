import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late _FakeSyncConfigRepository configRepository;
  late _ConflictThenResolvedApiClient apiClient;
  late _RecordingSyncRepository repository;
  late SyncQueueService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_queue_conflict_autoresolve_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository(
      settings: _buildSettings(isConfigured: true),
    );
    apiClient = _ConflictThenResolvedApiClient();
    repository = _RecordingSyncRepository('sales', pendingSyncIds: {'sale-1'});

    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => true,
      connectivityChanges: const Stream.empty(),
    );

    service.registerRepository(repository);

    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 'sale-1');
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'auto-resuelve conflicto cuando el backend devuelve el registro resuelto',
    () async {
      final processed = await service.processQueue();

      // The item is removed from queue even on conflict.
      final db = await appDatabase.database;
      final queueRows = await db.query(DatabaseSchema.syncQueueTable);
      expect(queueRows, isEmpty);

      // It should have been marked as synced (not stuck as conflict).
      expect(repository.markedSynced, contains('sale-1'));
      expect(repository.markedConflict, isEmpty);

      // The conflict should exist but be immediately resolved.
      final conflictRows = await db.query(
        DatabaseSchema.conflictLogsTable,
        where: 'scope = ? AND record_sync_id = ?',
        whereArgs: ['sales', 'sale-1'],
        orderBy: 'id DESC',
        limit: 1,
      );
      expect(conflictRows, hasLength(1));
      expect(conflictRows.single['resolved_at'], isNotNull);
      expect(conflictRows.single['resolution'], 'last_write_wins');

      // processedCount may stay 0 because it wasn't an ACK flow.
      expect(processed, 0);
    },
  );
}

SyncSettings _buildSettings({required bool isConfigured}) {
  return SyncSettings(
    baseUrl: isConfigured ? 'https://sync.example.com' : '',
    jwtToken: isConfigured ? 'token' : '',
    queueRetryInterval: const Duration(seconds: 10),
    realtimePollingInterval: const Duration(seconds: 5),
    conflictStrategy: SyncConflictStrategy.manual,
    deviceId: 'test-device',
  );
}

Future<void> _insertQueuedRecord(
  AppDatabase appDatabase, {
  required String scope,
  required String syncId,
}) async {
  final db = await appDatabase.database;
  final now = DateTime.now().toIso8601String();

  await db.insert(DatabaseSchema.syncQueueTable, {
    'scope': scope,
    'record_sync_id': syncId,
    'operation': 'upsert',
    'payload_json': '{"sync_id":"$syncId"}',
    'created_at': now,
    'updated_at': now,
    'next_attempt_at': now,
    'last_error': null,
    'attempt_count': 0,
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  _FakeSyncConfigRepository({required SyncSettings settings})
    : _settings = settings;

  SyncSettings _settings;

  @override
  Future<SyncSettings> loadSettings() async => _settings;
}

class _ConflictThenResolvedApiClient extends SyncApiClient {
  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    final payload = recordsByScope[scope]!.single;
    final syncId = payload['sync_id']?.toString() ?? '';

    // Backend says conflict, but also returns the resolved/authoritative record.
    throw SyncConflictException(
      message: 'Version conflict',
      scope: scope,
      strategy: SyncConflictStrategy.lastWriteWins,
      conflicts: [
        SyncConflictItem(
          scope: scope,
          recordSyncId: syncId,
          localVersion: 1,
          serverVersion: 2,
          localRecord: payload.map((k, v) => MapEntry(k, v)),
          serverRecord: {'sync_id': syncId, 'version': 2},
          message: 'conflict',
        ),
      ],
      returnedRecords: [
        {
          'sync_id': syncId,
          'version': 2,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      serverUri: Uri.parse('${settings.normalizedBaseUrl}/sync/upload'),
    );
  }
}

class _RecordingSyncRepository implements SyncRepository {
  _RecordingSyncRepository(this.scope, {required Set<String> pendingSyncIds})
    : _pendingSyncIds = pendingSyncIds;

  @override
  final String scope;

  final Set<String> _pendingSyncIds;

  final List<String> markedConflict = [];
  final List<String> markedSynced = [];

  @override
  String get downloadPath => '/sync/$scope';

  @override
  String get uploadPath => '/sync/$scope';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    return _pendingSyncIds
        .map((syncId) => {'sync_id': syncId})
        .toList(growable: false);
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    markedConflict.addAll(syncIds);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    markedSynced.addAll(syncIds);
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}
