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
    tempDirectory = await Directory.systemTemp.createTemp(
      'sales_pending_delete_beats_remote_active_',
    );
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

  test(
    'mergeRemoteRecords conserva la venta local en pending_delete ante un backend activo mas viejo',
    () async {
      final db = await appDatabase.database;
      final createdAt = DateTime(2026, 5, 5, 9, 0).toIso8601String();
      final localDeletedAt = DateTime(2026, 5, 5, 10, 0).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-sale-pending-delete-1',
        'version': 1,
        'nombre': 'Cliente Delete',
        'cedula': '001-0000555-1',
        'telefono': '8095555551',
        'direccion': 'Calle Delete',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-sale-pending-delete-1',
        'version': 1,
        'manzana_numero': 'P',
        'solar_numero': '02',
        'metros_cuadrados': 110,
        'precio_por_metro': 3000,
        'estado': 'vendido',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-pending-delete-1',
        'id_remote': 'remote-sale-pending-delete-1',
        'version': 9,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': createdAt,
        'precio_venta': 330000,
        'inicial_porcentaje': 10,
        'inicial_monto': 33000,
        'monto_inicial_requerido': 33000,
        'monto_inicial_pagado': 33000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': createdAt,
        'saldo_financiado': 297000,
        'saldo_pendiente': 297000,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'cancelada',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': localDeletedAt,
        'last_modified_local': localDeletedAt,
        'last_modified_remote': createdAt,
        'deleted_at': localDeletedAt,
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
      });

      await repository.mergeRemoteRecords([
        {
          'id': 'remote-sale-pending-delete-1',
          'sync_id': 'sale-pending-delete-1',
          'client_sync_id': 'client-sale-pending-delete-1',
          'product_sync_id': 'product-sale-pending-delete-1',
          'seller_sync_id': null,
          'version': 8,
          'sale_date': createdAt,
          'sale_price': 330000,
          'down_payment_percentage': 10,
          'down_payment_amount': 33000,
          'required_initial_payment': 33000,
          'paid_initial_payment': 33000,
          'pending_initial_payment': 0,
          'minimum_reserve_amount': null,
          'initial_payment_deadline': null,
          'activation_date': createdAt,
          'financed_balance': 297000,
          'pending_balance': 297000,
          'monthly_interest': 1,
          'installment_count': 12,
          'status': 'activa',
          'created_at': createdAt,
          'updated_at': createdAt,
          'deleted_at': null,
        },
      ]);

      final rows = await db.query(
        DatabaseSchema.salesTable,
        where: 'sync_id = ?',
        whereArgs: ['sale-pending-delete-1'],
        limit: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], localDeletedAt);
      expect(rows.single['sync_status'], DatabaseSchema.syncStatusPendingDelete);
      expect(rows.single['version'], 9);
    },
  );

  test(
    'mergeRemoteRecords revive una venta local borrada ya sincronizada cuando backend la reporta activa',
    () async {
      final db = await appDatabase.database;
      final createdAt = DateTime(2026, 5, 5, 9, 0).toIso8601String();
      final deletedAt = DateTime(2026, 5, 5, 10, 0).toIso8601String();
      final remoteUpdatedAt = DateTime(2026, 5, 5, 11, 0).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-sale-revive-1',
        'version': 1,
        'nombre': 'Cliente Revive',
        'cedula': '001-0000556-1',
        'telefono': '8095555552',
        'direccion': 'Calle Revive',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-sale-revive-1',
        'version': 1,
        'manzana_numero': 'R',
        'solar_numero': '03',
        'metros_cuadrados': 120,
        'precio_por_metro': 3200,
        'estado': 'vendido',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-revive-1',
        'id_remote': 'remote-sale-revive-1',
        'version': 4,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': createdAt,
        'precio_venta': 350000,
        'inicial_porcentaje': 10,
        'inicial_monto': 35000,
        'monto_inicial_requerido': 35000,
        'monto_inicial_pagado': 35000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': createdAt,
        'saldo_financiado': 315000,
        'saldo_pendiente': 315000,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'cancelada',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': deletedAt,
        'last_modified_local': deletedAt,
        'last_modified_remote': deletedAt,
        'deleted_at': deletedAt,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await repository.mergeRemoteRecords([
        {
          'id': 'remote-sale-revive-1',
          'sync_id': 'sale-revive-1',
          'client_sync_id': 'client-sale-revive-1',
          'product_sync_id': 'product-sale-revive-1',
          'seller_sync_id': null,
          'version': 5,
          'sale_date': createdAt,
          'sale_price': 355000,
          'down_payment_percentage': 10,
          'down_payment_amount': 35500,
          'required_initial_payment': 35500,
          'paid_initial_payment': 35500,
          'pending_initial_payment': 0,
          'minimum_reserve_amount': null,
          'initial_payment_deadline': null,
          'activation_date': createdAt,
          'financed_balance': 319500,
          'pending_balance': 319500,
          'monthly_interest': 1,
          'installment_count': 12,
          'status': 'activa',
          'created_at': createdAt,
          'updated_at': remoteUpdatedAt,
          'deleted_at': null,
        },
      ]);

      final row = (await db.query(
        DatabaseSchema.salesTable,
        where: 'sync_id = ?',
        whereArgs: ['sale-revive-1'],
        limit: 1,
      )).single;

      expect(row['deleted_at'], isNull);
      expect(row['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(row['version'], 5);
      expect(row['estado'], 'activa');
      expect(row['precio_venta'], 355000.0);
    },
  );
}