import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

/// POLITICA DE MORA EN LA ASIGNACION DE PAGOS (regresion fijada)
/// ==============================================================
/// El sistema imputa el pago en este orden: **mora -> interes -> capital**,
/// igual que el backend autoritativo (`applyToInstallment`). Consecuencias que
/// esta prueba fija para que nadie las cambie por accidente:
///
/// 1. Con mora habilitada y una cuota muy vencida, pagar SOLO el monto de la
///    cuota NO la deja `pagada`: parte del dinero cubre mora y la cuota queda
///    `parcial`. No es una perdida de pago, es la regla vigente.
/// 2. La mora cobrada queda registrada (`mora_aplicada`) y no desaparece.
/// 3. Pagando cuota + mora la cuota queda `pagada` y el saldo de la venta baja
///    exactamente lo amortizado.
///
/// Estas dos ultimas comprobaciones son la red contra el defecto historico de
/// "pago aplicado a mora sin dejar rastro" y contra el recalculado que dejaba
/// saldo fantasma.
void main() {
  test('la mora se cobra primero y queda trazada', () async {
    final harness = await PaymentApplicationTestHarness.create(
      lateFeeEnabled: true,
    );
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 2,
    );
    final db = await harness.appDatabase.database;
    final context = await harness.paymentsRepository.fetchSaleContext(saleId);
    final target = context!.overdueInstallments.first;

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 3, 1),
        amountPaid: target.remainingAmount,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: target.id,
      ),
    );

    final rows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'cuota_id = ? AND deleted_at IS NULL',
      whereArgs: [target.id],
    );
    expect(rows, hasLength(1));
    final lateFeeApplied = (rows.first['mora_aplicada'] as num).toDouble();
    final principalApplied = (rows.first['capital_aplicado'] as num).toDouble();
    final interestApplied = (rows.first['interes_aplicado'] as num).toDouble();

    expect(
      lateFeeApplied,
      greaterThan(0),
      reason: 'La mora acumulada debe imputarse y quedar registrada.',
    );
    expect(
      principalApplied + interestApplied,
      0,
      reason: 'Con la cuota muy vencida el pago se consume integramente en mora.',
    );

    final refreshed = await harness.paymentsRepository.fetchSaleContext(saleId);
    final updated = refreshed!.installments.firstWhere(
      (item) => item.id == target.id,
    );
    expect(
      updated.status,
      isNot('pagada'),
      reason: 'Pagar solo la cuota no salda la deuda cuando hay mora.',
    );
    expect(updated.remainingAmount, closeTo(target.remainingAmount, 0.01));
  });

  test('pagar cuota + mora deja la cuota pagada y el saldo correcto', () async {
    final harness = await PaymentApplicationTestHarness.create(
      lateFeeEnabled: true,
    );
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 2,
    );
    final db = await harness.appDatabase.database;
    final context = await harness.paymentsRepository.fetchSaleContext(saleId);
    final target = context!.overdueInstallments.first;

    final paymentDate = DateTime(2026, 3, 1);
    final dueDate = DateTime(
      target.dueDate.year,
      target.dueDate.month,
      target.dueDate.day,
    );
    final overdueDays = paymentDate.difference(dueDate).inDays;
    const dailyRate = 0.005;
    const graceDays = 5;
    final lateFeeDays = overdueDays > graceDays ? overdueDays - graceDays : 0;
    final expectedLateFee = target.remainingAmount * dailyRate * lateFeeDays;

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: paymentDate,
        amountPaid: target.remainingAmount + expectedLateFee,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: target.id,
      ),
    );

    final refreshed = await harness.paymentsRepository.fetchSaleContext(saleId);
    final updated = refreshed!.installments.firstWhere(
      (item) => item.id == target.id,
    );
    expect(updated.status, 'pagada');
    expect(updated.remainingAmount, closeTo(0, 0.01));
    expect(updated.paidAmount, closeTo(target.totalAmount, 0.01));

    final payments = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'cuota_id = ? AND deleted_at IS NULL',
      whereArgs: [target.id],
    );
    final lateFeeApplied = (payments.first['mora_aplicada'] as num).toDouble();
    expect(lateFeeApplied, closeTo(expectedLateFee, 0.05));

    final saleRow = (await db.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [saleId],
    )).first;
    final saleBalance = (saleRow['saldo_pendiente'] as num).toDouble();
    final capitalOutstanding = refreshed.installments.fold<double>(
      0,
      (sum, item) => sum + (item.principalAmount - item.paidPrincipalAmount),
    );
    expect(
      saleBalance,
      closeTo(capitalOutstanding, 0.02),
      reason: 'El saldo de la venta es el capital insoluto del calendario.',
    );
  });
}
