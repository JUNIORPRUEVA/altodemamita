import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('payment_cannot_be_saved_without_installment_effect_test', () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 2,
    );
    final context = await harness.paymentsRepository.fetchSaleContext(saleId);
    final targetInstallment = context!.overdueInstallments.first;

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 3, 1),
        amountPaid: targetInstallment.remainingAmount,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: targetInstallment.id,
      ),
    );

    expect(
      () => harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 3, 2),
          amountPaid: 10,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuota_vencida',
          targetInstallmentId: targetInstallment.id,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
