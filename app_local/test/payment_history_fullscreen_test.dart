import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/client_pagare_report.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payment_history_fullscreen.dart';

void main() {
  testWidgets('renderiza el historial completo de pagos sin errores', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sale = PaymentSaleOption(
      saleId: 15,
      clientId: 7,
      clientName: '[TEST] Carlos Ramirez Gomez',
      clientDocumentId: '001-1234567-8',
      clientPhone: '8095550101',
      lotDisplayCode: 'MA-S10',
      pendingBalance: 215000,
      requiredInitialPayment: 100000,
      paidInitialPayment: 100000,
      pendingInitialPayment: 0,
      status: 'activa',
    );

    final report = ClientPagareReport(
      clientId: 7,
      clientName: sale.clientName,
      clientDocumentId: sale.clientDocumentId,
      items: [
        ClientPagareItem(
          paymentId: 1,
          saleId: sale.saleId,
          lotDisplayCode: sale.lotDisplayCode,
          paymentDate: DateTime(2026, 3, 29),
          amountPaid: 15000,
          paymentMethod: 'transferencia',
          paymentType: 'cuota',
          installmentNumber: 1,
          reference: 'TRX-001',
        ),
        ClientPagareItem(
          paymentId: 2,
          saleId: sale.saleId,
          lotDisplayCode: sale.lotDisplayCode,
          paymentDate: DateTime(2026, 3, 30),
          amountPaid: 5000,
          paymentMethod: 'efectivo',
          paymentType: 'abono_capital',
          reference: 'CAJA-002',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => openClientPaymentHistoryFullscreen(
                    context,
                    sale: sale,
                    report: report,
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Historial de pagos'), findsOneWidget);
    expect(find.textContaining('Total pagado'), findsOneWidget);
    expect(find.text('Pago de cuota #1'), findsOneWidget);
    expect(find.text('Abono a capital'), findsOneWidget);
    expect(find.textContaining('Restante por pagar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}