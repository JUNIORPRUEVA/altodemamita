import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_summary.dart';

void main() {
  SaleSummary summary({
    int overdueInstallmentCount = 0,
    bool isFullyPaid = false,
  }) {
    return SaleSummary(
      id: 1,
      syncStatus: 'synced',
      clientName: 'THELEMARQUE WISMIQUE',
      clientDocumentId: '001-0000000-1',
      lotDisplayCode: 'MM-B-1-S446',
      saleDate: DateTime(2026, 3, 6),
      salePrice: 750000,
      downPaymentAmount: 75000,
      requiredInitialPayment: 75000,
      paidInitialPayment: 75000,
      pendingInitialPayment: 0,
      financedBalance: 675000,
      pendingBalance: 675000,
      monthlyInterest: 1,
      installmentCount: 120,
      status: 'activa',
      generatedInstallments: 120,
      overdueInstallmentCount: overdueInstallmentCount,
      isFullyPaid: isFullyPaid,
    );
  }

  test('formatea cuotas vencidas con singular y plural', () {
    expect(
      summary(overdueInstallmentCount: 1).overdueInstallmentsLabel,
      '1 cuota vencida',
    );
    expect(
      summary(overdueInstallmentCount: 2).overdueInstallmentsLabel,
      '2 cuotas vencidas',
    );
  });

  test('no muestra conteo vencido para ventas saldadas o sin vencidas', () {
    expect(summary().overdueInstallmentsLabel, isNull);
    expect(
      summary(
        overdueInstallmentCount: 2,
        isFullyPaid: true,
      ).overdueInstallmentsLabel,
      isNull,
    );
  });
}
