import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncQueueService service;
  late _FakeSyncConfigRepository configRepository;
  late _RepairApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('repair_delete_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    configRepository = _FakeSyncConfigRepository();
    apiClient = _RepairApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    service.registerRepository(ProductsSyncRepository(appDatabase: appDatabase));
  });

  tearDown(() async {
    service.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('repairs legacy product delete queue rows already deleted on backend', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-delete-1',
      'id_remote': 'remote-product-delete-1',
      'version': 4,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1200,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.syncQueueTable, {
      'scope': 'products',
      'record_sync_id': 'product-delete-1',
      'operation': 'delete',
      'payload_json': '{"sync_id":"product-delete-1","deleted_at":"$now"}',
      'attempt_count': 7,
      'last_error': 'FOREIGN KEY constraint failed DELETE FROM solares WHERE deleted_at IS NOT NULL',
      'next_attempt_at': now,
      'created_at': now,
      'updated_at': now,
    });

    apiClient.downloadedRecordsByScope = {
      'products': [
        {
          'id': 'remote-product-delete-1',
          'sync_id': 'product-delete-1',
          'version': 4,
          'block_number': 'A',
          'lot_number': '1',
          'area': 100,
          'price_per_square_meter': 1200,
          'status': 'vendido',
          'created_at': now,
          'updated_at': now,
          'deleted_at': now,
        },
      ],
    };

    final processed = await service.processQueue(includeDeferred: true);

    final queueRows = await db.query(DatabaseSchema.syncQueueTable);
    final localRow = (await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['product-delete-1'],
      limit: 1,
    )).single;

    expect(processed, 0);
    expect(apiClient.uploadCalls, 0);
    expect(queueRows, isEmpty);
    expect(localRow['deleted_at'], isNotNull);
    expect(localRow['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://sync.example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 5),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'device-test',
    );
  }
}

class _RepairApiClient extends SyncApiClient {
  int uploadCalls = 0;
  Map<String, List<Map<String, dynamic>>> downloadedRecordsByScope = const {};

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    uploadCalls += 1;
    return const SyncUploadResponse(returnedRecordsByScope: {});
  }

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    return SyncDownloadResponse(recordsByScope: downloadedRecordsByScope);
  }
}