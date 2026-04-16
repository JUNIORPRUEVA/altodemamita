import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_calculator.dart';

void main() {
  test('genera una cuota fija con interes decreciente y capital creciente', () {
    const financedBalance = 900000.0;
    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: DateTime(2026, 3, 31),
      financedBalance: financedBalance,
      monthlyInterest: 1,
      installmentCount: 12,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(schedule, hasLength(12));

    final fixedInstallmentAmount = schedule.first.totalAmount;
    for (final installment in schedule) {
      expect(installment.totalAmount, fixedInstallmentAmount);
    }

    for (var index = 1; index < schedule.length; index++) {
      expect(
        schedule[index].interestAmount,
        lessThan(schedule[index - 1].interestAmount),
      );
      expect(
        schedule[index].principalAmount,
        greaterThan(schedule[index - 1].principalAmount),
      );
      expect(
        schedule[index].openingBalance,
        schedule[index - 1].endingBalance,
      );
    }

    final principalSum = schedule.fold<double>(
      0,
      (sum, installment) => sum + installment.principalAmount,
    );
    final interestSum = schedule.fold<double>(
      0,
      (sum, installment) => sum + installment.interestAmount,
    );
    final totalPayments = schedule.fold<double>(
      0,
      (sum, installment) => sum + installment.totalAmount,
    );

    expect(principalSum, closeTo(financedBalance, 0.0001));
    expect(totalPayments, closeTo(financedBalance + interestSum, 0.0001));
    expect(schedule.last.endingBalance, 0);
  });

  test('puede recalcular con cuota fija y menos cuotas futuras', () {
    const financedBalance = 900000.0;
    const monthlyInterest = 1.0;
    const installmentCount = 12;

    final fixedPayment = SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );

    final dueDates = List<DateTime>.generate(
      installmentCount,
      (index) => DateTime(2026, 4 + index, 30),
    );

    final schedule =
        SaleCalculator.buildInstallmentScheduleForDueDatesWithFixedPayment(
      saleId: 1,
      dueDates: dueDates,
      financedBalance: 700000,
      monthlyInterest: monthlyInterest,
      fixedPaymentAmount: fixedPayment,
      createdAt: DateTime(2026, 3, 31),
    );

    expect(schedule, isNotEmpty);
    expect(schedule.length, lessThan(dueDates.length));

    for (var index = 0; index < schedule.length; index++) {
      final installment = schedule[index];
      if (index < schedule.length - 1) {
        expect(installment.totalAmount, fixedPayment);
      } else {
        expect(installment.totalAmount, lessThanOrEqualTo(fixedPayment));
      }

      if (index == 0) {
        continue;
      }

      final previousInstallment = schedule[index - 1];
      expect(installment.openingBalance, previousInstallment.endingBalance);
      expect(
        installment.interestAmount,
        lessThan(previousInstallment.interestAmount),
      );
    }

    expect(schedule.last.endingBalance, 0);
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
  });
}