import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('payment_applies_to_overdue_installment_test', () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 3,
    );
    final context = await harness.paymentsRepository.fetchSaleContext(saleId);
    expect(context, isNotNull);
    expect(context!.overdueInstallments.length, greaterThan(1));

    final selected = context.overdueInstallments.last;
    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 3, 1),
        amountPaid: 100,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: selected.id,
      ),
    );

    final db = await harness.appDatabase.database;
    final paymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ? AND tipo_pago = ? AND deleted_at IS NULL',
      whereArgs: [saleId, 'cuota'],
      orderBy: 'id DESC',
      limit: 1,
    );

    expect(paymentRows, isNotEmpty);
    expect(paymentRows.first['cuota_id'], selected.id);
  });
}
