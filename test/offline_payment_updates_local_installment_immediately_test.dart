import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('offline_payment_updates_local_installment_immediately_test', () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 2,
    );
    final context = await harness.paymentsRepository.fetchSaleContext(saleId);
    final target = context!.overdueInstallments.first;

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 3, 1),
        amountPaid: 100,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: target.id,
      ),
    );

    final db = await harness.appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.installmentsTable,
      columns: ['monto_pagado', 'sync_status'],
      where: 'id = ?',
      whereArgs: [target.id],
      limit: 1,
    );

    expect(rows, isNotEmpty);
    expect((rows.first['monto_pagado'] as num).toDouble(), greaterThan(0));
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusPending);
  });
}
