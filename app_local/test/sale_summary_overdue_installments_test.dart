import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
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

  test('deriva cuotas vencidas desde item backend con cuotas embebidas', () {
    final count = overdueInstallmentCountFromBackendItem(
      {
        'installments': [
          {
            'dueDate': '2026-09-11T00:00:00.000Z',
            'status': 'pendiente',
            'totalAmount': '1000',
            'paidAmount': '0',
          },
          {
            'dueDate': '2026-09-12T00:00:00.000Z',
            'status': 'parcial',
            'totalAmount': '1000',
            'paidAmount': '250',
          },
          {
            'dueDate': '2026-09-13T00:00:00.000Z',
            'status': 'pending',
            'amount': '1000',
            'paidAmount': '0',
          },
          {
            'dueDate': '2026-09-10T00:00:00.000Z',
            'status': 'pagada',
            'totalAmount': '1000',
            'paidAmount': '1000',
          },
          {
            'dueDate': '2026-09-10T00:00:00.000Z',
            'status': 'cancelada',
            'totalAmount': '1000',
            'paidAmount': '0',
          },
          {
            'dueDate': '2026-10-13T00:00:00.000Z',
            'status': 'pendiente',
            'totalAmount': '1000',
            'paidAmount': '0',
          },
        ],
      },
      now: DateTime(2026, 9, 14, 12),
    );

    expect(count, 3);
  });
}
