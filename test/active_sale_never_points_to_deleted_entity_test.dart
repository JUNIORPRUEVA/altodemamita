/// Tests that active sales never point to a deleted client, seller, or product.
///
/// These tests verify DB-level invariants: once the blindaje is in place,
/// no active sale should reference a soft-deleted entity.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/errors/active_sales_block_delete_exception.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('active_sale_never_deleted_entity_');
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> _insertBaseSaleData(
    Map<String, dynamic> extra, {
    required int clientId,
    required int lotId,
    required int userId,
    required int? sellerId,
    required String saleState,
  }) async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-invariant-${extra['sync_id']}',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': userId,
      'vendedor_id': sellerId,
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
      'estado': saleState,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
  }

  test('active_sale_never_points_to_deleted_client_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final repo = ClientRepository(appDatabase: appDatabase);

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-inv-1',
      'cedula': '00500000001',
      'nombre': 'Inv',
      'apellido': 'Cliente',
      'telefono': '8090000010',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-inv-1',
      'manzana_numero': 'F',
      'solar_numero': '6',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final userRows = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userRows.isEmpty ? 1 : userRows.first['id']) as int;

    await _insertBaseSaleData(
      {'sync_id': 'c1'},
      clientId: clientId,
      lotId: lotId,
      userId: uid,
      sellerId: null,
      saleState: 'activa',
    );

    // Attempt to delete — must throw
    bool threw = false;
    try {
      await repo.delete(clientId);
    } on ActiveSalesBlockDeleteException {
      threw = true;
    }
    expect(threw, isTrue, reason: 'Delete must be blocked when active sale exists');

    // Verify client still not deleted in DB
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'id = ?',
      whereArgs: [clientId],
    );
    expect(rows.first['deleted_at'], isNull,
        reason: 'Client must remain non-deleted after blocked attempt');
  });

  test('active_sale_never_points_to_deleted_product_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final repo = LotRepository(appDatabase: appDatabase);

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-inv-2',
      'cedula': '00500000002',
      'nombre': 'Inv2',
      'apellido': 'Cliente2',
      'telefono': '8090000011',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-inv-2',
      'manzana_numero': 'G',
      'solar_numero': '7',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final userRows = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userRows.isEmpty ? 1 : userRows.first['id']) as int;

    await _insertBaseSaleData(
      {'sync_id': 'p2'},
      clientId: clientId,
      lotId: lotId,
      userId: uid,
      sellerId: null,
      saleState: 'activa',
    );

    bool threw = false;
    try {
      await repo.delete(lotId);
    } on ActiveSalesBlockDeleteException {
      threw = true;
    }
    expect(threw, isTrue);

    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'id = ?',
      whereArgs: [lotId],
    );
    expect(rows.first['deleted_at'], isNull);
  });

  test('active_sale_never_points_to_deleted_seller_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final repo = SellerRepository(appDatabase: appDatabase);

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-inv-3',
      'cedula': '00500000003',
      'nombre': 'Inv3',
      'apellido': 'Cliente3',
      'telefono': '8090000012',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-inv-3',
      'manzana_numero': 'H',
      'solar_numero': '8',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final sellerId = await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-inv-3',
      'nombre': 'Seller Inv',
      'cedula': '00600000001',
      'telefono': '8090000013',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final userRows = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userRows.isEmpty ? 1 : userRows.first['id']) as int;

    await _insertBaseSaleData(
      {'sync_id': 's3'},
      clientId: clientId,
      lotId: lotId,
      userId: uid,
      sellerId: sellerId,
      saleState: 'activa',
    );

    bool threw = false;
    try {
      await repo.delete(sellerId);
    } on ActiveSalesBlockDeleteException {
      threw = true;
    }
    expect(threw, isTrue);

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'id = ?',
      whereArgs: [sellerId],
    );
    expect(rows.first['deleted_at'], isNull);
  });
}
