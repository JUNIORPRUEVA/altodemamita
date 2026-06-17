import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late PaymentsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'payments_delete_ack_tombstone_',
    );
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

  test('payments_delete_ack_never_hard_deletes_test', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 13, 0).toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-payment-delete-ref-1',
      'version': 1,
      'nombre': 'Cliente Pago',
      'cedula': '00100000003',
      'telefono': '8095550303',
      'direccion': 'Calle Pago',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-payment-delete-ref-1',
      'version': 1,
      'manzana_numero': 'E',
      'solar_numero': '09',
      'metros_cuadrados': 200,
      'precio_por_metro': 3000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final saleId = await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-payment-delete-ref-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 600000,
      'inicial_porcentaje': 10,
      'inicial_monto': 60000,
      'monto_inicial_requerido': 60000,
      'monto_inicial_pagado': 60000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 540000,
      'saldo_pendiente': 540000,
      'interes_mensual': 1,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await db.insert(DatabaseSchema.paymentsTable, {
      'sync_id': 'payment-sync-delete-1',
      'version': 2,
      'venta_id': saleId,
      'cliente_id': clientId,
      'usuario_id': 1,
      'cuota_id': null,
      'fecha_pago': now,
      'monto_pagado': 25000,
      'metodo_pago': 'efectivo',
      'tipo_pago': 'abono',
      'referencia': 'PAY-DELETE-1',
      'ano_a_pagar': '2026',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingDelete,
    });

    await repository.markAsSynced(['payment-sync-delete-1']);

    final paymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'sync_id = ?',
      whereArgs: ['payment-sync-delete-1'],
      limit: 1,
    );

    expect(paymentRows, hasLength(1));
    expect(paymentRows.single['deleted_at'], isNotNull);
    expect(paymentRows.single['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}
