import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../settings/domain/company_info.dart';
import '../../domain/sale_detail.dart';

class SaleInitialReceiptPdfBuilder {
  static PdfPageFormat get pageFormat => PdfPageFormat.letter.landscape;

  static Future<Uint8List> build({
    required SaleDetail detail,
    required CompanyInfo company,
    PdfPageFormat? pageFormat,
  }) async {
    final resolvedPageFormat =
        pageFormat ?? SaleInitialReceiptPdfBuilder.pageFormat;
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    pw.MemoryImage? logoImage;
    final logoBase64 = company.logoBytesBase64;
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(base64Decode(logoBase64));
      } catch (_) {
        logoImage = null;
      }
    }

    final sale = detail.sale;
    final firstInstallment = detail.installments.isEmpty
        ? null
        : detail.installments.first;
    final estimatedInstallmentAmount =
        firstInstallment?.totalAmount ??
        (sale.installmentCount > 0
            ? sale.financedBalance / sale.installmentCount
            : 0);

    final rows = <List<String>>[
      ['Cliente', detail.clientName],
      ['Cédula', detail.clientDocumentId],
      ['Vendedor', detail.sellerName ?? '-'],
      ['Solar', detail.lotDisplayCode],
      ['Fecha de venta', _formatDate(sale.saleDate)],
      [
        'Metodo del primer pago',
        _formatPaymentMethod(detail.initialPaymentMethod),
      ],
      ['Metros cuadrados', '${detail.lotArea.toStringAsFixed(2)} m²'],
      ['Precio por metro', _money(detail.lotPricePerSquareMeter)],
      ['Precio total', _money(sale.salePrice)],
      ['Inicial mínimo requerido', _money(sale.requiredInitialPayment)],
      ['Inicial real pagado', _money(sale.paidInitialPayment)],
      ['Inicial mínimo pendiente', _money(sale.pendingInitialPayment)],
      ['Saldo financiado', _money(sale.financedBalance)],
      ['Interés mensual', '${sale.monthlyInterest.toStringAsFixed(2)}%'],
      ['Cantidad de cuotas', '${sale.installmentCount}'],
      ['Monto estimado por cuota', _money(estimatedInstallmentAmount)],
    ];

    if (sale.initialPaymentDeadline != null) {
      rows.insert(9, [
        'Fecha límite',
        _formatDate(sale.initialPaymentDeadline!),
      ]);
    }

    doc.addPage(
      pw.Page(
        pageFormat: resolvedPageFormat,
        margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 18),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                company,
                logoImage,
                sale.id ?? 0,
                sale.saleDate,
              ),
              pw.SizedBox(height: 10),
              _buildDivider(),
              pw.SizedBox(height: 10),
              _buildDataGrid(rows),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    'No se aceptan devoluciones.',
                    style: const pw.TextStyle(
                      fontSize: 8.4,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 22),
              pw.Row(
                children: [
                  pw.Expanded(child: _signatureLine('Firma cliente')),
                  pw.SizedBox(width: 28),
                  pw.Expanded(child: _signatureLine('Firma autorizado')),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildDocumentHeader(
    CompanyInfo company,
    pw.MemoryImage? logoImage,
    int saleId,
    DateTime saleDate,
  ) {
    final companyName = company.nombre.isEmpty
        ? 'Sistema de Solares'
        : company.nombre;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null)
              pw.Container(
                width: 56,
                height: 56,
                alignment: pw.Alignment.center,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              )
            else
              pw.Container(
                width: 56,
                height: 56,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                ),
                child: pw.Text('LOGO', style: const pw.TextStyle(fontSize: 8)),
              ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ((company.telefono ?? '').isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        'Tel: ${company.telefono}',
                        style: const pw.TextStyle(fontSize: 8.8),
                      ),
                    ),
                  if ((company.direccion ?? '').isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1),
                      child: pw.Text(
                        company.direccion!,
                        style: const pw.TextStyle(fontSize: 8.8),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Container(
              width: 170,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('VENTA', style: const pw.TextStyle(fontSize: 7.6)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '#$saleId',
                    style: pw.TextStyle(
                      fontSize: 9.2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('FECHA', style: const pw.TextStyle(fontSize: 7.6)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _formatDate(saleDate),
                    style: pw.TextStyle(
                      fontSize: 9.2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Text(
            'RECIBO DE INICIAL',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildDataGrid(List<List<String>> rows) {
    final normalized = List<List<String>>.from(rows);
    while (normalized.length % 3 != 0) {
      normalized.add(['', '']);
    }

    final tableRows = <pw.TableRow>[];
    for (var index = 0; index < normalized.length; index += 3) {
      final left = normalized[index];
      final center = normalized[index + 1];
      final right = normalized[index + 2];
      tableRows.add(
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            _dataCell(left[0], left[1]),
            _dataCell(center[0], center[1]),
            _dataCell(right[0], right[1]),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        outside: const pw.BorderSide(color: PdfColors.grey400, width: 0.8),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(),
        1: pw.FlexColumnWidth(),
        2: pw.FlexColumnWidth(),
      },
      children: tableRows,
    );
  }

  static pw.Widget _dataCell(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8.2, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDivider() {
    return pw.Container(height: 0.8, color: PdfColors.grey400);
  }

  static pw.Widget _signatureLine(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 0.8, color: PdfColors.grey700),
        pw.SizedBox(height: 5),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8.8)),
      ],
    );
  }

  static String _money(double value) => 'RD\$ ${value.toStringAsFixed(2)}';

  static String _formatPaymentMethod(String value) {
    switch (value.trim().toLowerCase()) {
      case 'transferencia':
        return 'Transferencia';
      case 'cheque':
        return 'Cheque';
      case 'tarjeta':
        return 'Tarjeta';
      default:
        return 'Efectivo';
    }
  }

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }
}
