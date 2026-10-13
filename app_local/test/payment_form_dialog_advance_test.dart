import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payment_form_dialog.dart';

void main() {
  testWidgets(
    'cuotas adelantadas lets user choose count and auto-fills total',
    (tester) async {
      PaymentDraft? result;
      final now = DateTime.now();
      final sale = PaymentSaleOption(
        saleId: 1,
        clientId: 1,
        clientName: 'Cliente Prueba',
        clientDocumentId: '001-0000000-1',
        clientPhone: '8090000000',
        lotDisplayCode: 'M1-S1',
        pendingBalance: 6000,
        requiredInitialPayment: 0,
        paidInitialPayment: 0,
        pendingInitialPayment: 0,
        status: 'activa',
      );
      final installments = [
        _installment(
          id: 11,
          saleId: sale.saleId,
          number: 1,
          dueDate: now.add(const Duration(days: 30)),
          amount: 1000,
        ),
        _installment(
          id: 12,
          saleId: sale.saleId,
          number: 2,
          dueDate: now.add(const Duration(days: 60)),
          amount: 2000,
        ),
        _installment(
          id: 13,
          saleId: sale.saleId,
          number: 3,
          dueDate: now.add(const Duration(days: 90)),
          amount: 3000,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await PaymentFormDialog.show(
                      context,
                      sale: sale,
                      defaultPaymentMethod: 'efectivo',
                      actionableInstallment: installments.first,
                      installments: installments,
                    );
                  },
                  child: const Text('Abrir pago'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir pago'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Proxima cuota').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuotas adelantadas').last);
      await tester.pumpAndSettle();

      expect(find.text('Cantidad de cuotas'), findsOneWidget);
      expect(find.text('2 cuotas'), findsOneWidget);
      expect(
        find.textContaining('Total cuotas: RD\$ 3,000.00'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('advance_installment_count_field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 cuotas').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('#1, #2, #3'), findsWidgets);
      expect(
        find.textContaining('Total cuotas: RD\$ 6,000.00'),
        findsOneWidget,
      );

      await tester.tap(find.text('Aplicar pago'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.paymentTypeOverride, equals('cuotas_adelantadas'));
      expect(result!.amountPaid, equals(6000));
      expect(result!.advanceInstallmentCount, equals(3));
    },
  );

  testWidgets('cuotas adelantadas allows extra amount as direct capital', (
    tester,
  ) async {
    PaymentDraft? result;
    final now = DateTime.now();
    final sale = PaymentSaleOption(
      saleId: 1,
      clientId: 1,
      clientName: 'Cliente Prueba',
      clientDocumentId: '001-0000000-1',
      clientPhone: '8090000000',
      lotDisplayCode: 'M1-S1',
      pendingBalance: 6500,
      requiredInitialPayment: 0,
      paidInitialPayment: 0,
      pendingInitialPayment: 0,
      status: 'activa',
    );
    final installments = [
      _installment(
        id: 11,
        saleId: sale.saleId,
        number: 1,
        dueDate: now.add(const Duration(days: 30)),
        amount: 1000,
      ),
      _installment(
        id: 12,
        saleId: sale.saleId,
        number: 2,
        dueDate: now.add(const Duration(days: 60)),
        amount: 2000,
      ),
      _installment(
        id: 13,
        saleId: sale.saleId,
        number: 3,
        dueDate: now.add(const Duration(days: 90)),
        amount: 3000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await PaymentFormDialog.show(
                    context,
                    sale: sale,
                    defaultPaymentMethod: 'efectivo',
                    actionableInstallment: installments.first,
                    installments: installments,
                  );
                },
                child: const Text('Abrir pago'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proxima cuota').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuotas adelantadas').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('payment_amount_field')),
      '3500',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Capital directo'), findsOneWidget);
    expect(find.textContaining('RD\$ 500.00'), findsWidgets);

    await tester.tap(find.text('Aplicar pago'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paymentTypeOverride, equals('cuotas_adelantadas'));
    expect(result!.amountPaid, equals(3500));
    expect(result!.advanceInstallmentCount, equals(2));
  });
}

Installment _installment({
  required int id,
  required int saleId,
  required int number,
  required DateTime dueDate,
  required double amount,
}) {
  final now = DateTime.now();
  return Installment(
    id: id,
    saleId: saleId,
    installmentNumber: number,
    dueDate: dueDate,
    openingBalance: amount,
    principalAmount: amount,
    interestAmount: 0,
    totalAmount: amount,
    paidAmount: 0,
    paidPrincipalAmount: 0,
    paidInterestAmount: 0,
    endingBalance: 0,
    status: 'pendiente',
    createdAt: now,
    updatedAt: now,
  );
}
