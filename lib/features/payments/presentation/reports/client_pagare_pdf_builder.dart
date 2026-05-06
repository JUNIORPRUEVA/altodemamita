import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../settings/domain/company_info.dart';
import '../../domain/client_pagare_report.dart';

class ClientPagarePdfBuilder {
  static PdfPageFormat get pageFormat => PdfPageFormat.a4;

  static final Future<pw.Font> _baseFontFuture = _loadFont(
    'assets/fonts/NotoSans-Regular.ttf',
  );
  static final Future<pw.Font> _boldFontFuture = _loadFont(
    'assets/fonts/NotoSans-Bold.ttf',
  );

  static final PdfColor _borderColor = PdfColor.fromHex('#D8E0E8');
  static final PdfColor _softBorderColor = PdfColor.fromHex('#E7EDF4');
  static final PdfColor _surfaceTint = PdfColor.fromHex('#F4F7FB');
  static final PdfColor _accentColor = PdfColor.fromHex('#234A84');
  static final PdfColor _inkColor = PdfColor.fromHex('#172433');
  static final PdfColor _mutedColor = PdfColor.fromHex('#667788');
  static final PdfColor _successColor = PdfColor.fromHex('#0E6B4C');

  static Future<Uint8List> build({
    required ClientPagareReport report,
    required CompanyInfo company,
  }) async {
    final baseFont = await _baseFontFuture;
    final boldFont = await _boldFontFuture;
    final logoImage = _decodeLogo(company.logoBytesBase64);
    final generatedAt = DateTime.now();
    final tableData = _buildPaymentTable(report);

    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 24),
        footer: (context) =>
            _buildFooter(context, report: report, tableData: tableData),
        build: (_) => [
          _buildHeader(
            report: report,
            company: company,
            logoImage: logoImage,
            generatedAt: generatedAt,
            tableData: tableData,
          ),
          pw.SizedBox(height: 10),
          _buildClientSection(report, tableData: tableData),
          pw.SizedBox(height: 10),
          ..._buildPaymentsSection(tableData),
          pw.SizedBox(height: 10),
          _buildSummarySection(report, tableData),
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

  static pw.Widget _buildHeader({
    required ClientPagareReport report,
    required CompanyInfo company,
    required pw.MemoryImage? logoImage,
    required DateTime generatedAt,
    required _PaymentTableData tableData,
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
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: _inkColor,
                      ),
                    ),
                    if (companyPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Tel. $companyPhone',
                        style: pw.TextStyle(fontSize: 8.8, color: _mutedColor),
                      ),
                    ],
                    if (companyAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        companyAddress,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          color: _mutedColor,
                          lineSpacing: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Container(
                width: 190,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: _borderColor),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _metaLine('Fecha', _formatDate(generatedAt)),
                    _metaLine('Periodo', _formatRange(tableData)),
                    _metaLine(
                      'Monto total',
                      _money(report.totalPaid),
                      highlight: true,
                    ),
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
                  height: 38,
                  decoration: pw.BoxDecoration(
                    color: _accentColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Text(
                    'LISTA DE PAGOS DEL CLIENTE',
                    style: pw.TextStyle(
                      fontSize: 11.8,
                      fontWeight: pw.FontWeight.bold,
                      color: _accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildLogo(pw.MemoryImage? logoImage) {
    return pw.Container(
      width: 56,
      height: 56,
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
              fontSize: 7.3,
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

  static pw.Widget _buildClientSection(
    ClientPagareReport report, {
    required _PaymentTableData tableData,
  }) {
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
          pw.Text(
            'DATOS DEL CLIENTE',
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: pw.FontWeight.bold,
              color: _accentColor,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _textOrDash(report.clientName),
                      style: pw.TextStyle(
                        fontSize: 12.2,
                        fontWeight: pw.FontWeight.bold,
                        color: _inkColor,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Cedula: ${_textOrDash(report.clientDocumentId)}',
                      style: pw.TextStyle(fontSize: 9.0, color: _mutedColor),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: _surfaceTint,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: _borderColor),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _summaryLine('Cliente ID', '${report.clientId}'),
                      _summaryLine('Ventas activas', '${tableData.salesCount}'),
                      _summaryLine(
                        'Ultimo pago',
                        _formatOptionalDate(tableData.lastPaymentDate),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 86,
            child: pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _mutedColor,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8.7,
                fontWeight: pw.FontWeight.bold,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildPaymentsSection(_PaymentTableData tableData) {
    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: _borderColor),
        ),
        child: pw.Text(
          'PAGOS REGISTRADOS',
          style: pw.TextStyle(
            fontSize: 8.2,
            fontWeight: pw.FontWeight.bold,
            color: _accentColor,
          ),
        ),
      ),
      pw.SizedBox(height: 6),
      _buildPaymentsTable(tableData.rows),
    ];
  }

  static pw.Widget _buildPaymentsTable(List<List<String>> rows) {
    if (rows.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: _borderColor),
        ),
        child: pw.Text(
          'No hay pagos registrados para este cliente.',
          style: pw.TextStyle(fontSize: 8.5, color: _mutedColor),
        ),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: const [
        '#',
        'Fecha',
        'Tipo de pago',
        'Cuota / Ref.',
        'Metodo',
        'Venta',
        'Solar',
        'Monto',
      ],
      data: rows,
      headerStyle: pw.TextStyle(
        fontSize: 7.0,
        fontWeight: pw.FontWeight.bold,
        color: _inkColor,
      ),
      cellStyle: pw.TextStyle(fontSize: 6.9, color: _inkColor),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#EAF0FB')),
      border: pw.TableBorder.all(color: _borderColor, width: 0.45),
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FlexColumnWidth(0.92),
        2: pw.FlexColumnWidth(1.55),
        3: pw.FlexColumnWidth(1.60),
        4: pw.FlexColumnWidth(1.15),
        5: pw.FlexColumnWidth(0.75),
        6: pw.FlexColumnWidth(0.95),
        7: pw.FlexColumnWidth(1.0),
      },
      cellAlignments: const {
        0: pw.Alignment.center,
        1: pw.Alignment.center,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
        7: pw.Alignment.centerRight,
      },
      rowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#FAFBFD')),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
    );
  }

  static pw.Widget _buildSummarySection(
    ClientPagareReport report,
    _PaymentTableData tableData,
  ) {
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
          pw.Text(
            'CIERRE DEL REPORTE',
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: pw.FontWeight.bold,
              color: _accentColor,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _closingMetric(
                  'Pagos registrados',
                  '${report.items.length}',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _closingMetric(
                  'Ventas impactadas',
                  '${tableData.salesCount}',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _closingMetric(
                  'Total cobrado',
                  _money(report.totalPaid),
                  highlight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _closingMetric(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7.3,
              fontWeight: pw.FontWeight.bold,
              color: _mutedColor,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: highlight ? 10.8 : 9.8,
              fontWeight: pw.FontWeight.bold,
              color: highlight ? _successColor : _inkColor,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(
    pw.Context context, {
    required ClientPagareReport report,
    required _PaymentTableData tableData,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _softBorderColor, width: 0.6),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Cliente ${_textOrDash(report.clientName)}',
              style: pw.TextStyle(fontSize: 7.6, color: _mutedColor),
              maxLines: 1,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Text(
            'Pagina ${context.pageNumber}',
            style: pw.TextStyle(
              fontSize: 7.6,
              fontWeight: pw.FontWeight.bold,
              color: _accentColor,
            ),
          ),
        ],
      ),
    );
  }

  static _PaymentTableData _buildPaymentTable(ClientPagareReport report) {
    final items = [...report.items]
      ..sort((left, right) {
        final byDate = left.paymentDate.compareTo(right.paymentDate);
        if (byDate != 0) {
          return byDate;
        }
        return left.paymentId.compareTo(right.paymentId);
      });

    final rows = List<List<String>>.generate(items.length, (index) {
      final item = items[index];
      return [
        '${index + 1}',
        _formatDate(item.paymentDate),
        _paymentTypeLabel(item),
        _quotaOrReference(item),
        _capitalize(_textOrDash(item.paymentMethod)),
        '#${item.saleId}',
        item.lotDisplayCode,
        _money(item.amountPaid),
      ];
    }, growable: false);

    return _PaymentTableData(
      rows: rows,
      salesCount: items.map((item) => item.saleId).toSet().length,
      firstPaymentDate: items.isEmpty ? null : items.first.paymentDate,
      lastPaymentDate: items.isEmpty ? null : items.last.paymentDate,
    );
  }

  static String _paymentTypeLabel(ClientPagareItem item) {
    switch (item.paymentType.trim().toLowerCase()) {
      case 'abono_capital':
        return 'Abono a capital';
      case 'abono_inicial':
        return 'Abono a inicial';
      case 'apartado':
        return 'Pago de apartado';
      default:
        return item.installmentNumber == null
            ? 'Pago aplicado'
            : 'Pago de cuota #${item.installmentNumber}';
    }
  }

  static String _quotaOrReference(ClientPagareItem item) {
    final reference = (item.reference ?? '').trim();
    final quota = item.installmentNumber == null
        ? '-'
        : 'Cuota #${item.installmentNumber}';

    if (reference.isEmpty) {
      return quota;
    }
    if (quota == '-') {
      return reference;
    }
    return '$quota · $reference';
  }

  static String _formatRange(_PaymentTableData tableData) {
    final first = tableData.firstPaymentDate;
    final last = tableData.lastPaymentDate;
    if (first == null || last == null) {
      return '-';
    }
    return '${_formatDate(first)} - ${_formatDate(last)}';
  }

  static String _formatOptionalDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return _formatDate(value);
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

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  static String _capitalize(String value) {
    if (value.isEmpty || value == '-') {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static String _textOrDash(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? '-' : normalized;
  }
}

class _PaymentTableData {
  const _PaymentTableData({
    required this.rows,
    required this.salesCount,
    required this.firstPaymentDate,
    required this.lastPaymentDate,
  });

  final List<List<String>> rows;
  final int salesCount;
  final DateTime? firstPaymentDate;
  final DateTime? lastPaymentDate;
}
