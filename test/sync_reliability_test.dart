import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_logger.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_reliability_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('mantiene cambio local mas reciente cuando remoto viene atrasado', () async {
    final db = await appDatabase.database;
    final localUpdatedAt = DateTime.now().toIso8601String();
    final remoteUpdatedAt = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .toIso8601String();

    await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-1',
      'version': 3,
      'nombre': 'Vendedor local',
      'cedula': '00100000001',
      'telefono': '8090000001',
      'fecha_creacion': remoteUpdatedAt,
      'fecha_actualizacion': localUpdatedAt,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPending,
    });

    final queue = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: _FakeSyncConfigRepository(),
      apiClient: SyncApiClient(),
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    final repository = SellerRepository(
      database: appDatabase,
      syncQueueService: queue,
    );

    await repository.mergeRemoteRecords([
      {
        'sync_id': 'seller-1',
        'version': 2,
        'name': 'Vendedor remoto viejo',
        'document_id': '00100000001',
        'phone': '8091111111',
        'created_at': remoteUpdatedAt,
        'updated_at': remoteUpdatedAt,
        'deleted_at': null,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'sync_id = ?',
      whereArgs: ['seller-1'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['nombre'], 'Vendedor local');
    expect(rows.first['version'], 3);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusPending);
  });

  test('delete remoto de producto se replica como soft delete local', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1500,
      'estado': 'disponible',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final repository = ProductsSyncRepository(appDatabase: appDatabase);
    await repository.mergeRemoteRecords([
      {
        'sync_id': 'lot-1',
        'version': 2,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-1'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusSynced);
  });

  test('sync logger escribe en logs/sync.log', () async {
    final appPaths = AppPaths(supportDirectory: tempDirectory.path);
    final logger = SyncLogger(appPaths: appPaths);

    await logger.log(
      action: 'upload',
      entity: 'sales',
      result: 'ok',
      extra: {'count': 1},
    );

    final file = File(appPaths.syncLogPath);
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines, isNotEmpty);

    final payload = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(payload['action'], 'upload');
    expect(payload['entity'], 'sales');
    expect(payload['result'], 'ok');
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 10),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'device',
    );
  }
}