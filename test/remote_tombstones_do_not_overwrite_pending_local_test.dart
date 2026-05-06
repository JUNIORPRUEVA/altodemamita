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
    tempDirectory = await Directory.systemTemp.createTemp(
      'remote_tombstones_pending_local_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    productsRepository = ProductsSyncRepository(appDatabase: appDatabase);
    salesRepository = SalesSyncRepository(appDatabase: appDatabase);
    installmentsRepository = InstallmentsSyncRepository(
      appDatabase: appDatabase,
    );
    paymentsRepository = PaymentsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('products remote tombstone does not overwrite pending local row', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 18, 0).toIso8601String();

    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-pending-1',
      'version': 3,
      'manzana_numero': 'A',
      'solar_numero': '11',
      'metros_cuadrados': 120,
      'precio_por_metro': 2400,
      'estado': 'disponible',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'last_modified_local': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    await productsRepository.mergeRemoteRecords([
      {
        'id': 101,
        'sync_id': 'product-pending-1',
        'version': 99,
        'block_number': 'A',
        'lot_number': '11',
        'area': 120,
        'price_per_square_meter': 2400,
        'status': 'disponible',
        'created_at': now,
        'updated_at': DateTime(2026, 5, 5, 19, 0).toIso8601String(),
        'deleted_at': DateTime(2026, 5, 5, 19, 0).toIso8601String(),
      },
    ]);

    final row = (await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['product-pending-1'],
      limit: 1,
    )).single;

    expect(row['deleted_at'], isNull);
    expect(row['sync_status'], DatabaseSchema.syncStatusPendingUpdate);
    expect(row['version'], 3);
  });

  test('sales remote tombstone does not overwrite pending local row', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 18, 5).toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-sales-pending-1',
      'version': 1,
      'nombre': 'Cliente',
      'cedula': '00100000011',
      'telefono': '8095551111',
      'direccion': 'Calle 1',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-sales-pending-1',
      'version': 1,
      'manzana_numero': 'B',
      'solar_numero': '12',
      'metros_cuadrados': 180,
      'precio_por_metro': 2500,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-pending-1',
      'version': 4,
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
      'interes_mensual': 0,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'last_modified_local': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    await salesRepository.mergeRemoteRecords([
      {
        'id': 201,
        'sync_id': 'sale-pending-1',
        'version': 99,
        'client_sync_id': 'client-sales-pending-1',
        'product_sync_id': 'lot-sales-pending-1',
        'seller_sync_id': null,
        'sale_date': now,
        'sale_price': 450000,
        'down_payment_percentage': 10,
        'down_payment_amount': 45000,
        'required_initial_payment': 45000,
        'paid_initial_payment': 45000,
        'pending_initial_payment': 0,
        'minimum_reserve_amount': null,
        'initial_payment_deadline': null,
        'activation_date': now,
        'financed_balance': 405000,
        'pending_balance': 405000,
        'monthly_interest': 0,
        'installment_count': 12,
        'status': 'cancelada',
        'created_at': now,
        'updated_at': DateTime(2026, 5, 5, 19, 5).toIso8601String(),
        'deleted_at': DateTime(2026, 5, 5, 19, 5).toIso8601String(),
      },
    ]);

    final row = (await db.query(
      DatabaseSchema.salesTable,
      where: 'sync_id = ?',
      whereArgs: ['sale-pending-1'],
      limit: 1,
    )).single;

    expect(row['deleted_at'], isNull);
    expect(row['sync_status'], DatabaseSchema.syncStatusPendingUpdate);
    expect(row['version'], 4);
  });

  test(
    'installments remote tombstone does not overwrite pending local row',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 5, 5, 18, 10).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-installment-pending-1',
        'version': 1,
        'nombre': 'Cliente Cuota',
        'cedula': '00100000012',
        'telefono': '8095551212',
        'direccion': 'Calle 2',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'lot-installment-pending-1',
        'version': 1,
        'manzana_numero': 'C',
        'solar_numero': '13',
        'metros_cuadrados': 200,
        'precio_por_metro': 2600,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-installment-pending-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
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
        'interes_mensual': 0,
        'cantidad_cuotas': 18,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await db.insert(DatabaseSchema.installmentsTable, {
        'sync_id': 'installment-pending-1',
        'version': 2,
        'venta_id': saleId,
        'numero_cuota': 1,
        'fecha_vencimiento': now,
        'saldo_inicial': 450000,
        'capital_cuota': 25000,
        'interes_cuota': 0,
        'monto_cuota': 25000,
        'monto_pagado': 0,
        'capital_pagado': 0,
        'interes_pagado': 0,
        'saldo_final': 425000,
        'estado': 'pendiente',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'last_modified_local': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPendingUpdate,
      });

      await installmentsRepository.mergeRemoteRecords([
        {
          'id': 301,
          'sync_id': 'installment-pending-1',
          'version': 99,
          'sale_sync_id': 'sale-installment-pending-1',
          'installment_number': 1,
          'due_date': now,
          'opening_balance': 450000,
          'principal_amount': 25000,
          'interest_amount': 0,
          'total_amount': 25000,
          'paid_amount': 0,
          'paid_principal_amount': 0,
          'paid_interest_amount': 0,
          'ending_balance': 425000,
          'status': 'cancelada',
          'created_at': now,
          'updated_at': DateTime(2026, 5, 5, 19, 10).toIso8601String(),
          'deleted_at': DateTime(2026, 5, 5, 19, 10).toIso8601String(),
        },
      ]);

      final row = (await db.query(
        DatabaseSchema.installmentsTable,
        where: 'sync_id = ?',
        whereArgs: ['installment-pending-1'],
        limit: 1,
      )).single;

      expect(row['deleted_at'], isNull);
      expect(row['sync_status'], DatabaseSchema.syncStatusPendingUpdate);
      expect(row['version'], 2);
    },
  );

  test('payments remote tombstone does not overwrite pending local row', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 18, 15).toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-payment-pending-1',
      'version': 1,
      'nombre': 'Cliente Pago',
      'cedula': '00100000013',
      'telefono': '8095551313',
      'direccion': 'Calle 3',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-payment-pending-1',
      'version': 1,
      'manzana_numero': 'D',
      'solar_numero': '14',
      'metros_cuadrados': 210,
      'precio_por_metro': 2700,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final saleId = await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-payment-pending-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 620000,
      'inicial_porcentaje': 10,
      'inicial_monto': 62000,
      'monto_inicial_requerido': 62000,
      'monto_inicial_pagado': 62000,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 558000,
      'saldo_pendiente': 558000,
      'interes_mensual': 0,
      'cantidad_cuotas': 24,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await db.insert(DatabaseSchema.paymentsTable, {
      'sync_id': 'payment-pending-1',
      'version': 2,
      'venta_id': saleId,
      'cliente_id': clientId,
      'usuario_id': 1,
      'cuota_id': null,
      'fecha_pago': now,
      'monto_pagado': 25000,
      'metodo_pago': 'transferencia',
      'tipo_pago': 'cuota',
      'referencia': 'REF-1',
      'ano_a_pagar': 2026,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'last_modified_local': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    await paymentsRepository.mergeRemoteRecords([
      {
        'id': 401,
        'sync_id': 'payment-pending-1',
        'version': 99,
        'sale_sync_id': 'sale-payment-pending-1',
        'client_sync_id': 'client-payment-pending-1',
        'installment_sync_id': null,
        'payment_date': now,
        'amount_paid': 25000,
        'payment_method': 'transferencia',
        'payment_type': 'cuota',
        'reference': 'REF-1',
        'year_to_pay': 2026,
        'created_at': now,
        'updated_at': DateTime(2026, 5, 5, 19, 15).toIso8601String(),
        'deleted_at': DateTime(2026, 5, 5, 19, 15).toIso8601String(),
      },
    ]);

    final row = (await db.query(
      DatabaseSchema.paymentsTable,
      where: 'sync_id = ?',
      whereArgs: ['payment-pending-1'],
      limit: 1,
    )).single;

    expect(row['deleted_at'], isNull);
    expect(row['sync_status'], DatabaseSchema.syncStatusPendingUpdate);
    expect(row['version'], 2);
  });
}