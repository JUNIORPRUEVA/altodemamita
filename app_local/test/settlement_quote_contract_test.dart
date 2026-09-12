import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/settlement_quote.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';

void main() {
  test('settlement quote parses server financial fields', () {
    final quote = SettlementQuote.fromMap({
      'saleId': 'sale-1',
      'asOfDate': '2026-09-12T10:00:00.000Z',
      'principalOutstanding': '24000.50',
      'dueInterest': 1500,
      'lateFees': 0,
      'futureInterestWaived': '700.25',
      'settlementAmount': '25500.50',
      'quoteVersion': 'quote-v1',
    });

    expect(quote.saleId, 'sale-1');
    expect(quote.principalOutstanding, 24000.50);
    expect(quote.dueInterest, 1500);
    expect(quote.lateFees, 0);
    expect(quote.futureInterestWaived, 700.25);
    expect(quote.settlementAmount, 25500.50);
    expect(quote.quoteVersion, 'quote-v1');
  });

  test('cash sale draft carries explicit sale type and zero installments', () {
    final draft = SaleDraft(
      clientId: 1,
      lotId: 2,
      userId: 3,
      saleDate: DateTime(2026, 9, 12),
      salePrice: 600000,
      downPaymentPercentage: 100,
      requiredInitialPayment: 600000,
      initialPaymentPaid: 600000,
      saleType: 'CASH',
      monthlyInterest: 0,
      installmentCount: 0,
      status: 'pagada',
    );

    expect(draft.saleType, 'CASH');
    expect(draft.installmentCount, 0);
    expect(draft.pendingInitialPayment, 0);
  });
}
