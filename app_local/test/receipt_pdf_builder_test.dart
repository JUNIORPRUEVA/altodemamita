import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/payments/domain/payment_history_item.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_context.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/data/receipt_repository.dart';
import 'package:sistema_solares/features/payments/domain/receipt.dart';
import 'package:sistema_solares/features/payments/presentation/receipt/receipt_pdf_builder.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera PDF de recibo con encabezado largo sin fallar', () async {
    final receipt = _buildSampleReceipt();

    final bytes = await ReceiptPdfBuilder.build(receipt);
    final secondBytes = await ReceiptPdfBuilder.build(receipt);

    expect(bytes, isNotEmpty);
    expect(secondBytes, isNotEmpty);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(utf8.decode(secondBytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(2500));
  });

  test('genera recibo desde contexto cloud sin fila local de pago', () async {
    final paymentDate = DateTime(2026, 6, 2, 10, 30);
    final payment = PaymentHistoryItem(
      id: 730257513,
      saleId: 162493397,
      clientId: 0,
      paymentDate: paymentDate,
      amountPaid: 92762.40,
      paymentMethod: 'efectivo',
      paymentType: 'abono_inicial',
      reference: 'cloud-payment-1',
    );
    final context = PaymentSaleContext(
      sale: const PaymentSaleOption(
        saleId: 162493397,
        clientId: 1,
        clientName: 'CLARA MARIA BAEZ ALVAREZ',
        clientDocumentId: '028-0076241-7',
        clientPhone: '',
        lotDisplayCode: 'MM-H-S84',
        pendingBalance: 834861.60,
        requiredInitialPayment: 92762.40,
        paidInitialPayment: 92762.40,
        pendingInitialPayment: 0,
        status: 'activa',
      ),
      monthlyInterest: 1,
      installments: const [],
      history: [payment],
    );

    final receipt = await ReceiptRepository().buildReceiptFromContext(
      context: context,
      payment: payment,
    );
    final bytes = await ReceiptPdfBuilder.build(receipt);

    expect(receipt.paymentId, 730257513);
    expect(receipt.sale.clientName, contains('CLARA'));
    expect(receipt.totalAmount, closeTo(92762.40, 0.001));
    expect(bytes, isNotEmpty);
  });

  test(
    'resuelve recibo inmediato desde contexto confirmado sin fila local',
    () async {
      final paymentDate = DateTime(2026, 6, 2, 10, 30);
      final payment = PaymentHistoryItem(
        id: 730257513,
        saleId: 162493397,
        clientId: 0,
        paymentDate: paymentDate,
        amountPaid: 92762.40,
        paymentMethod: 'efectivo',
        paymentType: 'abono_inicial',
        reference: 'cloud-payment-1',
      );
      final context = _buildCloudContext(payment);
      final repository = _FakeReceiptRepository(localReceipt: null);

      final receipt = await repository.resolveReceiptForPayment(
        paymentId: payment.id,
        context: context,
        payment: payment,
        origin: 'test-immediate-payment',
      );

      expect(receipt, isNotNull);
      expect(receipt!.paymentId, payment.id);
      expect(repository.fetchCalls, 1);
      expect(repository.contextBuildCalls, 1);
    },
  );

  test('no convierte paymentId inexistente en exito sin evidencia', () async {
    final repository = _FakeReceiptRepository(localReceipt: null);

    final receipt = await repository.resolveReceiptForPayment(
      paymentId: 999999,
      origin: 'test-missing-payment',
    );

    expect(receipt, isNull);
    expect(repository.fetchCalls, 1);
    expect(repository.contextBuildCalls, 0);
  });

  test(
    'un fallo permanente al buscar recibo se propaga sin contexto confirmado',
    () async {
      final repository = _FakeReceiptRepository(
        fetchError: StateError('payment fetch failed'),
      );

      await expectLater(
        repository.resolveReceiptForPayment(
          paymentId: 999999,
          origin: 'test-permanent-failure',
        ),
        throwsA(isA<StateError>()),
      );

      expect(repository.contextBuildCalls, 0);
    },
  );
}

PaymentSaleContext _buildCloudContext(PaymentHistoryItem payment) {
  return PaymentSaleContext(
    sale: const PaymentSaleOption(
      saleId: 162493397,
      clientId: 1,
      clientName: 'CLARA MARIA BAEZ ALVAREZ',
      clientDocumentId: '028-0076241-7',
      clientPhone: '',
      lotDisplayCode: 'MM-H-S84',
      pendingBalance: 834861.60,
      requiredInitialPayment: 92762.40,
      paidInitialPayment: 92762.40,
      pendingInitialPayment: 0,
      status: 'activa',
    ),
    monthlyInterest: 1,
    installments: const [],
    history: [payment],
  );
}

class _FakeReceiptRepository extends ReceiptRepository {
  _FakeReceiptRepository({this.localReceipt, this.fetchError});

  final Receipt? localReceipt;
  final Object? fetchError;
  int fetchCalls = 0;
  int contextBuildCalls = 0;

  @override
  Future<Receipt?> fetchReceiptByPaymentId(int paymentId) async {
    fetchCalls++;
    final error = fetchError;
    if (error != null) {
      throw error;
    }
    return localReceipt;
  }

  @override
  Future<Receipt> buildReceiptFromContext({
    required PaymentSaleContext context,
    required PaymentHistoryItem payment,
  }) async {
    contextBuildCalls++;
    return Receipt(
      paymentId: payment.id,
      receiptNumber: 'TEST-${payment.id}',
      paymentDate: payment.paymentDate,
      sale: context.sale,
      payment: payment,
      payments: [payment],
      company: CompanyInfo(
        nombre: 'Sistema de Solares',
        telefono: null,
        direccion: null,
        logoBytesBase64: null,
        fechaCreacion: payment.paymentDate,
        fechaActualizacion: payment.paymentDate,
      ),
      paidInstallment: null,
      installmentsPaid: 0,
      installmentsRemaining: context.installments.length,
      totalPaidAccumulated: payment.amountPaid,
      accountStatusLabel: 'Al dia',
      blockNumber: 'MM',
      lotNumber: 'S84',
      installmentCount: context.installments.length,
      userName: '',
      conditionsOfPayment: 'Pago confirmado.',
      note: 'Recibo de prueba.',
    );
  }
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
      nombre:
          'Consorcio Inmobiliario de Desarrollo de Solares y Proyectos Residenciales del Cibao',
      telefono: '809-555-0101 ext. 204 y 205',
      direccion:
          'Autopista Duarte kilometro 8 1/2, edificio corporativo norte, segundo nivel, municipio Santo Domingo Oeste, Republica Dominicana',
      logoBytesBase64: null,
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
