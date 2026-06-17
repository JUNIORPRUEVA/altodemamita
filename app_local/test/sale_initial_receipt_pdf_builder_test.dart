import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/sales/domain/sale.dart';
import 'package:sistema_solares/features/sales/domain/sale_detail.dart';
import 'package:sistema_solares/features/sales/presentation/documents/sale_initial_receipt_pdf_builder.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera recibo de venta profesional con inicial pendiente', () async {
    final now = DateTime(2026, 5, 6);
    final detail = SaleDetail(
      sale: Sale(
        id: 21,
        clientId: 1,
        lotId: 2,
        userId: 7,
        sellerId: 5,
        saleDate: now,
        salePrice: 1200000,
        downPaymentPercentage: 10,
        downPaymentAmount: 120000,
        requiredInitialPayment: 120000,
        paidInitialPayment: 25000,
        pendingInitialPayment: 95000,
        minimumReserveAmount: 25000,
        initialPaymentDeadline: now.add(const Duration(days: 30)),
        activationDate: null,
        financedBalance: 1080000,
        pendingBalance: 1080000,
        monthlyInterest: 1.25,
        installmentCount: 36,
        status: 'inicial_incompleto',
        createdAt: now,
        updatedAt: now,
      ),
      clientName: 'Juan Pérez Núñez',
      clientDocumentId: '001-1234567-8',
      lotDisplayCode: 'M-A / Solar 14',
      lotArea: 250,
      lotPricePerSquareMeter: 4800,
      userName: 'Admin Local',
      initialPaymentMethod: 'transferencia',
      sellerName: 'María García',
      sellerDocumentId: '002-7654321-0',
      sellerPhone: '809-555-0199',
      installments: [
        Installment(
          id: 1,
          saleId: 21,
          installmentNumber: 1,
          dueDate: DateTime(2026, 6, 6),
          openingBalance: 1080000,
          principalAmount: 30000,
          interestAmount: 13500,
          totalAmount: 43500,
          paidAmount: 0,
          paidPrincipalAmount: 0,
          paidInterestAmount: 0,
          endingBalance: 1050000,
          status: 'pendiente',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    final bytes = await SaleInitialReceiptPdfBuilder.build(
      detail: detail,
      company: _company(now),
      pageFormat: PdfPageFormat.letter.landscape,
    );

    expect(bytes, isNotEmpty);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(2500));
  });
}

CompanyInfo _company(DateTime now) {
  return CompanyInfo(
    nombre: 'Sistema Solares Financiera RD',
    telefono: '809-555-0101',
    direccion: 'Santo Domingo, República Dominicana',
    logoBytesBase64: null,
    fechaCreacion: now,
    fechaActualizacion: now,
  );
}
