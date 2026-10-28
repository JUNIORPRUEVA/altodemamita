import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/payments/domain/authoritative_late_fee.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payment_form_dialog.dart';

PaymentSaleOption _sale() {
  return PaymentSaleOption(
    saleId: 1,
    clientId: 1,
    clientName: 'Cliente Prueba',
    clientDocumentId: '001-0000000-1',
    clientPhone: '8090000000',
    lotDisplayCode: 'M1-S1',
    pendingBalance: 1000,
    requiredInitialPayment: 0,
    paidInitialPayment: 0,
    pendingInitialPayment: 0,
    status: 'activa',
  );
}

Installment _overdueInstallment() {
  final now = DateTime.now();
  return Installment(
    id: 11,
    saleId: 1,
    installmentNumber: 3,
    dueDate: now.subtract(const Duration(days: 30)),
    openingBalance: 1000,
    principalAmount: 1000,
    interestAmount: 0,
    totalAmount: 1000,
    paidAmount: 0,
    paidPrincipalAmount: 0,
    paidInterestAmount: 0,
    endingBalance: 0,
    status: 'vencida',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _openDialog(
  WidgetTester tester, {
  AuthoritativeLateFeeSummary? authoritativeLateFees,
}) async {
  final installment = _overdueInstallment();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await PaymentFormDialog.show(
                  context,
                  sale: _sale(),
                  defaultPaymentMethod: 'efectivo',
                  actionableInstallment: installment,
                  installments: [installment],
                  overdueInstallments: [installment],
                  authoritativeLateFees: authoritativeLateFees,
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
  await tester.enterText(
    find.byKey(const Key('payment_amount_field')),
    '1000',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'sin mora autoritativa el dialogo muestra el calculo local',
    (tester) async {
      await _openDialog(tester);

      expect(find.text('Mora calculada:'), findsOneWidget);
      expect(find.text('Mora cobrable:'), findsNothing);
      expect(find.text('Mora condonada:'), findsNothing);
      // 30 dias de atraso - 5 de gracia = 25 dias x 0.5% sobre RD$1,000.
      expect(find.textContaining('RD\$ 125.00'), findsWidgets);
    },
  );

  testWidgets(
    'con mora autoritativa condonada no se muestra como cobrable',
    (tester) async {
      final summary = AuthoritativeLateFeeSummary.fromMap({
        'saleId': 'sale-remote-1',
        'grossLateFees': 125,
        'collectedLateFees': 0,
        'waivedLateFees': 125,
        'outstandingLateFees': 0,
        'installments': [
          {
            'installmentSyncId': 'inst-3',
            'installmentNumber': 3,
            'grossLateFee': 125,
            'waivedLateFee': 125,
            'collectedLateFee': 0,
            'outstandingLateFee': 0,
          },
        ],
      });

      await _openDialog(tester, authoritativeLateFees: summary);

      expect(find.text('Mora cobrable:'), findsOneWidget);
      expect(find.text('Mora calculada:'), findsNothing);
      expect(find.text('Mora condonada:'), findsOneWidget);
      expect(find.textContaining('RD\$ 125.00'), findsWidgets);
      expect(find.textContaining('RD\$ 0.00'), findsWidgets);
      // El total recomendado no incluye la mora condonada.
      expect(find.textContaining('RD\$ 1,000.00'), findsWidgets);
    },
  );

  testWidgets(
    'con mora autoritativa exigible se usa el monto del backend',
    (tester) async {
      final summary = AuthoritativeLateFeeSummary.fromMap({
        'saleId': 'sale-remote-1',
        'grossLateFees': 125,
        'waivedLateFees': 100,
        'outstandingLateFees': 25,
        'installments': [
          {
            'installmentNumber': 3,
            'grossLateFee': 125,
            'waivedLateFee': 100,
            'outstandingLateFee': 25,
          },
        ],
      });

      await _openDialog(tester, authoritativeLateFees: summary);

      expect(find.text('Mora cobrable:'), findsOneWidget);
      expect(find.textContaining('RD\$ 25.00'), findsWidgets);
      expect(find.text('Mora condonada:'), findsOneWidget);
      // Total recomendado = cuota 1,000 + mora exigible 25.
      expect(find.textContaining('RD\$ 1,025.00'), findsWidgets);
    },
  );
}
