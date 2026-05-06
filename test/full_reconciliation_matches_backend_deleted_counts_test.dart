import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ProductsSyncRepository productsRepository;
  late SalesSyncRepository salesRepository;
  late InstallmentsSyncRepository installmentsRepository;
  late PaymentsSyncRepository paymentsRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('reconcile_counts_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    productsRepository = ProductsSyncRepository(appDatabase: appDatabase);
    salesRepository = SalesSyncRepository(appDatabase: appDatabase);
    installmentsRepository = InstallmentsSyncRepository(appDatabase: appDatabase);
    paymentsRepository = PaymentsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('full_reconciliation_matches_backend_deleted_counts_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-1',
      'version': 1,
      'nombre': 'Cliente',
      'cedula': '001-0000001-1',
      'telefono': '8090000001',
      'direccion': 'Dir',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    for (var i = 1; i <= 10; i++) {
      final deleted = i <= 5 ? now : null;
      await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-$i',
        'version': 1,
        'manzana_numero': 'B',
        'solar_numero': '$i',
        'metros_cuadrados': 200,
        'precio_por_metro': 900,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': deleted,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
    }

    final productRows = await db.query(
      DatabaseSchema.lotsTable,
      columns: ['id', 'sync_id', 'deleted_at'],
      orderBy: 'id ASC',
    );
    final clientRow = await db.query(
      DatabaseSchema.clientsTable,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: ['client-1'],
      limit: 1,
    );
    final clientId = clientRow.single['id'];

    for (var i = 1; i <= 8; i++) {
      final productId = productRows[i - 1]['id'];
      final deleted = i <= 1 ? now : null;
      final state = deleted == null ? 'activa' : 'cancelada';
      await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-$i',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': productId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': now,
        'precio_venta': 500000,
        'inicial_porcentaje': 20,
        'inicial_monto': 100000,
        'monto_inicial_requerido': 100000,
        'monto_inicial_pagado': 100000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': now,
        'saldo_financiado': 400000,
        'saldo_pendiente': 400000,
        'interes_mensual': 1.5,
        'cantidad_cuotas': 12,
        'estado': state,
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': deleted,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
    }

    final sale2Row = await db.query(
      DatabaseSchema.salesTable,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: ['sale-2'],
      limit: 1,
    );
    final sale2Id = sale2Row.single['id'];

    for (var i = 1; i <= 454; i++) {
      final deleted = i <= 123 ? now : null;
      await db.insert(DatabaseSchema.installmentsTable, {
        'sync_id': 'inst-$i',
        'version': 1,
        'venta_id': sale2Id,
        'numero_cuota': i,
        'fecha_vencimiento': now,
        'saldo_inicial': 400000,
        'capital_cuota': 1000,
        'interes_cuota': 100,
        'monto_cuota': 1100,
        'monto_pagado': 0,
        'capital_pagado': 0,
        'interes_pagado': 0,
        'saldo_final': 399000,
        'estado': deleted == null ? 'pendiente' : 'cancelada',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': deleted,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
    }

    for (var i = 1; i <= 8; i++) {
      final deleted = i <= 4 ? now : null;
      await db.insert(DatabaseSchema.paymentsTable, {
        'sync_id': 'pay-$i',
        'version': 1,
        'venta_id': sale2Id,
        'cliente_id': clientId,
        'usuario_id': 1,
        'cuota_id': null,
        'fecha_pago': now,
        'monto_pagado': 1000,
        'metodo_pago': 'efectivo',
        'tipo_pago': 'cuota',
        'referencia': 'ref-$i',
        'ano_a_pagar': '2026',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': deleted,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
    }

    await productsRepository.mergeRemoteRecords(List.generate(5, (index) {
      final i = index + 6;
      return {
        'id': 'remote-product-$i',
        'sync_id': 'product-$i',
        'version': 2,
        'block_number': 'B',
        'lot_number': '$i',
        'area': 200,
        'price_per_square_meter': 900,
        'status': 'vendido',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      };
    }));

    await salesRepository.mergeRemoteRecords(List.generate(4, (index) {
      final i = index + 2;
      return {
        'id': 'remote-sale-$i',
        'sync_id': 'sale-$i',
        'version': 2,
        'client_sync_id': 'client-1',
        'product_sync_id': 'product-$i',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 500000,
        'down_payment_percentage': 20,
        'down_payment_amount': 100000,
        'required_initial_payment': 100000,
        'paid_initial_payment': 100000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 400000,
        'pending_balance': 400000,
        'monthly_interest': 1.5,
        'installment_count': 12,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      };
    }));

    await installmentsRepository.mergeRemoteRecords(List.generate(192, (index) {
      final i = index + 124;
      return {
        'id': 'remote-inst-$i',
        'sync_id': 'inst-$i',
        'version': 2,
        'sale_sync_id': 'sale-2',
        'installment_number': i,
        'due_date': now,
        'opening_balance': 400000,
        'principal_amount': 1000,
        'interest_amount': 100,
        'total_amount': 1100,
        'paid_amount': 0,
        'paid_principal_amount': 0,
        'paid_interest_amount': 0,
        'ending_balance': 399000,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      };
    }));

    await paymentsRepository.mergeRemoteRecords(List.generate(2, (index) {
      final i = index + 5;
      return {
        'id': 'remote-pay-$i',
        'sync_id': 'pay-$i',
        'version': 2,
        'sale_sync_id': 'sale-2',
        'client_sync_id': 'client-1',
        'installment_sync_id': null,
        'payment_date': now,
        'amount_paid': 1000,
        'payment_method': 'efectivo',
        'payment_type': 'cuota',
        'reference': 'ref-$i',
        'year_to_pay': '2026',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      };
    }));

    expect(await _countDeleted(db, DatabaseSchema.lotsTable), 10);
    expect(await _countDeleted(db, DatabaseSchema.salesTable), 5);
    expect(await _countDeleted(db, DatabaseSchema.installmentsTable), 315);
    expect(await _countDeleted(db, DatabaseSchema.paymentsTable), 6);

    expect(await _countActive(db, DatabaseSchema.salesTable), 3);
    expect(await _countActive(db, DatabaseSchema.installmentsTable), 139);
    expect(await _countActive(db, DatabaseSchema.paymentsTable), 2);
  });
}

Future<int> _countDeleted(dynamic db, String tableName) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM $tableName WHERE deleted_at IS NOT NULL',
  );
  return (rows.single['total'] as num).toInt();
}

Future<int> _countActive(dynamic db, String tableName) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM $tableName WHERE deleted_at IS NULL',
  );
  return (rows.single['total'] as num).toInt();
}
