import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SalesSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('reconcile_sales_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = SalesSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('full_reconciliation_inserts_missing_sales_tombstones_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-1',
      'version': 1,
      'nombre': 'Cliente',
      'cedula': '001-0000001-1',
      'telefono': '8090000001',
      'direccion': 'Dir',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 200,
      'precio_por_metro': 1000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-sale-5',
        'sync_id': 'sale-tomb-5',
        'version': 2,
        'client_sync_id': 'client-1',
        'product_sync_id': 'product-1',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 500000,
        'down_payment_percentage': 20,
        'down_payment_amount': 100000,
        'required_initial_payment': 100000,
        'paid_initial_payment': 100000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 400000,
        'pending_balance': 400000,
        'monthly_interest': 1.5,
        'installment_count': 12,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.salesTable,
      where: 'sync_id = ?',
      whereArgs: ['sale-tomb-5'],
      limit: 1,
    );
    expect(rows, isNotEmpty);
    expect((rows.first['deleted_at'] as String?)?.isNotEmpty, isTrue);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}
