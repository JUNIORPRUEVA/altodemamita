/// Tests offline-first behavior: delete is blocked locally when an active sale
/// exists in SQLite, even without internet access.
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
    tempDir = await Directory.systemTemp.createTemp('offline_delete_blocks_');
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('offline_delete_blocks_when_local_active_sale_exists_test', () async {
    // Repositories use only SQLite — no network calls needed.
    // This simulates offline behavior: if the local DB has an active sale,
    // the delete must be blocked regardless of connectivity state.
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-offline-1',
      'cedula': '00700000001',
      'nombre': 'Offline Test',
      'telefono': '8091000001',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-offline-1',
      'manzana_numero': 'I',
      'solar_numero': '9',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final sellerId = await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-offline-1',
      'nombre': 'Offline Seller',
      'cedula': '00800000001',
      'telefono': '8091000002',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final userRows = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userRows.isEmpty ? 1 : userRows.first['id']) as int;

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-offline-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': uid,
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
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    // All three repositories must block the delete offline.
    final clientRepo = ClientRepository(appDatabase: appDatabase);
    final lotRepo = LotRepository(appDatabase: appDatabase);
    final sellerRepo = SellerRepository(database: appDatabase);

    expect(
      () => clientRepo.delete(clientId),
      throwsA(isA<ActiveSalesBlockDeleteException>()),
      reason: 'Client delete must be blocked offline when active sale exists',
    );
    expect(
      () => lotRepo.delete(lotId),
      throwsA(isA<ActiveSalesBlockDeleteException>()),
      reason: 'Lot delete must be blocked offline when active sale exists',
    );
    expect(
      () => sellerRepo.delete(sellerId),
      throwsA(isA<ActiveSalesBlockDeleteException>()),
      reason: 'Seller delete must be blocked offline when active sale exists',
    );

    // Verify none were soft-deleted
    final clientRows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'id = ?',
      whereArgs: [clientId],
    );
    final lotRows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'id = ?',
      whereArgs: [lotId],
    );
    final sellerRows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'id = ?',
      whereArgs: [sellerId],
    );

    expect(clientRows.first['deleted_at'], isNull);
    expect(lotRows.first['deleted_at'], isNull);
    expect(sellerRows.first['deleted_at'], isNull);
  });
}
