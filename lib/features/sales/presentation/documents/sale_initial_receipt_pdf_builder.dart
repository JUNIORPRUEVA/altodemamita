import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../shared/pdf/financial_pdf_theme.dart';
import '../../../settings/domain/company_info.dart';
import '../../domain/sale_detail.dart';

class SaleInitialReceiptPdfBuilder {
  /// El recibo de venta siempre se imprime en carta horizontal.
  static PdfPageFormat get pageFormat => PdfPageFormat.letter.landscape;

  static Future<Uint8List> build({
    required SaleDetail detail,
    required CompanyInfo company,
    PdfPageFormat? pageFormat,
  }) async {
    final format = pageFormat ?? SaleInitialReceiptPdfBuilder.pageFormat;
    final fonts = await FinancialPdfTheme.loadFonts();
    final logo = FinancialPdfTheme.decodeLogo(company.logoBytesBase64);
    final doc = pw.Document(theme: fonts.theme);

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.fromLTRB(
          format.width > format.height ? 22 : 18,
          18,
          format.width > format.height ? 22 : 18,
          20,
        ),
        build: (_) => _buildPage(detail, company, logo),
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildPage(
    SaleDetail detail,
    CompanyInfo company,
    pw.MemoryImage? logo,
  ) {
    final sale = detail.sale;
    final firstInstallment = detail.installments.isEmpty
        ? null
        : detail.installments.first;
    final estimatedInstallment =
        firstInstallment?.totalAmount ??
        (sale.installmentCount > 0
            ? sale.financedBalance / sale.installmentCount
            : 0.0);
    final initialStatus = _initialStatusLabel(sale);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        FinancialPdfTheme.documentHeader(
          companyName: company.nombre.trim().isEmpty
              ? 'Sistema de Solares'
              : company.nombre.trim(),
          phone: company.telefono,
          address: company.direccion,
          logo: logo,
          documentTitle: 'Recibo de venta',
          subtitle: 'Documento de operación y condiciones financieras',
          metaItems: [
            PdfMetaItem('Venta', '#${sale.id ?? 0}'),
            PdfMetaItem('Fecha', FinancialPdfTheme.shortDate(sale.saleDate)),
            PdfMetaItem('Estado', initialStatus, emphasis: true),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 58,
                child: pw.Column(
                  children: [
                    FinancialPdfTheme.card(
                      title: 'Cliente, solar y vendedor',
                      child: FinancialPdfTheme.fieldGrid([
                        PdfField(
                          'Cliente',
                          FinancialPdfTheme.dash(detail.clientName),
                        ),
                        PdfField(
                          'Cédula',
                          FinancialPdfTheme.dash(detail.clientDocumentId),
                        ),
                        PdfField(
                          'Solar',
                          FinancialPdfTheme.dash(detail.lotDisplayCode),
                        ),
                        PdfField(
                          'Área del solar',
                          '${detail.lotArea.toStringAsFixed(2)} m²',
                        ),
                        PdfField(
                          'Precio por m²',
                          FinancialPdfTheme.money(
                            detail.lotPricePerSquareMeter,
                          ),
                        ),
                        PdfField(
                          'Vendedor',
                          FinancialPdfTheme.dash(detail.sellerName),
                        ),
                        PdfField(
                          'Cédula vendedor',
                          FinancialPdfTheme.dash(detail.sellerDocumentId),
                        ),
                        PdfField(
                          'Teléfono vendedor',
                          FinancialPdfTheme.dash(detail.sellerPhone),
                        ),
                        PdfField(
                          'Registrado por',
                          FinancialPdfTheme.dash(detail.userName),
                        ),
                      ], columns: 3),
                    ),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: FinancialPdfTheme.card(
                        title: 'Condiciones de venta',
                        child: FinancialPdfTheme.fieldGrid([
                          PdfField(
                            'Precio total',
                            FinancialPdfTheme.money(sale.salePrice),
                            emphasis: true,
                          ),
                          PdfField(
                            'Inicial requerida',
                            FinancialPdfTheme.money(
                              sale.requiredInitialPayment,
                            ),
                          ),
                          PdfField(
                            'Estado del inicial',
                            initialStatus,
                            emphasis: true,
                          ),
                          PdfField(
                            'Interés mensual',
                            '${sale.monthlyInterest.toStringAsFixed(2)}%',
                          ),
                          PdfField(
                            'Cantidad de cuotas',
                            '${sale.installmentCount}',
                          ),
                          PdfField(
                            'Cuota estimada',
                            FinancialPdfTheme.money(estimatedInstallment),
                            emphasis: true,
                          ),
                          PdfField(
                            'Fecha de venta',
                            FinancialPdfTheme.shortDate(sale.saleDate),
                          ),
                          PdfField(
                            'Fecha límite inicial',
                            sale.initialPaymentDeadline == null
                                ? '-'
                                : FinancialPdfTheme.shortDate(
                                    sale.initialPaymentDeadline!,
                                  ),
                          ),
                          PdfField(
                            'Método primer pago',
                            _paymentMethod(detail.initialPaymentMethod),
                          ),
                        ], columns: 3),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 42,
                child: pw.Column(
                  children: [
                    FinancialPdfTheme.card(
                      title: 'Resumen financiero',
                      child: FinancialPdfTheme.fieldGrid([
                        PdfField(
                          _initialAmountLabel(sale),
                          FinancialPdfTheme.money(_initialAmountValue(sale)),
                          emphasis: true,
                        ),
                        PdfField(
                          'Inicial pendiente',
                          FinancialPdfTheme.money(sale.pendingInitialPayment),
                          emphasis: sale.pendingInitialPayment > 0.009,
                        ),
                        PdfField(
                          'Saldo financiado',
                          FinancialPdfTheme.money(sale.financedBalance),
                          emphasis: true,
                        ),
                        PdfField(
                          'Saldo pendiente',
                          FinancialPdfTheme.money(sale.pendingBalance),
                        ),
                        PdfField(
                          'Apartado mínimo',
                          sale.minimumReserveAmount == null
                              ? '-'
                              : FinancialPdfTheme.money(
                                  sale.minimumReserveAmount!,
                                ),
                        ),
                        PdfField('Estado venta', _capitalize(sale.status)),
                      ], columns: 2),
                    ),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: FinancialPdfTheme.card(
                        title: 'Validación y firmas',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _initialNotice(sale),
                            pw.SizedBox(height: 20),
                            pw.Row(
                              children: [
                                pw.Expanded(
                                  child: FinancialPdfTheme.signatureLine(
                                    'Firma del cliente',
                                  ),
                                ),
                                pw.SizedBox(width: 24),
                                pw.Expanded(
                                  child: FinancialPdfTheme.signatureLine(
                                    'Firma autorizada / vendedor',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 11),
        pw.Container(height: 0.75, color: FinancialPdfTheme.line),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Documento válido con firma y sello. No se aceptan devoluciones.',
            style: FinancialPdfTheme.text(
              size: 7.2,
              color: FinancialPdfTheme.muted,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _initialNotice(dynamic sale) {
    final pending = sale.pendingInitialPayment as double;
    final paid = sale.paidInitialPayment as double;
    final isPaid = pending <= 0.009 && paid > 0.009;
    final title = isPaid
        ? 'Inicial pagado'
        : (paid > 0.009 ? 'Inicial pendiente' : 'Apartado');
    final message = isPaid
        ? 'El monto inicial requerido figura como cubierto para esta operación.'
        : (paid > 0.009
              ? 'Esta venta mantiene balance pendiente de inicial. No debe tratarse como inicial pagado hasta completar el monto requerido.'
              : 'Esta operación corresponde a un apartado. No representa inicial pagado hasta completar el monto inicial requerido.');

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: isPaid
            ? FinancialPdfTheme.softGreen
            : FinancialPdfTheme.warningSoft,
        border: pw.Border.all(
          color: isPaid ? FinancialPdfTheme.green : FinancialPdfTheme.warning,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: FinancialPdfTheme.text(
              size: 8.2,
              bold: true,
              color: isPaid
                  ? FinancialPdfTheme.greenDark
                  : FinancialPdfTheme.warning,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            message,
            style: FinancialPdfTheme.text(size: 8.2, lineSpacing: 1.25),
          ),
        ],
      ),
    );
  }

  static String _initialStatusLabel(dynamic sale) {
    final pending = sale.pendingInitialPayment as double;
    final paid = sale.paidInitialPayment as double;
    if (pending <= 0.009 && paid > 0.009) {
      return 'Inicial pagado';
    }
    if (paid > 0.009) {
      return 'Inicial pendiente';
    }
    return 'Apartado';
  }

  static String _initialAmountLabel(dynamic sale) {
    final pending = sale.pendingInitialPayment as double;
    final paid = sale.paidInitialPayment as double;
    if (pending <= 0.009 && paid > 0.009) {
      return 'Inicial pagado';
    }
    if (paid > 0.009) {
      return 'Abono a inicial';
    }
    return 'Apartado registrado';
  }

  static double _initialAmountValue(dynamic sale) {
    final paid = sale.paidInitialPayment as double;
    if (paid > 0.009) {
      return paid;
    }
    return (sale.minimumReserveAmount as double?) ?? 0;
  }

  static String _paymentMethod(String value) {
    return switch (value.trim().toLowerCase()) {
      'transferencia' => 'Transferencia',
      'cheque' => 'Cheque',
      'tarjeta' => 'Tarjeta',
      'efectivo' => 'Efectivo',
      _ => FinancialPdfTheme.dash(value),
    };
  }

  static String _capitalize(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      return '-';
    }
    return clean[0].toUpperCase() + clean.substring(1).toLowerCase();
  }
}
