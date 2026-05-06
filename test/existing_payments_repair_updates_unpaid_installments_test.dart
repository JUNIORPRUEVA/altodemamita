import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/database_schema.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('existing_payments_repair_updates_unpaid_installments_test', () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 2,
    );
    final db = await harness.appDatabase.database;

    final installment = (await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ? AND deleted_at IS NULL',
      whereArgs: [saleId],
      orderBy: 'numero_cuota ASC',
      limit: 1,
    )).first;

    final sale = (await db.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).first;

    final paid = ((installment['monto_cuota'] as num).toDouble() / 2);
    await db.insert(DatabaseSchema.paymentsTable, {
      'sync_id': 'repair-payment-1',
      'venta_id': saleId,
      'cliente_id': sale['cliente_id'],
      'usuario_id': 1,
      'cuota_id': installment['id'],
      'fecha_pago': DateTime.now().toIso8601String(),
      'monto_pagado': paid,
      'metodo_pago': 'efectivo',
      'tipo_pago': 'cuota',
      'referencia': 'REPAIR-1',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPending,
    });

    final report = await harness.paymentsRepository
        .repairExistingPaymentApplicationInconsistencies();

    final after = (await db.query(
      DatabaseSchema.installmentsTable,
      where: 'id = ?',
      whereArgs: [installment['id']],
      limit: 1,
    )).first;

    expect(report.fixedInstallments, greaterThan(0));
    expect((after['monto_pagado'] as num).toDouble(), closeTo(paid, 0.01));
    expect(after['estado'], 'parcial');
  });
}
