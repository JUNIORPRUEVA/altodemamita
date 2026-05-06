import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/errors/active_sales_block_delete_exception.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late LotRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('cannot_delete_product_lot_active_sale_');
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();
    repository = LotRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('cannot_delete_product_lot_with_active_sale_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-lot-block-1',
      'cedula': '00400000001',
      'nombre': 'Ana',
      'apellido': 'Gomez',
      'telefono': '8090000001',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-block-1',
      'manzana_numero': 'C',
      'solar_numero': '3',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final userId = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userId.isEmpty ? 1 : userId.first['id']) as int;

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-block-lot-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': uid,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 700000.0,
      'inicial_porcentaje': 10.0,
      'inicial_monto': 70000.0,
      'monto_inicial_requerido': 70000.0,
      'monto_inicial_pagado': 70000.0,
      'monto_inicial_pendiente': 0.0,
      'saldo_financiado': 630000.0,
      'saldo_pendiente': 630000.0,
      'interes_mensual': 1.0,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    expect(
      () => repository.delete(lotId),
      throwsA(isA<ActiveSalesBlockDeleteException>()),
    );
  });

  test('can_delete_product_lot_without_active_sale_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-no-sale-1',
      'manzana_numero': 'D',
      'solar_numero': '4',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'disponible',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await expectLater(repository.delete(lotId), completes);

    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'id = ?',
      whereArgs: [lotId],
    );
    expect(rows.first['deleted_at'], isNotNull);
  });

  test('can_delete_product_lot_with_only_cancelled_sales_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-lot-cancelled-1',
      'cedula': '00400000002',
      'nombre': 'Luis',
      'apellido': 'Rios',
      'telefono': '8090000002',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-cancelled-sale-1',
      'manzana_numero': 'E',
      'solar_numero': '5',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'disponible',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final userId = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userId.isEmpty ? 1 : userId.first['id']) as int;

    // Only a cancelled sale — should NOT block delete
    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-cancelled-lot-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': uid,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 700000.0,
      'inicial_porcentaje': 10.0,
      'inicial_monto': 70000.0,
      'monto_inicial_requerido': 70000.0,
      'monto_inicial_pagado': 70000.0,
      'monto_inicial_pendiente': 0.0,
      'saldo_financiado': 630000.0,
      'saldo_pendiente': 630000.0,
      'interes_mensual': 1.0,
      'cantidad_cuotas': 12,
      'estado': 'cancelada',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await expectLater(repository.delete(lotId), completes);
  });
}
