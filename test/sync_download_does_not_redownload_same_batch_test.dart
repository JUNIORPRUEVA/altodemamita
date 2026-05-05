import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

import 'helpers/fake_sync_download_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncConfigRepository configRepository;
  late FakeSyncDownloadApiClient apiClient;
  late SyncQueueService queueService;
  late SyncService syncService;
  late _RecordingSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_no_redownload_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'sync.db'));
    await appDatabase.initialize();
    configRepository = SyncConfigRepository();
    apiClient = FakeSyncDownloadApiClient();
    repository = _RecordingSyncRepository('roles');
    queueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    syncService = SyncService(
      repositories: [repository],
      configRepository: configRepository,
      apiClient: apiClient,
      syncQueueService: queueService,
      appDatabase: appDatabase,
    );
    await configRepository.saveJwtToken('jwt-test');
    apiClient.recordsByScope = {
      'roles': [
        {
          'id': 'role-remote-1',
          'sync_id': 'role-sync-1',
          'version': 1,
          'code': 'ADMIN',
          'name': 'Administrador',
          'description': 'Rol administrativo',
          'created_at': '2026-05-05T10:00:00.000Z',
          'updated_at': '2026-05-05T10:00:00.000Z',
          'deleted_at': null,
          'sync_status': 'synced',
        },
      ],
    };
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('sync_download_does_not_redownload_same_batch_test', () async {
    await syncService.downloadUpdatesForScopes(['roles']);
    final secondDownload = await syncService.downloadUpdatesForScopes([
      'roles',
    ]);

    expect(secondDownload, 0);
    expect(apiClient.downloadCalls, 2);
    expect(repository.mergedRecords, hasLength(1));
  });
}

class _RecordingSyncRepository implements SyncRepository {
  _RecordingSyncRepository(this.scope);

  @override
  final String scope;

  final List<Map<String, dynamic>> mergedRecords = <Map<String, dynamic>>[];

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/download';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async => const [];

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {}

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {}

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    mergedRecords
      ..clear()
      ..addAll(records.map((record) => Map<String, dynamic>.from(record)));
  }
}
