import 'dart:math';

import '../../installments/domain/installment.dart';

class SaleCalculator {
  static double calculateDownPaymentAmount({
    required double salePrice,
    required double downPaymentPercentage,
  }) {
    return _roundCurrency(salePrice * (downPaymentPercentage / 100));
  }

  static double calculateFinancedBalance({
    required double salePrice,
    required double downPaymentAmount,
  }) {
    final normalizedDownPayment = downPaymentAmount.clamp(0, salePrice);
    return _roundCurrency(salePrice - normalizedDownPayment);
  }

  static double calculatePendingInitialPayment({
    required double requiredInitialPayment,
    required double initialPaymentPaid,
  }) {
    final remaining = requiredInitialPayment - initialPaymentPaid;
    return remaining <= 0 ? 0 : _roundCurrency(remaining);
  }

  /// Devuelve la cuota fija mensual del financiamiento.
  static double calculateEstimatedInstallmentAmount({
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    if (installmentCount <= 0) {
      return 0;
    }

    return _calculateFixedPayment(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );
  }

  static List<Installment> buildInstallmentSchedule({
    required int saleId,
    required DateTime saleDate,
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
    required DateTime createdAt,
  }) {
    if (installmentCount <= 0 || financedBalance <= 0) {
      return const [];
    }

    final dueDates = List<DateTime>.generate(
      installmentCount,
      (index) => _addMonths(saleDate, index + 1),
    );

    return buildInstallmentScheduleForDueDates(
      saleId: saleId,
      dueDates: dueDates,
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      createdAt: createdAt,
    );
  }

  static List<Installment> buildInstallmentScheduleForDueDates({
    required int saleId,
    required List<DateTime> dueDates,
    required double financedBalance,
    required double monthlyInterest,
    required DateTime createdAt,
    int startingInstallmentNumber = 1,
    DateTime? updatedAt,
    List<int?>? installmentIds,
  }) {
    if (dueDates.isEmpty || financedBalance <= 0) {
      return const [];
    }

    final monthlyRate = monthlyInterest / 100;
    final paymentAmount = _calculateFixedPayment(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: dueDates.length,
    );
    final paymentCents = _toCents(paymentAmount);
    var balanceCents = _toCents(financedBalance);
    final installments = <Installment>[];
    final resolvedUpdatedAt = updatedAt ?? createdAt;

    for (var index = 0; index < dueDates.length; index++) {
      final openingBalanceCents = balanceCents;
      if (openingBalanceCents <= 0) {
        break;
      }

      final isLastInstallment = index == dueDates.length - 1;
      var interestCents = _toCents((_fromCents(openingBalanceCents)) * monthlyRate);
      var principalCents = paymentCents - interestCents;
      var totalAmountCents = paymentCents;

      if (principalCents < 0) {
        principalCents = 0;
        interestCents = paymentCents;
        totalAmountCents = paymentCents;
      }

      if (principalCents >= openingBalanceCents || isLastInstallment) {
        principalCents = openingBalanceCents;
        final adjustedInterestCents = paymentCents - principalCents;
        if (adjustedInterestCents >= 0) {
          interestCents = adjustedInterestCents;
          totalAmountCents = paymentCents;
        } else {
          totalAmountCents = principalCents + interestCents;
        }
      }

      final endingBalanceCents = (principalCents >= openingBalanceCents || isLastInstallment)
          ? 0
          : openingBalanceCents - principalCents;

      installments.add(
        Installment(
          id: installmentIds != null && index < installmentIds.length
              ? installmentIds[index]
              : null,
          saleId: saleId,
          installmentNumber: startingInstallmentNumber + index,
          dueDate: dueDates[index],
          openingBalance: _fromCents(openingBalanceCents),
          principalAmount: _fromCents(principalCents),
          interestAmount: _fromCents(interestCents),
          totalAmount: _fromCents(totalAmountCents),
          paidAmount: 0,
          paidPrincipalAmount: 0,
          paidInterestAmount: 0,
          endingBalance: _fromCents(endingBalanceCents),
          status: 'pendiente',
          createdAt: createdAt,
          updatedAt: resolvedUpdatedAt,
        ),
      );

      balanceCents = endingBalanceCents;
    }

    return installments;
  }

  static List<Installment> buildInstallmentScheduleForDueDatesWithFixedPayment({
    required int saleId,
    required List<DateTime> dueDates,
    required double financedBalance,
    required double monthlyInterest,
    required double fixedPaymentAmount,
    required DateTime createdAt,
    int startingInstallmentNumber = 1,
    DateTime? updatedAt,
    List<int?>? installmentIds,
  }) {
    if (dueDates.isEmpty || financedBalance <= 0 || fixedPaymentAmount <= 0) {
      return const [];
    }

    final monthlyRate = monthlyInterest / 100;
    final fixedPaymentCents = _toCents(fixedPaymentAmount);
    var balanceCents = _toCents(financedBalance);
    final installments = <Installment>[];
    final resolvedUpdatedAt = updatedAt ?? createdAt;

    for (var index = 0; index < dueDates.length; index++) {
      final openingBalanceCents = balanceCents;
      if (openingBalanceCents <= 0) {
        break;
      }

      var interestCents = monthlyRate == 0
          ? 0
          : _toCents(_fromCents(openingBalanceCents) * monthlyRate);
      var totalAmountCents = fixedPaymentCents;
      var principalCents = totalAmountCents - interestCents;

      if (principalCents < 0) {
        principalCents = 0;
        totalAmountCents = interestCents;
      }

      final payoffAmountCents = openingBalanceCents + interestCents;
      if (payoffAmountCents <= fixedPaymentCents) {
        principalCents = openingBalanceCents;
        totalAmountCents = payoffAmountCents;
      } else if (principalCents >= openingBalanceCents) {
        principalCents = openingBalanceCents;
        totalAmountCents = payoffAmountCents;
      }

      final endingBalanceCents = (openingBalanceCents - principalCents).clamp(
        0,
        openingBalanceCents,
      );

      installments.add(
        Installment(
          id: installmentIds != null && index < installmentIds.length
              ? installmentIds[index]
              : null,
          saleId: saleId,
          installmentNumber: startingInstallmentNumber + index,
          dueDate: dueDates[index],
          openingBalance: _fromCents(openingBalanceCents),
          principalAmount: _fromCents(principalCents),
          interestAmount: _fromCents(interestCents),
          totalAmount: _fromCents(totalAmountCents),
          paidAmount: 0,
          paidPrincipalAmount: 0,
          paidInterestAmount: 0,
          endingBalance: _fromCents(endingBalanceCents),
          status: 'pendiente',
          createdAt: createdAt,
          updatedAt: resolvedUpdatedAt,
        ),
      );

      balanceCents = endingBalanceCents;
    }

    return installments;
  }

  static double _calculateFixedPayment({
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    if (installmentCount <= 0 || financedBalance <= 0) {
      return 0;
    }

    final monthlyRate = monthlyInterest / 100;
    if (monthlyRate == 0) {
      return _roundCurrency(financedBalance / installmentCount);
    }

    final factor = 1 - (1 / (pow(1 + monthlyRate, installmentCount)));
    if (factor == 0) {
      return _roundCurrency(financedBalance / installmentCount);
    }

    return _roundCurrency((financedBalance * monthlyRate) / factor);
  }

  static DateTime _addMonths(DateTime date, int monthsToAdd) {
    final targetMonthIndex = date.month - 1 + monthsToAdd;
    final targetYear = date.year + (targetMonthIndex ~/ 12);
    final targetMonth = (targetMonthIndex % 12) + 1;
    final maxDay = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = date.day > maxDay ? maxDay : date.day;
    return DateTime(
      targetYear,
      targetMonth,
      targetDay,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  static double _roundCurrency(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  static int _toCents(double value) {
    return (value * 100).round();
  }

  static double _fromCents(int value) {
    return value / 100;
  }
}