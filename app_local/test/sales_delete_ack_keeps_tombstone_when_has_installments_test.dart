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
      'sales_delete_ack_tombstone_',
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

  test('sales_delete_ack_keeps_tombstone_when_has_installments_test', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 12, 0).toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-sales-delete-ref-1',
      'version': 1,
      'nombre': 'Cliente Venta',
      'cedula': '00100000001',
      'telefono': '8095550101',
      'direccion': 'Calle Venta',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-sales-delete-ref-1',
      'version': 1,
      'manzana_numero': 'C',
      'solar_numero': '07',
      'metros_cuadrados': 175,
      'precio_por_metro': 2800,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final saleId = await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-sync-delete-installment-1',
      'version': 4,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 490000,
      'inicial_porcentaje': 10,
      'inicial_monto': 49000,
      'monto_inicial_requerido': 49000,
      'monto_inicial_pagado': 49000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 441000,
      'saldo_pendiente': 441000,
      'interes_mensual': 1,
      'cantidad_cuotas': 12,
      'estado': 'cancelada',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingDelete,
    });

    await db.insert(DatabaseSchema.installmentsTable, {
      'sync_id': 'installment-sale-delete-ref-1',
      'version': 1,
      'venta_id': saleId,
      'numero_cuota': 1,
      'fecha_vencimiento': now,
      'saldo_inicial': 441000,
      'capital_cuota': 35000,
      'interes_cuota': 4410,
      'monto_cuota': 39410,
      'monto_pagado': 0,
      'capital_pagado': 0,
      'interes_pagado': 0,
      'saldo_final': 406000,
      'estado': 'pendiente',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.markAsSynced(['sale-sync-delete-installment-1']);

    final saleRows = await db.query(
      DatabaseSchema.salesTable,
      where: 'sync_id = ?',
      whereArgs: ['sale-sync-delete-installment-1'],
      limit: 1,
    );
    final installmentRows = await db.query(
      DatabaseSchema.installmentsTable,
      columns: ['venta_id'],
      where: 'sync_id = ?',
      whereArgs: ['installment-sale-delete-ref-1'],
      limit: 1,
    );

    expect(saleRows, hasLength(1));
    expect(saleRows.single['deleted_at'], isNotNull);
    expect(saleRows.single['sync_status'], DatabaseSchema.syncStatusSynced);
    expect(installmentRows, hasLength(1));
    expect(installmentRows.single['venta_id'], saleId);
  });
}
