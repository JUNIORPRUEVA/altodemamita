import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SalesSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('sales_tombstone_');
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

  test('inserts missing remote sales tombstone locally', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-1',
      'version': 1,
      'nombre': 'Cliente 1',
      'cedula': '001-0000001-1',
      'telefono': '8095551111',
      'direccion': 'Dir 1',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-sale-1',
        'sync_id': 'sale-1',
        'version': 2,
        'client_sync_id': 'client-1',
        'product_sync_id': 'product-1',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 500000,
        'down_payment_percentage': 10,
        'down_payment_amount': 50000,
        'required_initial_payment': 50000,
        'paid_initial_payment': 50000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 450000,
        'pending_balance': 450000,
        'monthly_interest': 1,
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
      whereArgs: ['sale-1'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.single['deleted_at'], now);
    expect(rows.single['sync_status'], DatabaseSchema.syncStatusSynced);
  });

  test('keeps local sale and inserts remote sales tombstone with same solar', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-1',
      'version': 1,
      'nombre': 'Cliente 1',
      'cedula': '001-0000001-1',
      'telefono': '8095551111',
      'direccion': 'Dir 1',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final clientId = (await db.query(DatabaseSchema.clientsTable, limit: 1))
        .single['id'];
    final productId = (await db.query(DatabaseSchema.lotsTable, limit: 1))
        .single['id'];

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'local-sale-conflict',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': productId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 500000,
      'inicial_porcentaje': 10,
      'inicial_monto': 50000,
      'monto_inicial_requerido': 50000,
      'monto_inicial_pagado': 50000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 450000,
      'saldo_pendiente': 450000,
      'interes_mensual': 1,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-sale-1',
        'sync_id': 'sale-1',
        'version': 2,
        'client_sync_id': 'client-1',
        'product_sync_id': 'product-1',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 500000,
        'down_payment_percentage': 10,
        'down_payment_amount': 50000,
        'required_initial_payment': 50000,
        'paid_initial_payment': 50000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 450000,
        'pending_balance': 450000,
        'monthly_interest': 1,
        'installment_count': 12,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.salesTable,
      orderBy: 'sync_id ASC',
    );

    expect(rows, hasLength(2));
    expect(rows.where((row) => row['sync_id'] == 'local-sale-conflict'), hasLength(1));
    expect(rows.where((row) => row['sync_id'] == 'sale-1'), hasLength(1));
    expect(
      rows.firstWhere((row) => row['sync_id'] == 'sale-1')['deleted_at'],
      now,
    );
  });

  test('reuses local active sale occupying the same solar unique slot', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-1',
      'version': 1,
      'nombre': 'Cliente 1',
      'cedula': '001-0000001-1',
      'telefono': '8095551111',
      'direccion': 'Dir 1',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final clientId = (await db.query(DatabaseSchema.clientsTable, limit: 1))
        .single['id'];
    final productId = (await db.query(DatabaseSchema.lotsTable, limit: 1))
        .single['id'];

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'local-sale-conflict',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': productId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 400000,
      'inicial_porcentaje': 10,
      'inicial_monto': 40000,
      'monto_inicial_requerido': 40000,
      'monto_inicial_pagado': 40000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 360000,
      'saldo_pendiente': 360000,
      'interes_mensual': 1,
      'cantidad_cuotas': 12,
      'estado': 'apartada',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-sale-1',
        'sync_id': 'sale-1',
        'version': 2,
        'client_sync_id': 'client-1',
        'product_sync_id': 'product-1',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 500000,
        'down_payment_percentage': 10,
        'down_payment_amount': 50000,
        'required_initial_payment': 50000,
        'paid_initial_payment': 50000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 450000,
        'pending_balance': 450000,
        'monthly_interest': 1,
        'installment_count': 12,
        'status': 'activa',
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      },
    ]);

    final rows = await db.query(DatabaseSchema.salesTable);

    expect(rows, hasLength(1));
    expect(rows.single['sync_id'], 'sale-1');
    expect(rows.single['precio_venta'], 500000.0);
    expect(rows.single['deleted_at'], isNull);
    expect(rows.single['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}