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
  late _RecordingSyncApiClient apiClient;
  late SyncQueueService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_queue_service_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository(
      settings: _buildSettings(isConfigured: true),
    );
    apiClient = _RecordingSyncApiClient(failingScopes: {'clients'});
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    for (final scope in ['clients', 'products', 'sales', 'payments']) {
      service.registerRepository(_FakeSyncRepository(scope));
    }
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('bloquea scopes dependientes cuando falla un scope padre', () async {
    await _insertQueuedRecord(appDatabase, scope: 'clients', syncId: 'c-1');
    await _insertQueuedRecord(appDatabase, scope: 'products', syncId: 'p-1');
    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 's-1');
    await _insertQueuedRecord(appDatabase, scope: 'payments', syncId: 'py-1');

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 0);
    expect(apiClient.uploadedScopes, ['clients']);
    expect(queueRows['clients']?['attempt_count'], 1);
    expect(queueRows['products']?['attempt_count'], 0);
    expect(queueRows['sales']?['attempt_count'], 0);
    expect(queueRows['payments']?['attempt_count'], 0);
  });
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

Future<Map<String, Map<String, Object?>>> _readQueueRows(
  AppDatabase appDatabase,
) async {
  final db = await appDatabase.database;
  final rows = await db.query(DatabaseSchema.syncQueueTable);
  return {for (final row in rows) row['scope']! as String: row};
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  _FakeSyncConfigRepository({required SyncSettings settings})
    : _settings = settings;

  SyncSettings _settings;

  set settings(SyncSettings value) {
    _settings = value;
  }

  @override
  Future<SyncSettings> loadSettings() async => _settings;
}

class _RecordingSyncApiClient extends SyncApiClient {
  _RecordingSyncApiClient({this.failingScopes = const {}});

  final Set<String> failingScopes;
  final List<String> uploadedScopes = [];

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    uploadedScopes.add(scope);
    if (failingScopes.contains(scope)) {
      throw HttpException('Fallo simulado para $scope');
    }

    return SyncUploadResponse(
      returnedRecordsByScope: {scope: const []},
    );
  }
}

class _FakeSyncRepository implements SyncRepository {
  _FakeSyncRepository(this.scope);

  @override
  final String scope;

  @override
  String get downloadPath => '/sync/$scope';

  @override
  String get uploadPath => '/sync/$scope';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async => const [];

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {}

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {}

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}
