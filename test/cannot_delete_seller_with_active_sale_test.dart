import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late SellerRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('cannot_delete_seller_active_sale_');
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();
    repository = SellerRepository(database: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('can_soft_delete_seller_with_active_sale_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-seller-1',
      'cedula': '00200000001',
      'nombre': 'Pedro Torres',
      'telefono': '8091234560',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-seller-1',
      'manzana_numero': 'B',
      'solar_numero': '2',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final sellerId = await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-block-1',
      'nombre': 'Carlos Vendedor',
      'cedula': '00300000001',
      'telefono': '8091111111',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final userId = await db.rawQuery('SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1');
    final uid = (userId.isEmpty ? 1 : userId.first['id']) as int;

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-block-seller-1',
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

    await expectLater(repository.delete(sellerId), completes);

    final sellerRows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'id = ?',
      whereArgs: [sellerId],
      limit: 1,
    );
    expect(sellerRows.single['deleted_at'], isNotNull);
    expect(sellerRows.single['sync_status'], DatabaseSchema.syncStatusPendingDelete);

    final activeSales = await db.query(
      DatabaseSchema.salesTable,
      where: 'vendedor_id = ? AND deleted_at IS NULL',
      whereArgs: [sellerId],
    );
    expect(activeSales, isNotEmpty);
  });

  test('can_delete_seller_without_active_sale_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final sellerId = await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-no-sale-1',
      'nombre': 'Laura Sin Ventas',
      'cedula': '00300000002',
      'telefono': '8092222222',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await expectLater(repository.delete(sellerId), completes);

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'id = ?',
      whereArgs: [sellerId],
    );
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['cedula'], '__DELETED__$sellerId');
  });

  test('blocks_duplicate_active_seller_document_and_allows_recreate_after_delete', () async {
    final db = await appDatabase.database;
    final now = DateTime.now();
    final document = '00300000999';

    final firstId = await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-dup-1',
      'nombre': 'Vendedor Uno',
      'cedula': document,
      'telefono': '8099990001',
      'fecha_creacion': now.toIso8601String(),
      'fecha_actualizacion': now.toIso8601String(),
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await expectLater(
      repository.insert(
        Seller(
          name: 'Vendedor Dos',
          phone: '8099990002',
          documentId: document,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('vendedor activo con esta cédula'),
        ),
      ),
    );

    await repository.delete(firstId);

    await expectLater(
      repository.insert(
        Seller(
          name: 'Vendedor Recreado',
          phone: '8099990003',
          documentId: document,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      completes,
    );

    final activeRows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'TRIM(cedula) = ? AND deleted_at IS NULL',
      whereArgs: [document],
    );
    expect(activeRows.length, 1);
  });
}
