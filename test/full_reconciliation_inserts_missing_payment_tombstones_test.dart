import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late PaymentsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('reconcile_payments_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = PaymentsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('full_reconciliation_inserts_missing_payment_tombstones_test', () async {
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
    final clientId = (await db.query(DatabaseSchema.clientsTable, limit: 1)).single['id'];
    final productId = (await db.query(DatabaseSchema.lotsTable, limit: 1)).single['id'];
    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': productId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 500000,
      'inicial_porcentaje': 20,
      'inicial_monto': 100000,
      'monto_inicial_requerido': 100000,
      'monto_inicial_pagado': 100000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 400000,
      'saldo_pendiente': 400000,
      'interes_mensual': 1.5,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-payment-6',
        'sync_id': 'payment-tomb-6',
        'version': 2,
        'sale_sync_id': 'sale-1',
        'client_sync_id': 'client-1',
        'installment_sync_id': null,
        'payment_date': now,
        'amount_paid': 25000,
        'payment_method': 'transferencia',
        'payment_type': 'cuota',
        'reference': 'R-6',
        'year_to_pay': '2026',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'sync_id = ?',
      whereArgs: ['payment-tomb-6'],
      limit: 1,
    );
    expect(rows, isNotEmpty);
    expect((rows.first['deleted_at'] as String?)?.isNotEmpty, isTrue);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}
