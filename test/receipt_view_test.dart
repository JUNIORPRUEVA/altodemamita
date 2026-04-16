import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/payments/domain/payment_history_item.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/domain/receipt.dart';
import 'package:sistema_solares/features/payments/presentation/receipt/receipt_view.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';

void main() {
  testWidgets('renderiza la vista previa del recibo sin errores de layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final receipt = _buildSampleReceipt();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: ReceiptView.documentWidth,
              height: ReceiptView.documentHeight,
              child: ReceiptView(receipt: receipt),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COMPROBANTE DE PAGO'), findsOneWidget);
    expect(find.text('VALIDACION Y ARCHIVO'), findsOneWidget);
    expect(find.text('Tel. 809-555-0101'), findsOneWidget);
    expect(find.text('RESUMEN FINANCIERO'), findsOneWidget);
    expect(find.text('BALANCE ACTUAL'), findsOneWidget);
    expect(find.text('ABONADO ACUMULADO'), findsOneWidget);
    expect(find.text('ESTADO ACTUAL'), findsOneWidget);
    expect(find.text('Proxima cuota'), findsOneWidget);
    expect(find.text('[TEST] Usuario Cajero'), findsWidgets);
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ajusta el recibo en un viewport reducido sin romper el espacio',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final receipt = _buildSampleReceipt();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1060,
                height: 620,
                child: ReceiptView(receipt: receipt),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DETALLE Y RESUMEN'), findsOneWidget);
      expect(find.text('VALIDACION Y ARCHIVO'), findsOneWidget);
      expect(find.text('No aceptamos devoluciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Receipt _buildSampleReceipt() {
  final now = DateTime(2026, 3, 28, 14, 45);

  return Receipt(
    paymentId: 101,
    receiptNumber: 'RC-000101',
    paymentDate: now,
    sale: const PaymentSaleOption(
      saleId: 10,
      clientId: 50,
      clientName: '[TEST] Carlos Ramirez Gomez',
      clientDocumentId: '001-1234567-8',
      clientPhone: '8095550101',
      lotDisplayCode: 'MA-S10',
      pendingBalance: 250000,
      requiredInitialPayment: 100000,
      paidInitialPayment: 75000,
      pendingInitialPayment: 25000,
      status: 'activa',
    ),
    payment: PaymentHistoryItem(
      id: 101,
      saleId: 10,
      clientId: 50,
      installmentId: 1,
      paymentDate: now,
      amountPaid: 18500,
      paymentMethod: 'transferencia',
      paymentType: 'cuota',
      reference: 'TRX-12345',
      installmentNumber: 1,
    ),
    payments: [
      PaymentHistoryItem(
        id: 101,
        saleId: 10,
        clientId: 50,
        installmentId: 1,
        paymentDate: now,
        amountPaid: 15000,
        paymentMethod: 'transferencia',
        paymentType: 'cuota',
        reference: 'TRX-12345',
        installmentNumber: 1,
      ),
      PaymentHistoryItem(
        id: 102,
        saleId: 10,
        clientId: 50,
        installmentId: null,
        paymentDate: now,
        amountPaid: 3500,
        paymentMethod: 'transferencia',
        paymentType: 'abono_capital',
        reference: 'TRX-12345',
        installmentNumber: null,
      ),
    ],
    company: CompanyInfo(
      nombre: 'Sistema de Solares',
      telefono: '809-555-0101',
      direccion: 'Av. Principal, Santo Domingo',
      logoBytesBase64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2foAAAAASUVORK5CYII=',
      fechaCreacion: now,
      fechaActualizacion: now,
    ),
    paidInstallment: Installment(
      id: 1,
      saleId: 10,
      installmentNumber: 1,
      dueDate: DateTime(2026, 4, 28),
      openingBalance: 250000,
      principalAmount: 12000,
      interestAmount: 3000,
      totalAmount: 15000,
      paidAmount: 15000,
      paidPrincipalAmount: 12000,
      paidInterestAmount: 3000,
      endingBalance: 238000,
      status: 'pagada',
      createdAt: now,
      updatedAt: now,
    ),
    paidCapitalAmount: 3500,
    installmentsPaid: 1,
    installmentsRemaining: 11,
    totalPaidAccumulated: 18500,
    accountStatusLabel: 'Al dia',
    nextInstallmentNumber: 2,
    nextInstallmentDueDate: DateTime(2026, 5, 28),
    nextInstallmentAmount: 15000,
    monthlyInterest: 1.2,
    blockNumber: 'A',
    lotNumber: '10',
    installmentCount: 12,
    userName: '[TEST] Javier Reyes',
    paymentRegisteredByName: '[TEST] Usuario Cajero',
    sellerName: '[TEST] Javier Reyes',
    conditionsOfPayment: 'Pago mensual dentro de los primeros cinco dias.',
    note: 'Cliente al dia con observacion interna de prueba.',
  );
}
