import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/roles_sync_repository.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_scope_cursors_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'sync.db'));
    await appDatabase.initialize();
    configRepository = SyncConfigRepository();
    apiClient = FakeSyncDownloadApiClient();
    queueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    syncService = SyncService(
      repositories: [
        RolesSyncRepository(appDatabase: appDatabase),
        ProductsSyncRepository(appDatabase: appDatabase),
      ],
      configRepository: configRepository,
      apiClient: apiClient,
      syncQueueService: queueService,
      appDatabase: appDatabase,
    );
    await configRepository.saveJwtToken('jwt-test');
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('sync_download_uses_scope_cursors_test', () async {
    final rolesCursor = DateTime.utc(2026, 5, 1, 10);
    final productsCursor = DateTime.utc(2026, 5, 2, 10);
    await configRepository.saveCursor('roles', rolesCursor);
    await configRepository.saveCursor('products', productsCursor);

    apiClient.recordsByScope = {'roles': const [], 'products': const []};

    await syncService.downloadUpdatesForScopes(['roles', 'products']);

    expect(apiClient.requestedUpdatedSince, isNull);
    expect(apiClient.requestedUpdatedSinceByScope['roles'], rolesCursor);
    expect(apiClient.requestedUpdatedSinceByScope['products'], productsCursor);
  });
}
