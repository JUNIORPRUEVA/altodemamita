import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_summary.dart';

void main() {
  SaleSummary summary({
    int pendingInstallmentCount = 0,
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
      pendingInstallmentCount: pendingInstallmentCount,
      isFullyPaid: isFullyPaid,
    );
  }

  test('formatea cuotas pendientes con singular y plural', () {
    expect(
      summary(pendingInstallmentCount: 1).pendingInstallmentsLabel,
      '1 cuota pendiente',
    );
    expect(
      summary(pendingInstallmentCount: 117).pendingInstallmentsLabel,
      '117 cuotas pendientes',
    );
  });

  test(
    'no muestra conteo pendiente para ventas saldadas o sin obligaciones',
    () {
      expect(summary().pendingInstallmentsLabel, isNull);
      expect(
        summary(
          pendingInstallmentCount: 117,
          isFullyPaid: true,
        ).pendingInstallmentsLabel,
        isNull,
      );
    },
  );
}
