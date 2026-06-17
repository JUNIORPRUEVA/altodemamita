import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/sales/domain/sale.dart';
import 'package:sistema_solares/features/sales/domain/sale_detail.dart';
import 'package:sistema_solares/features/sales/presentation/documents/sale_amortization_pdf_builder.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera PDF de amortizacion con encabezado largo sin fallar', () async {
    final now = DateTime(2026, 3, 27);
    final detail = SaleDetail(
      sale: Sale(
        id: 3,
        clientId: 1,
        lotId: 2,
        userId: 7,
        sellerId: 5,
        saleDate: now,
        salePrice: 950000,
        downPaymentPercentage: 10,
        downPaymentAmount: 95000,
        requiredInitialPayment: 95000,
        paidInitialPayment: 95000,
        pendingInitialPayment: 0,
        minimumReserveAmount: 0,
        initialPaymentDeadline: now.add(const Duration(days: 30)),
        activationDate: now,
        financedBalance: 855000,
        pendingBalance: 855000,
        monthlyInterest: 1,
        installmentCount: 18,
        status: 'activa',
        createdAt: now,
        updatedAt: now,
      ),
      clientName: 'Maria Garcia Rodriguez',
      clientDocumentId: '999-00000000002-2',
      lotDisplayCode: 'MTEST-A-S2',
      lotArea: 200,
      lotPricePerSquareMeter: 4750,
      userName: 'programador',
      initialPaymentMethod: 'transferencia',
      sellerName: 'Sofia Beltran',
      sellerDocumentId: '999-0010000002-6',
      sellerPhone: '809-666-0102',
      installments: List<Installment>.generate(18, (index) {
        final installmentNumber = index + 1;
        final openingBalance = 855000.0 - (index * 47500.0);
        final principal = installmentNumber == 18 ? 47500.0 : 47497.67;
        final interest = openingBalance * 0.01;
        final totalAmount = principal + interest;
        final paidAmount = installmentNumber == 1 ? totalAmount : 0.0;
        return Installment(
          id: installmentNumber,
          saleId: 3,
          installmentNumber: installmentNumber,
          dueDate: DateTime(2026, 4 + index, 26),
          openingBalance: openingBalance,
          principalAmount: principal,
          interestAmount: interest,
          totalAmount: totalAmount,
          paidAmount: paidAmount,
          paidPrincipalAmount: paidAmount == 0 ? 0.0 : principal,
          paidInterestAmount: paidAmount == 0 ? 0.0 : interest,
          endingBalance: (openingBalance - principal)
              .clamp(0.0, double.infinity)
              .toDouble(),
          status: paidAmount == 0 ? 'pendiente' : 'pagada',
          createdAt: now,
          updatedAt: now,
        );
      }),
    );

    final company = CompanyInfo(
      nombre:
          'Consorcio Inmobiliario de Desarrollo de Solares y Proyectos Residenciales del Cibao',
      telefono: '809-555-0101 ext. 204 y 205',
      direccion:
          'Autopista Duarte kilometro 8 1/2, edificio corporativo norte, segundo nivel, municipio Santo Domingo Oeste, Republica Dominicana',
      logoBytesBase64: base64Encode(List<int>.filled(32, 1)),
      fechaCreacion: now,
      fechaActualizacion: now,
    );

    final bytes = await SaleAmortizationPdfBuilder.build(
      detail: detail,
      company: company,
    );
    final secondBuildBytes = await SaleAmortizationPdfBuilder.build(
      detail: detail,
      company: company,
    );

    expect(bytes, isNotEmpty);
    expect(secondBuildBytes, isNotEmpty);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(utf8.decode(secondBuildBytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(2500));
  });

  test('genera PDF de amortizacion cuando el plazo activo fue reducido', () async {
    final now = DateTime(2026, 3, 27);
    final detail = SaleDetail(
      sale: Sale(
        id: 4,
        clientId: 1,
        lotId: 2,
        userId: 7,
        sellerId: 5,
        saleDate: now,
        salePrice: 950000,
        downPaymentPercentage: 10,
        downPaymentAmount: 95000,
        requiredInitialPayment: 95000,
        paidInitialPayment: 95000,
        pendingInitialPayment: 0,
        minimumReserveAmount: 0,
        initialPaymentDeadline: now.add(const Duration(days: 30)),
        activationDate: now,
        financedBalance: 855000,
        pendingBalance: 620000,
        monthlyInterest: 1,
        installmentCount: 18,
        status: 'activa',
        createdAt: now,
        updatedAt: now,
      ),
      clientName: 'Maria Garcia Rodriguez',
      clientDocumentId: '999-00000000002-2',
      lotDisplayCode: 'MTEST-A-S2',
      lotArea: 200,
      lotPricePerSquareMeter: 4750,
      userName: 'programador',
      initialPaymentMethod: 'transferencia',
      sellerName: 'Sofia Beltran',
      sellerDocumentId: '999-0010000002-6',
      sellerPhone: '809-666-0102',
      installments: List<Installment>.generate(9, (index) {
        final installmentNumber = index + 4;
        final openingBalance = 620000.0 - (index * 78000.0);
        final interest = openingBalance * 0.01;
        final totalAmount = 84200.0;
        final principal = index == 8
            ? (openingBalance + interest).clamp(0.0, totalAmount).toDouble() -
                interest
            : totalAmount - interest;
        return Installment(
          id: installmentNumber,
          saleId: 4,
          installmentNumber: installmentNumber,
          dueDate: DateTime(2026, 7 + index, 26),
          openingBalance: openingBalance,
          principalAmount: principal,
          interestAmount: interest,
          totalAmount: index == 8 ? principal + interest : totalAmount,
          paidAmount: 0.0,
          paidPrincipalAmount: 0.0,
          paidInterestAmount: 0.0,
          endingBalance: (openingBalance - principal)
              .clamp(0.0, double.infinity)
              .toDouble(),
          status: 'pendiente',
          createdAt: now,
          updatedAt: now,
        );
      }),
    );

    final company = CompanyInfo(
      nombre: 'Empresa Real RD',
      telefono: '809-555-0202',
      direccion: 'Autopista Duarte Km 10',
      logoBytesBase64: base64Encode(List<int>.filled(32, 1)),
      fechaCreacion: now,
      fechaActualizacion: now,
    );

    final bytes = await SaleAmortizationPdfBuilder.build(
      detail: detail,
      company: company,
    );

    expect(bytes, isNotEmpty);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(detail.activeInstallmentCount, 9);
    expect(detail.reducedInstallmentCount, 9);
  });
}
