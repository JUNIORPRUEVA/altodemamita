import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('payment_uses_installment_number_fallback_when_target_id_is_stale_test',
      () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 4,
    );

    final before = await harness.paymentsRepository.fetchSaleContext(saleId);
    expect(before, isNotNull);
    expect(before!.overdueInstallments, isNotEmpty);

    final target = before.overdueInstallments.first;
    final firstPaymentAmount = (target.remainingAmount / 2).toDouble();

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 5, 6, 20, 30),
        amountPaid: firstPaymentAmount,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: target.id,
        targetInstallmentNumber: target.installmentNumber,
      ),
    );

    final middle = await harness.paymentsRepository.fetchSaleContext(saleId);
    final updatedTarget = middle!.installments.firstWhere(
      (i) => i.installmentNumber == target.installmentNumber,
    );
    final remaining = updatedTarget.remainingAmount;
    expect(remaining, greaterThan(0));

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 5, 6, 20, 40),
        amountPaid: remaining,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: 999999,
        targetInstallmentNumber: target.installmentNumber,
      ),
    );

    final after = await harness.paymentsRepository.fetchSaleContext(saleId);
    final fullyPaidInstallment = after!.installments.firstWhere(
      (i) => i.installmentNumber == target.installmentNumber,
    );
    expect(fullyPaidInstallment.status, 'pagada');
    expect(fullyPaidInstallment.remainingAmount, closeTo(0, 0.01));

    final db = await harness.appDatabase.database;
    final paymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ? AND cuota_id = ? AND tipo_pago = ? AND deleted_at IS NULL',
      whereArgs: [saleId, fullyPaidInstallment.id, 'cuota'],
    );
    expect(paymentRows.length, 2);
  });
}
