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
      'sales_delete_financial_history_',
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

  test('sales_delete_preserves_financial_history_test', () async {
    final saleId = await _createSampleSale(salesRepository, appDatabase);
    final db = await appDatabase.database;

    final installmentsBefore = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );
    final paymentsBefore = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );

    expect(installmentsBefore, isNotEmpty);
    expect(paymentsBefore, isNotEmpty);

    await salesRepository.deleteSale(saleId);

    final saleRows = await db.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    expect(saleRows.single['deleted_at'], isNotNull);
    expect(saleRows.single['estado'], 'cancelada');

    // Financial rows must remain physically present and only be tombstoned.
    final installmentsAfter = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );
    final paymentsAfter = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );

    expect(installmentsAfter.length, installmentsBefore.length);
    expect(paymentsAfter.length, paymentsBefore.length);
    expect(
      installmentsAfter.every((row) => row['deleted_at'] != null),
      isTrue,
    );
    expect(paymentsAfter.every((row) => row['deleted_at'] != null), isTrue);
  });

  test('sales_update_soft_deletes_previous_installments_test', () async {
    final saleId = await _createSampleSale(salesRepository, appDatabase);
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 2, 10, 0);

    final saleRow = (await db.query(
      DatabaseSchema.salesTable,
      columns: ['cliente_id', 'solar_id', 'usuario_id'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).single;

    final beforeRows = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );
    expect(beforeRows, isNotEmpty);

    await salesRepository.updateSale(
      saleId,
      SaleDraft(
        clientId: saleRow['cliente_id'] as int,
        lotId: saleRow['solar_id'] as int,
        userId: saleRow['usuario_id'] as int,
        saleDate: now,
        salePrice: 400000,
        downPaymentPercentage: 10,
        requiredInitialPayment: 40000,
        initialPaymentPaid: 40000,
        monthlyInterest: 1,
        installmentCount: 8,
      ),
    );

    final allRows = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );
    final activeRows = allRows.where((row) => row['deleted_at'] == null).toList();
    final deletedRows = allRows.where((row) => row['deleted_at'] != null).toList();

    expect(activeRows.length, 8);
    expect(deletedRows.length, beforeRows.length);
  });
}

Future<int> _createSampleSale(
  SalesRepository repository,
  AppDatabase appDatabase,
) async {
  final db = await appDatabase.database;
  final now = DateTime(2026, 5, 1, 9, 30).toIso8601String();

  final clientId = await db.insert(DatabaseSchema.clientsTable, {
    'sync_id': 'client-fin-hist',
    'version': 1,
    'nombre': 'Cliente Historial',
    'cedula': '00113745699',
    'telefono': '8095550199',
    'direccion': 'Direccion',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  final lotId = await db.insert(DatabaseSchema.lotsTable, {
    'sync_id': 'product-fin-hist',
    'version': 1,
    'manzana_numero': 'C',
    'solar_numero': '9',
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
