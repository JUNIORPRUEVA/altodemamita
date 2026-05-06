import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../shared/pdf/financial_pdf_theme.dart';
import '../../domain/receipt.dart';

class ReceiptPdfBuilder {
  static Future<Uint8List> build(
    Receipt receipt, {
    PdfPageFormat? pageFormat,
  }) async {
    final format = pageFormat ?? PdfPageFormat.letter.landscape;
    final fonts = await FinancialPdfTheme.loadFonts();
    final logo = FinancialPdfTheme.decodeLogo(receipt.company.logoBytesBase64);
    final doc = pw.Document(theme: fonts.theme);
    final compact = format.width < 340 || format.height > format.width * 1.8;

    doc.addPage(
      compact
          ? pw.MultiPage(
              pageFormat: format,
              margin: const pw.EdgeInsets.fromLTRB(10, 10, 10, 12),
              build: (_) => _buildCompact(receipt, logo),
            )
          : pw.Page(
              pageFormat: format,
              margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 20),
              build: (_) => _buildLetter(receipt, logo),
            ),
    );

    return doc.save();
  }

  static pw.Widget _buildLetter(Receipt receipt, pw.MemoryImage? logo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        FinancialPdfTheme.documentHeader(
          companyName: receipt.company.nombre.trim().isEmpty
              ? 'Sistema de Solares'
              : receipt.company.nombre.trim(),
          phone: receipt.company.telefono,
          address: receipt.company.direccion,
          logo: logo,
          documentTitle: 'Recibo de pago',
          subtitle: 'Comprobante financiero de pago recibido',
          metaItems: [
            PdfMetaItem(
              'Recibo',
              FinancialPdfTheme.dash(receipt.receiptNumber),
            ),
            PdfMetaItem('Fecha', receipt.formattedDateShort),
            PdfMetaItem(
              'Monto',
              FinancialPdfTheme.money(receipt.totalAmount),
              emphasis: true,
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 60,
                child: pw.Column(
                  children: [
                    FinancialPdfTheme.card(
                      title: 'Información del pago',
                      child: FinancialPdfTheme.fieldGrid(
                        _receiptFields(receipt),
                        columns: 3,
                      ),
                    ),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: FinancialPdfTheme.card(
                        title: 'Detalle aplicado',
                        child: _paymentTable(receipt),
                      ),
                    ),
                    pw.SizedBox(height: 9),
                    _amountInWords(receipt),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 40,
                child: pw.Column(
                  children: [
                    FinancialPdfTheme.card(
                      title: 'Resumen de cuenta',
                      child: pw.Column(
                        children: [
                          FinancialPdfTheme.keyValue(
                            'Pagado en recibo',
                            FinancialPdfTheme.money(receipt.totalAmount),
                            emphasis: true,
                          ),
                          FinancialPdfTheme.keyValue(
                            'Balance actual',
                            FinancialPdfTheme.money(
                              receipt.currentOutstandingBalance,
                            ),
                          ),
                          FinancialPdfTheme.keyValue(
                            'Saldo plan',
                            FinancialPdfTheme.money(
                              receipt.remainingFinancedBalance,
                            ),
                          ),
                          FinancialPdfTheme.keyValue(
                            'Inicial pendiente',
                            FinancialPdfTheme.money(
                              receipt.remainingInitialBalance,
                            ),
                          ),
                          FinancialPdfTheme.keyValue(
                            'Total acumulado',
                            FinancialPdfTheme.money(
                              receipt.totalPaidAccumulated,
                            ),
                          ),
                          FinancialPdfTheme.keyValue(
                            'Estado cuenta',
                            FinancialPdfTheme.dash(receipt.accountStatusLabel),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: FinancialPdfTheme.card(
                        title: 'Cuotas y validación',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            FinancialPdfTheme.keyValue(
                              'Cuotas pagadas',
                              '${receipt.installmentsPaid}',
                            ),
                            FinancialPdfTheme.keyValue(
                              'Cuotas restantes',
                              '${receipt.installmentsRemaining}',
                            ),
                            FinancialPdfTheme.keyValue(
                              'Próxima cuota',
                              receipt.nextInstallmentNumber == null
                                  ? '-'
                                  : '#${receipt.nextInstallmentNumber}',
                            ),
                            FinancialPdfTheme.keyValue(
                              'Fecha vencimiento',
                              receipt.nextInstallmentDueDate == null
                                  ? '-'
                                  : receipt.formatShortDate(
                                      receipt.nextInstallmentDueDate!,
                                    ),
                            ),
                            FinancialPdfTheme.keyValue(
                              'Monto próxima',
                              receipt.nextInstallmentAmount == null
                                  ? '-'
                                  : FinancialPdfTheme.money(
                                      receipt.nextInstallmentAmount!,
                                    ),
                            ),
                            pw.SizedBox(height: 14),
                            pw.Row(
                              children: [
                                pw.Expanded(
                                  child: FinancialPdfTheme.signatureLine(
                                    'Entregado por',
                                    name: receipt.deliveredBy,
                                  ),
                                ),
                                pw.SizedBox(width: 20),
                                pw.Expanded(
                                  child: FinancialPdfTheme.signatureLine(
                                    'Recibido por / firma',
                                    name: receipt.receivedBy,
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
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Comprobante válido con firma y sello. No se aceptan devoluciones.',
            style: FinancialPdfTheme.text(
              size: 7.2,
              color: FinancialPdfTheme.muted,
            ),
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _buildCompact(Receipt receipt, pw.MemoryImage? logo) {
    return [
      FinancialPdfTheme.documentHeader(
        companyName: receipt.company.nombre.trim().isEmpty
            ? 'Sistema de Solares'
            : receipt.company.nombre.trim(),
        phone: receipt.company.telefono,
        address: receipt.company.direccion,
        logo: logo,
        documentTitle: 'Recibo de pago',
        metaItems: [
          PdfMetaItem('Recibo', FinancialPdfTheme.dash(receipt.receiptNumber)),
          PdfMetaItem('Fecha', receipt.formattedDateShort),
          PdfMetaItem(
            'Monto',
            FinancialPdfTheme.money(receipt.totalAmount),
            emphasis: true,
          ),
        ],
        compact: true,
      ),
      pw.SizedBox(height: 8),
      FinancialPdfTheme.card(
        title: 'Información del pago',
        child: FinancialPdfTheme.fieldGrid(_receiptFields(receipt), columns: 2),
      ),
      pw.SizedBox(height: 8),
      FinancialPdfTheme.card(
        title: 'Detalle aplicado',
        child: _paymentTable(receipt),
      ),
      pw.SizedBox(height: 8),
      FinancialPdfTheme.card(
        title: 'Resumen',
        child: pw.Column(
          children: [
            FinancialPdfTheme.keyValue(
              'Balance actual',
              FinancialPdfTheme.money(receipt.currentOutstandingBalance),
            ),
            FinancialPdfTheme.keyValue(
              'Total acumulado',
              FinancialPdfTheme.money(receipt.totalPaidAccumulated),
            ),
            FinancialPdfTheme.keyValue(
              'Estado cuenta',
              FinancialPdfTheme.dash(receipt.accountStatusLabel),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 18),
      FinancialPdfTheme.signatureLine(
        'Recibido por / firma',
        name: receipt.receivedBy,
      ),
    ];
  }

  static List<PdfField> _receiptFields(Receipt receipt) {
    return [
      PdfField('Cliente', FinancialPdfTheme.dash(receipt.sale.clientName)),
      PdfField('Cédula', FinancialPdfTheme.dash(receipt.sale.clientDocumentId)),
      PdfField('Solar', _solarLabel(receipt)),
      PdfField('Venta', '#${receipt.sale.saleId}'),
      PdfField('Concepto', FinancialPdfTheme.dash(receipt.paymentConcept)),
      PdfField(
        'Método de pago',
        FinancialPdfTheme.dash(receipt.paymentMethodLabel),
      ),
      PdfField('Referencia', _reference(receipt)),
      PdfField(
        'Cuota pagada',
        receipt.paidInstallment == null
            ? '-'
            : '#${receipt.paidInstallment!.installmentNumber}',
      ),
      PdfField('Recibido por', FinancialPdfTheme.dash(receipt.receivedBy)),
      PdfField('Entregado por', FinancialPdfTheme.dash(receipt.deliveredBy)),
      PdfField(
        'Registrado por',
        FinancialPdfTheme.dash(receipt.paymentRegisteredByName),
      ),
      PdfField(
        'Monto pagado',
        FinancialPdfTheme.money(receipt.totalAmount),
        emphasis: true,
      ),
    ];
  }

  static pw.Widget _paymentTable(Receipt receipt) {
    final rows = receipt.paymentBreakdown
        .map(
          (line) => [
            line.label,
            _detailText(receipt),
            FinancialPdfTheme.money(line.amount),
          ],
        )
        .toList(growable: false);

    return pw.Column(
      children: [
        pw.TableHelper.fromTextArray(
          headers: const ['Concepto', 'Detalle', 'Monto'],
          data: rows,
          border: pw.TableBorder(
            top: pw.BorderSide(color: FinancialPdfTheme.line, width: 0.7),
            bottom: pw.BorderSide(color: FinancialPdfTheme.line, width: 0.7),
            horizontalInside: pw.BorderSide(
              color: FinancialPdfTheme.softLine,
              width: 0.4,
            ),
          ),
          headerDecoration: pw.BoxDecoration(
            color: FinancialPdfTheme.greenDark,
          ),
          headerStyle: FinancialPdfTheme.text(
            size: 7.5,
            bold: true,
            color: PdfColors.white,
          ),
          cellStyle: FinancialPdfTheme.text(size: 8.2),
          oddCellStyle: FinancialPdfTheme.text(size: 8.2),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 5,
          ),
          rowDecoration: pw.BoxDecoration(color: FinancialPdfTheme.surface),
          oddRowDecoration: pw.BoxDecoration(color: PdfColors.white),
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
          },
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FixedColumnWidth(86),
          },
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(
            color: FinancialPdfTheme.softGreen,
            border: pw.Border.all(color: PdfColor.fromHex('#CDE8DA')),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'TOTAL PAGADO',
                  style: FinancialPdfTheme.text(
                    size: 8,
                    bold: true,
                    color: FinancialPdfTheme.greenDark,
                  ),
                ),
              ),
              pw.Text(
                FinancialPdfTheme.money(receipt.totalAmount),
                style: FinancialPdfTheme.text(
                  size: 10,
                  bold: true,
                  color: FinancialPdfTheme.greenDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _amountInWords(Receipt receipt) {
    final note = receipt.note.trim();
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: FinancialPdfTheme.surface,
        border: pw.Border.all(color: FinancialPdfTheme.line, width: 0.7),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'MONTO EN LETRAS',
            style: FinancialPdfTheme.text(
              size: 7.2,
              bold: true,
              color: FinancialPdfTheme.muted,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            receipt.amountInWords.toUpperCase(),
            maxLines: 2,
            style: FinancialPdfTheme.text(
              size: 8.8,
              bold: true,
              lineSpacing: 1.2,
            ),
          ),
          if (note.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Observación: $note',
              maxLines: 2,
              style: FinancialPdfTheme.text(
                size: 8,
                color: FinancialPdfTheme.muted,
                lineSpacing: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _solarLabel(Receipt receipt) {
    final block = receipt.blockNumber.trim();
    final lot = receipt.lotNumber.trim();
    if (block.isEmpty && lot.isEmpty) {
      return '-';
    }
    return 'M$block-S$lot';
  }

  static String _reference(Receipt receipt) {
    return FinancialPdfTheme.dash(receipt.payment.reference);
  }

  static String _detailText(Receipt receipt) {
    final method = FinancialPdfTheme.dash(receipt.paymentMethodLabel);
    final reference = _reference(receipt);
    return reference == '-' ? method : '$method | $reference';
  }
}
