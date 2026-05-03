import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../settings/domain/company_info.dart';
import '../../domain/sale_calculator.dart';
import '../../domain/sale_detail.dart';

class SaleAmortizationPdfBuilder {
  static PdfPageFormat get pageFormat => PdfPageFormat.a4;

  static final Future<pw.Font> _baseFontFuture = _loadFont(
    'assets/fonts/NotoSans-Regular.ttf',
  );
  static final Future<pw.Font> _boldFontFuture = _loadFont(
    'assets/fonts/NotoSans-Bold.ttf',
  );

  static final PdfColor _borderColor = PdfColor.fromHex('#D8E0E8');
  static final PdfColor _surfaceTint = PdfColor.fromHex('#F4F7FB');
  static final PdfColor _accentColor = PdfColor.fromHex('#234A84');
  static final PdfColor _inkColor = PdfColor.fromHex('#172433');
  static final PdfColor _mutedColor = PdfColor.fromHex('#667788');
  static final PdfColor _successColor = PdfColor.fromHex('#0E6B4C');

  static Future<Uint8List> build({
    required SaleDetail detail,
    required CompanyInfo company,
    PdfPageFormat? pageFormat,
  }) async {
    final resolvedPageFormat =
        pageFormat ?? SaleAmortizationPdfBuilder.pageFormat;
    final baseFont = await _baseFontFuture;
    final boldFont = await _boldFontFuture;
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    final logoImage = _decodeLogo(company.logoBytesBase64);
    final computedTable = _buildTableRows(detail);

    document.addPage(
      pw.MultiPage(
        pageFormat: resolvedPageFormat,
        margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 18),
        build: (_) => [
          _buildHeader(detail: detail, company: company, logoImage: logoImage),
          pw.SizedBox(height: 10),
          _buildSummary(detail),
          pw.SizedBox(height: 10),
          _buildInstallmentsTable(computedTable.rows),
          pw.SizedBox(height: 10),
          _buildTotals(computedTable),
        ],
      ),
    );

    return document.save();
  }

  static Future<pw.Font> _loadFont(String assetPath) async {
    final fontData = await rootBundle.load(assetPath);
    return pw.Font.ttf(fontData);
  }

  static pw.MemoryImage? _decodeLogo(String? logoBase64) {
    if (logoBase64 == null || logoBase64.isEmpty) {
      return null;
    }

    try {
      return pw.MemoryImage(base64Decode(logoBase64));
    } catch (_) {
      return null;
    }
  }

  static _ComputedTable _buildTableRows(SaleDetail detail) {
    var totalCapital = 0.0;
    var totalInterest = 0.0;
    var totalAmount = 0.0;

    final rows = List<List<String>>.generate(detail.installments.length, (
      index,
    ) {
      final installment = detail.installments[index];
      totalCapital += installment.principalAmount;
      totalInterest += installment.interestAmount;
      totalAmount += installment.totalAmount;

      return [
        '${installment.installmentNumber}',
        _formatDate(installment.dueDate),
        _money(installment.openingBalance),
        _money(installment.principalAmount),
        _money(installment.interestAmount),
        _money(installment.totalAmount),
        _money(installment.paidAmount),
        _money(installment.remainingAmount),
        _money(installment.endingBalance),
        _formatStatus(installment.status),
      ];
    }, growable: false);

    return _ComputedTable(
      rows: rows,
      totalCapital: totalCapital,
      totalInterest: totalInterest,
      totalAmount: totalAmount,
    );
  }

  static pw.Widget _buildHeader({
    required SaleDetail detail,
    required CompanyInfo company,
    required pw.MemoryImage? logoImage,
  }) {
    final companyName = company.nombre.trim().isEmpty
        ? 'Sistema de Solares'
        : company.nombre.trim();
    final companyPhone = (company.telefono ?? '').trim();
    final companyAddress = (company.direccion ?? '').trim();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildLogo(logoImage),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 13.8,
                        fontWeight: pw.FontWeight.bold,
                        color: _inkColor,
                      ),
                    ),
                    if (companyPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Telefono: $companyPhone',
                        style: pw.TextStyle(fontSize: 8.7, color: _mutedColor),
                      ),
                    ],
                    if (companyAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        companyAddress,
                        style: pw.TextStyle(fontSize: 8.7, color: _mutedColor),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Container(
                width: 172,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: _borderColor),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _metaLine('Venta', '#${detail.sale.id ?? 0}'),
                    _metaLine('Fecha', _formatDate(detail.sale.saleDate)),
                    _metaLine('Cliente', detail.clientName),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: _surfaceTint,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: _borderColor),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 8,
                  height: 34,
                  decoration: pw.BoxDecoration(
                    color: _accentColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Text(
                  'TABLA DE AMORTIZACION',
                  style: pw.TextStyle(
                    fontSize: 11.8,
                    fontWeight: pw.FontWeight.bold,
                    color: _accentColor,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          _buildHeaderTagsRow(detail),
        ],
      ),
    );
  }

  static pw.Widget _buildHeaderTagsRow(SaleDetail detail) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _headerTag('Solar', detail.lotDisplayCode),
        _headerTag(
          'Plazo activo',
          '${detail.activeInstallmentCount}/${detail.sale.installmentCount}',
        ),
        if (detail.reducedInstallmentCount > 0)
          _headerTag('Reduccion', '-${detail.reducedInstallmentCount}'),
        _headerTag('Cedula', detail.clientDocumentId),
      ],
    );
  }

  static pw.Widget _metaLine(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7.4,
              fontWeight: pw.FontWeight.bold,
              color: _mutedColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: highlight ? 9.8 : 8.9,
              fontWeight: pw.FontWeight.bold,
              color: highlight ? _successColor : _inkColor,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildLogo(pw.MemoryImage? logoImage) {
    return pw.Container(
      width: 58,
      height: 58,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _borderColor),
      ),
      child: logoImage != null
          ? pw.Image(logoImage, fit: pw.BoxFit.contain)
          : pw.Center(
              child: pw.Text(
                'LOGO',
                style: pw.TextStyle(
                  fontSize: 7.2,
                  fontWeight: pw.FontWeight.bold,
                  color: _accentColor,
                ),
              ),
            ),
    );
  }

  static pw.Widget _headerTag(String label, String value) {
    return pw.Container(
      width: 123,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7.0,
              fontWeight: pw.FontWeight.bold,
              color: _mutedColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.3,
              fontWeight: pw.FontWeight.bold,
              color: _inkColor,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummary(SaleDetail detail) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 5,
                height: 14,
                decoration: pw.BoxDecoration(
                  color: _accentColor,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                'RESUMEN DE VENTA',
                style: pw.TextStyle(
                  fontSize: 8.4,
                  fontWeight: pw.FontWeight.bold,
                  color: _accentColor,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _summaryItem('Cedula', detail.clientDocumentId),
              _summaryItem('Vendedor', detail.sellerName ?? '-'),
              _summaryItem(
                'Interes mensual',
                '${detail.sale.monthlyInterest.toStringAsFixed(2)}%',
              ),
              _summaryItem(
                'Cuota fija mensual',
                _money(_fixedInstallmentAmount(detail)),
              ),
              _summaryItem(
                'Saldo financiado',
                _money(detail.sale.financedBalance),
                highlight: true,
              ),
              _summaryItem(
                'Saldo pendiente',
                _money(detail.sale.pendingBalance),
                highlight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryItem(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return pw.Container(
      width: 185,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 6.9,
              fontWeight: pw.FontWeight.bold,
              color: _mutedColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: highlight ? 9.9 : 8.5,
              fontWeight: pw.FontWeight.bold,
              color: highlight ? _successColor : _inkColor,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInstallmentsTable(List<List<String>> rows) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'LISTADO DE CUOTAS',
            style: pw.TextStyle(
              fontSize: 8.1,
              fontWeight: pw.FontWeight.bold,
              color: _accentColor,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Vence',
              'Saldo inicial',
              'Capital',
              'Interes',
              'Cuota',
              'Pagado',
              'Pendiente',
              'Saldo final',
              'Estado',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 7.1,
              fontWeight: pw.FontWeight.bold,
              color: _inkColor,
            ),
            cellStyle: pw.TextStyle(fontSize: 6.9, color: _inkColor),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 3.6,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E6EDF9'),
            ),
            border: pw.TableBorder.all(color: _borderColor, width: 0.42),
            columnWidths: const {
              0: pw.FixedColumnWidth(18),
              1: pw.FlexColumnWidth(1.08),
              2: pw.FlexColumnWidth(1.45),
              3: pw.FlexColumnWidth(1.14),
              4: pw.FlexColumnWidth(1.08),
              5: pw.FlexColumnWidth(1.16),
              6: pw.FlexColumnWidth(1.13),
              7: pw.FlexColumnWidth(1.17),
              8: pw.FlexColumnWidth(1.32),
              9: pw.FlexColumnWidth(0.92),
            },
            cellAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.center,
            },
            rowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFE')),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTotals(_ComputedTable computedTable) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _totalItem(
              'Capital total',
              _money(computedTable.totalCapital),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _totalItem(
              'Interes total',
              _money(computedTable.totalInterest),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _totalItem(
              'Total del plan',
              _money(computedTable.totalAmount),
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalItem(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: _mutedColor,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: highlight ? 11 : 9.8,
            fontWeight: pw.FontWeight.bold,
            color: highlight ? _successColor : _inkColor,
          ),
        ),
      ],
    );
  }

  static String _money(double value) {
    final normalized = value.isFinite ? value : 0;
    final fixed = normalized.toStringAsFixed(2);
    final parts = fixed.split('.');
    final integer = parts.first;
    final decimal = parts.last;

    final buffer = StringBuffer();
    for (var index = 0; index < integer.length; index++) {
      final reverseIndex = integer.length - index;
      buffer.write(integer[index]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }

    return 'RD\$${buffer.toString()}.$decimal';
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  static String _formatStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'pagada':
        return 'Pagada';
      case 'vencida':
        return 'Vencida';
      case 'parcial':
        return 'Parcial';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Pendiente';
    }
  }

  static double _fixedInstallmentAmount(SaleDetail detail) {
    if (detail.installments.isNotEmpty) {
      return detail.installments.first.totalAmount;
    }

    return SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: detail.sale.financedBalance,
      monthlyInterest: detail.sale.monthlyInterest,
      installmentCount: detail.sale.installmentCount,
    );
  }
}

class _ComputedTable {
  const _ComputedTable({
    required this.rows,
    required this.totalCapital,
    required this.totalInterest,
    required this.totalAmount,
  });

  final List<List<String>> rows;
  final double totalCapital;
  final double totalInterest;
  final double totalAmount;
}
