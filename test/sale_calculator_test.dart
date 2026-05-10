import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_calculator.dart';

void main() {
  test('calcula cuota PMT y amortizacion sobre saldo insoluto (caso Excel)', () {
    const financedBalance = 562500.0;
    const monthlyInterest = 1.0;
    const installmentCount = 120;

    final estimatedInstallment = SaleCalculator.calculateEstimatedInstallmentAmount(
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

    expect(estimatedInstallment, closeTo(8070.240847645539, 0.000001));
    expect(schedule, hasLength(120));

    final first = schedule.first;
    expect(first.totalAmount, 8070.24);
    expect(first.openingBalance, 562500);
    expect(first.interestAmount, 5625);
    expect(first.principalAmount, 2445.24);
    expect(first.endingBalance, 560054.76);

    final last = schedule.last;
    expect(last.endingBalance, 0);
    expect(last.totalAmount, greaterThan(0));

    final totalPrincipal = schedule.fold<double>(
      0,
      (sum, installment) => sum + installment.principalAmount,
    );
    expect(totalPrincipal, closeTo(financedBalance, 0.01));

    final totalAmount = schedule.fold<double>(
      0,
      (sum, installment) => sum + installment.totalAmount,
    );
    final totalInterest = schedule.fold<double>(
      0,
      (sum, installment) => sum + installment.interestAmount,
    );
    expect(totalAmount, closeTo(totalPrincipal + totalInterest, 0.01));
    expect(schedule.every((item) => item.endingBalance >= 0), isTrue);
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
    expect(schedule.every((item) => item.totalAmount >= 0), isTrue);
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

  test('ajusta la ultima cuota por redondeo sin generar interes negativo', () {
    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: DateTime(2026, 3, 31),
      financedBalance: 100000,
      monthlyInterest: 0,
      installmentCount: 3,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(schedule, hasLength(3));
    expect(schedule[0].totalAmount, 33333.33);
    expect(schedule[1].totalAmount, 33333.33);
    expect(schedule[2].totalAmount, 33333.34);
    expect(schedule.every((item) => item.interestAmount >= 0), isTrue);
    expect(
      schedule.fold<double>(0, (sum, item) => sum + item.principalAmount),
      closeTo(100000, 0.0001),
    );
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