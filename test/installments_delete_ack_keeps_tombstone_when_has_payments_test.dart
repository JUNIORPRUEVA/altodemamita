import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late InstallmentsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'installments_delete_ack_tombstone_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = InstallmentsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'installments_delete_ack_keeps_tombstone_when_has_payments_test',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 5, 5, 12, 30).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-installment-delete-ref-1',
        'version': 1,
        'nombre': 'Cliente Cuota',
        'cedula': '00100000002',
        'telefono': '8095550202',
        'direccion': 'Calle Cuota',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'lot-installment-delete-ref-1',
        'version': 1,
        'manzana_numero': 'D',
        'solar_numero': '08',
        'metros_cuadrados': 190,
        'precio_por_metro': 2600,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-installment-delete-ref-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': now,
        'precio_venta': 520000,
        'inicial_porcentaje': 10,
        'inicial_monto': 52000,
        'monto_inicial_requerido': 52000,
        'monto_inicial_pagado': 52000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': now,
        'saldo_financiado': 468000,
        'saldo_pendiente': 468000,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final installmentId = await db.insert(DatabaseSchema.installmentsTable, {
        'sync_id': 'installment-sync-delete-payment-1',
        'version': 3,
        'venta_id': saleId,
        'numero_cuota': 1,
        'fecha_vencimiento': now,
        'saldo_inicial': 468000,
        'capital_cuota': 39000,
        'interes_cuota': 4680,
        'monto_cuota': 43680,
        'monto_pagado': 0,
        'capital_pagado': 0,
        'interes_pagado': 0,
        'saldo_final': 429000,
        'estado': 'pendiente',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': now,
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
      });

      await db.insert(DatabaseSchema.paymentsTable, {
        'sync_id': 'payment-installment-delete-ref-1',
        'version': 1,
        'venta_id': saleId,
        'cliente_id': clientId,
        'usuario_id': 1,
        'cuota_id': installmentId,
        'fecha_pago': now,
        'monto_pagado': 43680,
        'metodo_pago': 'transferencia',
        'tipo_pago': 'cuota',
        'referencia': 'PAY-001',
        'ano_a_pagar': '2026',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await repository.markAsSynced(['installment-sync-delete-payment-1']);

      final installmentRows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'sync_id = ?',
        whereArgs: ['installment-sync-delete-payment-1'],
        limit: 1,
      );
      final paymentRows = await db.query(
        DatabaseSchema.paymentsTable,
        columns: ['cuota_id'],
        where: 'sync_id = ?',
        whereArgs: ['payment-installment-delete-ref-1'],
        limit: 1,
      );

      expect(installmentRows, hasLength(1));
      expect(installmentRows.single['deleted_at'], isNotNull);
      expect(
        installmentRows.single['sync_status'],
        DatabaseSchema.syncStatusSynced,
      );
      expect(paymentRows, hasLength(1));
      expect(paymentRows.single['cuota_id'], installmentId);
    },
  );
}
