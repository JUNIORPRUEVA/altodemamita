import '../../installments/domain/installment.dart';

class SaleScheduleEntry {
  const SaleScheduleEntry({
    required this.capitalPayment,
    required this.interestPayment,
    required this.totalPayment,
  });

  final double capitalPayment;
  final double interestPayment;
  final double totalPayment;
}

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
    if (installmentCount <= 0 || financedBalance <= 0) {
      return 0;
    }

    return calculateTotalFinancingAmount(
          financedBalance: financedBalance,
          monthlyInterest: monthlyInterest,
          installmentCount: installmentCount,
        ) /
        installmentCount;
  }

  static double calculateFixedMonthlyInterestAmount({
    required double financedBalance,
    required double monthlyInterest,
  }) {
    if (financedBalance <= 0 || monthlyInterest <= 0) {
      return 0;
    }

    return _roundCurrency(financedBalance * (monthlyInterest / 100));
  }

  static double calculateTotalInterestAmount({
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    if (installmentCount <= 0 || financedBalance <= 0) {
      return 0;
    }

    final monthlyInterestAmount = calculateFixedMonthlyInterestAmount(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
    );
    return _roundCurrency(monthlyInterestAmount * installmentCount);
  }

  static double calculateTotalFinancingAmount({
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    if (financedBalance <= 0) {
      return 0;
    }

    return _roundCurrency(
      financedBalance +
          calculateTotalInterestAmount(
            financedBalance: financedBalance,
            monthlyInterest: monthlyInterest,
            installmentCount: installmentCount,
          ),
    );
  }

  static List<SaleScheduleEntry> generateSchedule({
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    if (installmentCount <= 0 || financedBalance <= 0) {
      return const [];
    }

    final installments = buildInstallmentSchedule(
      saleId: 0,
      saleDate: DateTime(2000, 1, 1),
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
      createdAt: DateTime(2000, 1, 1),
    );

    return installments
        .map(
          (installment) => SaleScheduleEntry(
            capitalPayment: installment.principalAmount,
            interestPayment: installment.interestAmount,
            totalPayment: installment.totalAmount,
          ),
        )
        .toList(growable: false);
  }

  static List<Installment> buildInstallmentSchedule({
    required int saleId,
    required DateTime saleDate,
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
    required DateTime createdAt,
    DateTime? statusAsOf,
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
      statusAsOf: statusAsOf,
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
    DateTime? statusAsOf,
  }) {
    if (dueDates.isEmpty || financedBalance <= 0) {
      return const [];
    }

    final principalCents = _toCents(financedBalance);
    final fixedInterestCents = _toCents(
      calculateFixedMonthlyInterestAmount(
        financedBalance: financedBalance,
        monthlyInterest: monthlyInterest,
      ),
    );
    final totalPlanCents = _toCents(
      calculateTotalFinancingAmount(
        financedBalance: financedBalance,
        monthlyInterest: monthlyInterest,
        installmentCount: dueDates.length,
      ),
    );
    final fixedPaymentCents = _toCents(
      calculateEstimatedInstallmentAmount(
        financedBalance: financedBalance,
        monthlyInterest: monthlyInterest,
        installmentCount: dueDates.length,
      ),
    );
    var remainingPrincipalCents = principalCents;
    var remainingPlanCents = totalPlanCents;
    final installments = <Installment>[];
    final resolvedUpdatedAt = updatedAt ?? createdAt;
    final resolvedStatusAsOf = statusAsOf ?? DateTime.now();

    for (var index = 0; index < dueDates.length; index++) {
      final openingBalanceCents = remainingPrincipalCents;
      if (openingBalanceCents <= 0 || remainingPlanCents <= 0) {
        break;
      }

      final isLastInstallment = index == dueDates.length - 1;
      var totalAmountCents = isLastInstallment
          ? remainingPlanCents
          : fixedPaymentCents;
      if (totalAmountCents > remainingPlanCents) {
        totalAmountCents = remainingPlanCents;
      }

      var interestCents = fixedInterestCents;
      var principalCentsForInstallment = totalAmountCents - interestCents;

      if (principalCentsForInstallment < 0) {
        principalCentsForInstallment = 0;
        interestCents = totalAmountCents;
      }

      if (principalCentsForInstallment >= openingBalanceCents ||
          isLastInstallment) {
        principalCentsForInstallment = openingBalanceCents;
        interestCents = totalAmountCents - principalCentsForInstallment;
        if (interestCents < 0) {
          interestCents = 0;
          totalAmountCents = principalCentsForInstallment;
        }
      }

      final endingBalanceCents =
          (openingBalanceCents - principalCentsForInstallment).clamp(
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
          principalAmount: _fromCents(principalCentsForInstallment),
          interestAmount: _fromCents(interestCents),
          totalAmount: _fromCents(totalAmountCents),
          paidAmount: 0,
          paidPrincipalAmount: 0,
          paidInterestAmount: 0,
          endingBalance: _fromCents(endingBalanceCents),
          status: resolveInstallmentStatus(
            dueDate: dueDates[index],
            paidAmount: 0,
            totalAmount: _fromCents(totalAmountCents),
            asOf: resolvedStatusAsOf,
          ),
          createdAt: createdAt,
          updatedAt: resolvedUpdatedAt,
        ),
      );

      remainingPrincipalCents = endingBalanceCents;
      remainingPlanCents = (remainingPlanCents - totalAmountCents).clamp(
        0,
        remainingPlanCents,
      );
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
    DateTime? statusAsOf,
  }) {
    if (dueDates.isEmpty || financedBalance <= 0 || fixedPaymentAmount <= 0) {
      return const [];
    }

    final fixedInterestCents = _toCents(
      calculateFixedMonthlyInterestAmount(
        financedBalance: financedBalance,
        monthlyInterest: monthlyInterest,
      ),
    );
    final fixedPaymentCents = _toCents(fixedPaymentAmount);
    var balanceCents = _toCents(financedBalance);
    final installments = <Installment>[];
    final resolvedUpdatedAt = updatedAt ?? createdAt;
    final resolvedStatusAsOf = statusAsOf ?? DateTime.now();

    for (var index = 0; index < dueDates.length; index++) {
      final openingBalanceCents = balanceCents;
      if (openingBalanceCents <= 0) {
        break;
      }

      var interestCents = fixedInterestCents;
      var totalAmountCents = fixedPaymentCents;
      var principalCents = totalAmountCents - interestCents;

      if (principalCents < 0) {
        principalCents = 0;
        interestCents = totalAmountCents;
      }

      final payoffAmountCents = openingBalanceCents + interestCents;
      if (payoffAmountCents <= fixedPaymentCents ||
          principalCents >= openingBalanceCents) {
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
          status: resolveInstallmentStatus(
            dueDate: dueDates[index],
            paidAmount: 0,
            totalAmount: _fromCents(totalAmountCents),
            asOf: resolvedStatusAsOf,
          ),
          createdAt: createdAt,
          updatedAt: resolvedUpdatedAt,
        ),
      );

      balanceCents = endingBalanceCents;
    }

    return installments;
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

  static String resolveInstallmentStatus({
    required DateTime dueDate,
    required double paidAmount,
    required double totalAmount,
    required DateTime asOf,
  }) {
    if (paidAmount >= totalAmount - 0.009) {
      return 'pagada';
    }
    if (paidAmount > 0.009) {
      return 'parcial';
    }
    return isPastDue(dueDate: dueDate, asOf: asOf) ? 'vencida' : 'pendiente';
  }

  static bool isPastDue({required DateTime dueDate, required DateTime asOf}) {
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    return dueDay.isBefore(today);
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
