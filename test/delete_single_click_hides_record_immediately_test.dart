import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncQueueService syncQueueService;
  late SalesRepository salesRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'delete_single_click_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    syncQueueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: _FakeSyncConfigRepository(),
      apiClient: _NoopSyncApiClient(),
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    salesRepository = SalesRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );
  });

  tearDown(() async {
    syncQueueService.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('delete_single_click_hides_record_immediately_test', () async {
    final saleId = await _createSampleSale(salesRepository, appDatabase);

    await salesRepository.deleteSale(saleId);

    final activeSales = await salesRepository.fetchAll();
    expect(activeSales.where((item) => item.id == saleId), isEmpty);
  });

  test('delete_does_not_require_second_tap_test', () async {
    final saleId = await _createSampleSale(salesRepository, appDatabase);

    await salesRepository.deleteSale(saleId);

    final db = await appDatabase.database;
    final row = (await db.query(
      DatabaseSchema.salesTable,
      columns: ['deleted_at', 'sync_status'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).single;

    expect(row['deleted_at'], isNotNull);
    expect(row['sync_status'], DatabaseSchema.syncStatusPendingDelete);
  });

  test('delete_soft_delete_writes_sqlite_before_sync_test', () async {
    final saleId = await _createSampleSale(salesRepository, appDatabase);

    await salesRepository.deleteSale(saleId);

    final db = await appDatabase.database;
    final row = (await db.query(
      DatabaseSchema.salesTable,
      columns: ['deleted_at', 'sync_status'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).single;

    final queueRows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope = ? AND operation = ?',
      whereArgs: ['sales', 'delete'],
    );

    expect(row['deleted_at'], isNotNull);
    expect(row['sync_status'], DatabaseSchema.syncStatusPendingDelete);
    expect(queueRows, isNotEmpty);
  });

  test('delete_enqueue_pending_delete_once_test', () async {
    final saleId = await _createSampleSale(salesRepository, appDatabase);
    final db = await appDatabase.database;
    final saleSyncId = (await db.query(
      DatabaseSchema.salesTable,
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).single['sync_id'] as String;

    await salesRepository.deleteSale(saleId);

    final queueRows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope = ? AND operation = ? AND record_sync_id = ?',
      whereArgs: ['sales', 'delete', saleSyncId],
    );

    expect(queueRows.length, 1);
  });
}

Future<int> _createSampleSale(
  SalesRepository repository,
  AppDatabase appDatabase,
) async {
  final db = await appDatabase.database;
  final now = DateTime(2026, 5, 1, 9, 30).toIso8601String();

  final clientId = await db.insert(DatabaseSchema.clientsTable, {
    'sync_id': 'client-single-delete',
    'version': 1,
    'nombre': 'Cliente Uno',
    'cedula': '00113745624',
    'telefono': '8095550101',
    'direccion': 'Direccion',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  final lotId = await db.insert(DatabaseSchema.lotsTable, {
    'sync_id': 'product-single-delete',
    'version': 1,
    'manzana_numero': 'A',
    'solar_numero': '1',
    'metros_cuadrados': 120,
    'precio_por_metro': 2000,
    'estado': 'disponible',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  return repository.createSale(
    SaleDraft(
      clientId: clientId,
      lotId: lotId,
      userId: 1,
      saleDate: DateTime.parse(now),
      salePrice: 400000,
      downPaymentPercentage: 10,
      requiredInitialPayment: 40000,
      initialPaymentPaid: 40000,
      monthlyInterest: 1,
      installmentCount: 6,
    ),
  );
}

class _NoopSyncApiClient extends SyncApiClient {}

class _FakeSyncConfigRepository extends SyncConfigRepository {}
