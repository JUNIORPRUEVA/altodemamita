import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_calculator.dart';

void main() {
  test('caso 450000 @1% 120m: cuota fija en todas las filas y cierre en 0', () {
    const financedBalance = 450000.0;
    const monthlyInterest = 1.0;
    const installmentCount = 120;

    final fixedPayment = SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );

    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: DateTime(2026, 3, 31),
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(fixedPayment, closeTo(6456.192678, 0.000001));
    expect(schedule, hasLength(120));

    final first = schedule[0];
    expect(first.openingBalance, closeTo(450000, 0.0001));
    expect(first.interestAmount, closeTo(4500, 0.0001));
    expect(first.principalAmount, closeTo(1956.192678, 0.0001));
    expect(first.totalAmount, closeTo(fixedPayment, 0.000001));
    expect(first.endingBalance, closeTo(448043.8073, 0.001));

    final second = schedule[1];
    expect(second.interestAmount, closeTo(4480.44, 0.0001));
    expect(second.principalAmount, closeTo(1975.752678, 0.0001));
    expect(second.totalAmount, closeTo(fixedPayment, 0.000001));
    expect(second.endingBalance, closeTo(446068.0546, 0.001));

    for (final installment in schedule) {
      expect(
        installment.totalAmount,
        closeTo(fixedPayment, 0.000001),
      );
    }

    final last = schedule.last;
    expect(last.totalAmount, closeTo(fixedPayment, 0.000001));
    expect(last.endingBalance, closeTo(0, 0.000001));
  });

  test('caso 562500 @1% 120m: cuota fija en todas las filas y cierre en 0', () {
    const financedBalance = 562500.0;
    const monthlyInterest = 1.0;
    const installmentCount = 120;

    final fixedPayment = SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );

    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: DateTime(2026, 3, 31),
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(fixedPayment, closeTo(8070.240847645539, 0.000001));
    expect(schedule, hasLength(120));

    for (final installment in schedule) {
      expect(installment.totalAmount, closeTo(fixedPayment, 0.000001));
    }

    final last = schedule.last;
    expect(last.totalAmount, closeTo(fixedPayment, 0.000001));
    expect(last.endingBalance, closeTo(0, 0.000001));
  });

  test('recalculo con pago fijo mantiene interes sobre saldo insoluto', () {
    const financedBalance = 450000.0;
    const monthlyInterest = 1.0;
    const installmentCount = 120;

    final fixedPayment = SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );

    final dueDates = List<DateTime>.generate(
      installmentCount,
      (index) => DateTime(2026, 4, 30 + index),
    );

    final schedule =
        SaleCalculator.buildInstallmentScheduleForDueDatesWithFixedPayment(
      saleId: 1,
      dueDates: dueDates,
      financedBalance: 300000,
      monthlyInterest: monthlyInterest,
      fixedPaymentAmount: fixedPayment,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(schedule, isNotEmpty);
    expect(schedule.length, lessThan(dueDates.length));
    expect(schedule.first.interestAmount, 3000);
    expect(
      schedule[1].interestAmount,
      lessThan(schedule.first.interestAmount),
    );
    expect(schedule.last.endingBalance, 0);
    for (final installment in schedule) {
      expect(
        installment.totalAmount,
        closeTo(schedule.first.totalAmount, 0.000001),
      );
    }
  });

  test('calcula resumen contractual con PMT (sin interes fijo simple)', () {
    expect(
      SaleCalculator.calculateFixedMonthlyInterestAmount(
        financedBalance: 450000,
        monthlyInterest: 1,
      ),
      4500,
    );
    expect(
      SaleCalculator.calculateTotalInterestAmount(
        financedBalance: 450000,
        monthlyInterest: 1,
        installmentCount: 120,
      ),
      closeTo(324743.12, 0.01),
    );
    expect(
      SaleCalculator.calculateTotalFinancingAmount(
        financedBalance: 450000,
        monthlyInterest: 1,
        installmentCount: 120,
      ),
      closeTo(774743.12, 0.01),
    );
  });

  test('usa division simple cuando la tasa mensual es cero', () {
    final payment = SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: 120000,
      monthlyInterest: 0,
      installmentCount: 12,
    );

    expect(payment, 10000);
  });

  test('tasa 0 mantiene cuota fija y saldo final en 0', () {
    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: DateTime(2026, 3, 31),
      financedBalance: 100000,
      monthlyInterest: 0,
      installmentCount: 3,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(schedule, hasLength(3));
    expect(schedule[0].totalAmount, closeTo(schedule[1].totalAmount, 0.000001));
    expect(schedule[1].totalAmount, closeTo(schedule[2].totalAmount, 0.000001));
    expect(schedule.every((item) => item.interestAmount >= 0), isTrue);
    expect(schedule.last.endingBalance, 0);
    expect(schedule.every((item) => item.endingBalance >= 0), isTrue);
  });

  test('monto pequeno no deja residuos ni saldos negativos', () {
    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 99,
      saleDate: DateTime(2026, 1, 1),
      financedBalance: 100,
      monthlyInterest: 1,
      installmentCount: 12,
      createdAt: DateTime(2026, 1, 1),
    );

    expect(schedule, hasLength(12));
    expect(schedule.last.endingBalance, 0);
    expect(schedule.every((item) => item.endingBalance >= 0), isTrue);
    expect(
      schedule.fold<double>(0, (sum, item) => sum + item.principalAmount),
      closeTo(100, 0.01),
    );
  });
}