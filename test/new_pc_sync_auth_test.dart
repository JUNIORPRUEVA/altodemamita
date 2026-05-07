import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late FakeBackendState backendState;
  late FakeSyncConfigRepository configRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'new_pc_sync_auth_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'sync.db'));
    await appDatabase.initialize();
    backendState = FakeBackendState()..initialized = true;
    configRepository = FakeSyncConfigRepository(settings: buildFakeSettings());
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  SyncService buildSyncService({List<SyncRepository> repositories = const []}) {
    final apiClient = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );
    final queue = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    return SyncService(
      repositories: repositories,
      configRepository: configRepository,
      apiClient: apiClient,
      syncQueueService: queue,
    );
  }

  test('login local sin JWT bloquea sync con mensaje claro', () async {
    final syncService = buildSyncService(repositories: [_FakeSyncRepository()]);

    final report = await syncService.syncNow();

    expect(report.wasSkipped, isTrue);
    expect(report.errorMessage, SyncService.cloudLoginRequiredMessage);
    expect(
      await syncService.startupBlockReason(),
      SyncService.cloudLoginRequiredMessage,
    );
  });

  test('JWT guardado permite iniciar sync', () async {
    await configRepository.saveJwtToken('jwt-test-token');
    final syncService = buildSyncService();

    expect(await syncService.startupBlockReason(), isNull);
    final report = await syncService.syncNow(forceFullDownload: true);

    expect(report.wasSkipped, isFalse);
    expect(report.errorMessage, isNull);
  });

  test(
    '401 en sync invalida JWT una sola vez y no crea loop infinito',
    () async {
      await configRepository.saveJwtToken('jwt-test-token');
      backendState.rejectSyncDownloadUnauthorized = true;
      var expiredNotifications = 0;
      final apiClient = SyncApiClient(
        httpClient: FakeBackendHttpClient(state: backendState),
      );
      final queue = SyncQueueService.test(
        appDatabase: appDatabase,
        configRepository: configRepository,
        apiClient: apiClient,
        conflictService: SyncConflictService(appDatabase: appDatabase),
      );
      final syncService = SyncService(
        repositories: [_FakeSyncRepository()],
        configRepository: configRepository,
        apiClient: apiClient,
        syncQueueService: queue,
        onCloudSessionExpired: (_) async {
          expiredNotifications += 1;
        },
      );

      final firstReport = await syncService.syncNow(forceFullDownload: true);
      final secondReport = await syncService.syncNow(forceFullDownload: true);

      expect(firstReport.wasSkipped, isTrue);
      expect(firstReport.errorMessage, contains('Inicia sesion en linea'));
      expect(secondReport.wasSkipped, isTrue);
      expect(secondReport.errorMessage, SyncService.cloudLoginRequiredMessage);
      expect(expiredNotifications, 1);
      expect((await configRepository.loadSettings()).jwtToken, isEmpty);
    },
  );

  test('sync se bloquea con mensaje claro si la PC no esta autorizada', () async {
    await configRepository.saveJwtToken('jwt-test-token');
    backendState.rejectSyncDownloadForDeviceUnauthorized = true;
    final syncService = buildSyncService(repositories: [_FakeSyncRepository()]);

    final report = await syncService.syncNow(forceFullDownload: true);

    expect(report.wasSkipped, isTrue);
    expect(
      report.errorMessage,
      SyncService.deviceAuthorizationRequiredMessage,
    );
  });
}

class _FakeSyncRepository implements SyncRepository {
  @override
  String get scope => 'clients';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/download';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async => const [];

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {}

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {}

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}
