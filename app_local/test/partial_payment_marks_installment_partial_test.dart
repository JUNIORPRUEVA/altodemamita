import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('partial_payment_marks_installment_partial_test', () async {
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
        amountPaid: target.remainingAmount / 2,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: target.id,
      ),
    );

    final refreshed = await harness.paymentsRepository.fetchSaleContext(saleId);
    final updated = refreshed!.installments.firstWhere(
      (i) => i.id == target.id,
    );
    expect(updated.status, 'parcial');
    expect(updated.paidAmount, greaterThan(0));
    expect(updated.paidAmount, lessThan(updated.totalAmount));
  });
}
