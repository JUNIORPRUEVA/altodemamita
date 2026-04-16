import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/client_pagare_report.dart';
import 'package:sistema_solares/features/payments/presentation/reports/client_pagare_pdf_builder.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera PDF de lista de pagos con encabezado largo sin fallar', () async {
    final now = DateTime(2026, 3, 29);
    final report = ClientPagareReport(
      clientId: 7,
      clientName: '[TEST] Carlos Ramirez Gomez',
      clientDocumentId: '001-1234567-8',
      items: [
        ClientPagareItem(
          paymentId: 1,
          saleId: 10,
          lotDisplayCode: 'MTEST-S20',
          paymentDate: DateTime.utc(2026, 3, 19),
          amountPaid: 13910.70,
          paymentMethod: 'transferencia',
          paymentType: 'cuota',
          installmentNumber: 1,
          reference: 'TEST-10-9',
        ),
      ],
    );

    final company = CompanyInfo(
      nombre:
          'Consorcio Inmobiliario de Desarrollo de Solares y Proyectos Residenciales del Cibao',
      telefono: '809-555-0101 ext. 204 y 205',
      direccion:
          'Autopista Duarte kilometro 8 1/2, edificio corporativo norte, segundo nivel, municipio Santo Domingo Oeste, Republica Dominicana',
      logoBytesBase64: null,
      fechaCreacion: now,
      fechaActualizacion: now,
    );

    final bytes = await ClientPagarePdfBuilder.build(
      report: report,
      company: company,
    );
    final secondBytes = await ClientPagarePdfBuilder.build(
      report: report,
      company: company,
    );

    expect(bytes, isNotEmpty);
    expect(secondBytes, isNotEmpty);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(utf8.decode(secondBytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(2200));
  });
}
