import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ProductsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'products_delete_ack_tombstone_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = ProductsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'markAsSynced conserva el solar soft-deleted si sigue referenciado por ventas locales',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 5, 5, 9, 0).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-product-delete-ref-1',
        'version': 1,
        'nombre': 'Cliente Referenciado',
        'cedula': '00113745624',
        'telefono': '8095551111',
        'direccion': 'Calle Referencia',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'lot-sync-delete-ref-1',
        'version': 2,
        'manzana_numero': 'A',
        'solar_numero': '10',
        'metros_cuadrados': 180,
        'precio_por_metro': 2500,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': now,
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
      });

      await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-sync-delete-ref-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': now,
        'precio_venta': 450000,
        'inicial_porcentaje': 10,
        'inicial_monto': 45000,
        'monto_inicial_requerido': 45000,
        'monto_inicial_pagado': 45000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': now,
        'saldo_financiado': 405000,
        'saldo_pendiente': 405000,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await repository.markAsSynced(['lot-sync-delete-ref-1']);

      final lotRows = await db.query(
        DatabaseSchema.lotsTable,
        where: 'sync_id = ?',
        whereArgs: ['lot-sync-delete-ref-1'],
        limit: 1,
      );
      final saleRows = await db.query(
        DatabaseSchema.salesTable,
        columns: ['solar_id'],
        where: 'sync_id = ?',
        whereArgs: ['sale-sync-delete-ref-1'],
        limit: 1,
      );

      expect(lotRows, hasLength(1));
      expect(lotRows.single['deleted_at'], isNotNull);
      expect(lotRows.single['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(saleRows, hasLength(1));
      expect(saleRows.single['solar_id'], lotId);
    },
  );
}
