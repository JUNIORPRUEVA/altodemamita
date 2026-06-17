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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ProductsSyncRepository productsRepository;
  late SalesSyncRepository salesRepository;
  late InstallmentsSyncRepository installmentsRepository;
  late PaymentsSyncRepository paymentsRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('full_reconcile_');
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

  test('full reconciliation aligns local deleted counts with backend tombstones', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-1',
      'version': 1,
      'nombre': 'Cliente 1',
      'cedula': '001-0000001-1',
      'telefono': '8095551111',
      'direccion': 'Dir 1',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-active',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-sale-deleted',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '2',
      'metros_cuadrados': 110,
      'precio_por_metro': 950,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final clientId = (await db.query(DatabaseSchema.clientsTable, limit: 1)).single['id'];
    final productId = (await db.query(DatabaseSchema.lotsTable, limit: 1)).single['id'];
    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-active',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': productId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 500000,
      'inicial_porcentaje': 10,
      'inicial_monto': 50000,
      'monto_inicial_requerido': 50000,
      'monto_inicial_pagado': 50000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 450000,
      'saldo_pendiente': 450000,
      'interes_mensual': 1,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await productsRepository.mergeRemoteRecords([
      {
        'id': 'remote-product-delete-1',
        'sync_id': 'product-delete-1',
        'version': 2,
        'block_number': 'B',
        'lot_number': '2',
        'area': 90,
        'price_per_square_meter': 1200,
        'status': 'vendido',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);
    await salesRepository.mergeRemoteRecords([
      {
        'id': 'remote-sale-delete-1',
        'sync_id': 'sale-delete-1',
        'version': 2,
        'client_sync_id': 'client-1',
        'product_sync_id': 'product-sale-deleted',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 500000,
        'down_payment_percentage': 10,
        'down_payment_amount': 50000,
        'required_initial_payment': 50000,
        'paid_initial_payment': 50000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 450000,
        'pending_balance': 450000,
        'monthly_interest': 1,
        'installment_count': 12,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);
    await installmentsRepository.mergeRemoteRecords([
      {
        'id': 'remote-installment-delete-1',
        'sync_id': 'installment-delete-1',
        'version': 2,
        'sale_sync_id': 'sale-active',
        'installment_number': 1,
        'due_date': now,
        'opening_balance': 450000,
        'principal_amount': 37500,
        'interest_amount': 4500,
        'total_amount': 42000,
        'paid_amount': 0,
        'paid_principal_amount': 0,
        'paid_interest_amount': 0,
        'ending_balance': 412500,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);
    await paymentsRepository.mergeRemoteRecords([
      {
        'id': 'remote-payment-delete-1',
        'sync_id': 'payment-delete-1',
        'version': 2,
        'sale_sync_id': 'sale-active',
        'client_sync_id': 'client-1',
        'installment_sync_id': null,
        'payment_date': now,
        'amount_paid': 25000,
        'payment_method': 'transferencia',
        'payment_type': 'cuota',
        'reference': 'REF-1',
        'year_to_pay': '2026',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);
    expect(await _countDeleted(db, DatabaseSchema.lotsTable), 1);
    expect(await _countDeleted(db, DatabaseSchema.salesTable), 1);
    expect(await _countDeleted(db, DatabaseSchema.installmentsTable), 1);
    expect(await _countDeleted(db, DatabaseSchema.paymentsTable), 1);
  });
}

Future<int> _countDeleted(dynamic db, String tableName) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM $tableName WHERE deleted_at IS NOT NULL',
  );
  return (rows.single['total'] as num).toInt();
}
