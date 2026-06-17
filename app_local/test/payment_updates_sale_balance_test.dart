import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('payment_updates_sale_balance_test', () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale();
    final before = await harness.paymentsRepository.fetchSaleContext(saleId);
    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 2, 1),
        amountPaid: 500,
        paymentMethod: 'efectivo',
      ),
    );
    final after = await harness.paymentsRepository.fetchSaleContext(saleId);

    expect(before, isNotNull);
    expect(after, isNotNull);
    expect(after!.sale.pendingBalance, lessThan(before!.sale.pendingBalance));
  });
}
