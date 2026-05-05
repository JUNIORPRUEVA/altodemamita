import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/dominican_formatters.dart';
import '../../../settings/domain/company_info.dart';
import '../../domain/sale_calculator.dart';
import '../../domain/sale_detail.dart';

// â”€â”€â”€ Brand tokens â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
final _amAccent      = PdfColor.fromHex('#1B3F7A');
final _amAccentDark  = PdfColor.fromHex('#163168');
final _amAccentLight = PdfColor.fromHex('#E8EFFA');
final _amInk         = PdfColor.fromHex('#0F1E2E');
final _amMuted       = PdfColor.fromHex('#5C6E82');
final _amSurface     = PdfColor.fromHex('#F5F8FC');
final _amBorder      = PdfColor.fromHex('#CDD8E6');
final _amSuccess     = PdfColor.fromHex('#0A5C3E');
final _amSubtle      = PdfColor.fromHex('#B8CCEC');

class SaleAmortizationPdfBuilder {
  static PdfPageFormat get pageFormat => PdfPageFormat.a4;

  static final Future<pw.Font> _baseFontFuture = _loadFont(
    'assets/fonts/NotoSans-Regular.ttf',
  );
  static final Future<pw.Font> _boldFontFuture = _loadFont(
    'assets/fonts/NotoSans-Bold.ttf',
  );

  static Future<Uint8List> build({
    required SaleDetail detail,
    required CompanyInfo company,
    PdfPageFormat? pageFormat,
  }) async {
    final fmt  = pageFormat ?? SaleAmortizationPdfBuilder.pageFormat;
    final base = await _baseFontFuture;
    final bold = await _boldFontFuture;
    final logo = _decodeLogo(company.logoBytesBase64);

    final computed = _ComputedTable.fromDetail(detail);
    final sale     = detail.sale;

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: base, bold: bold),
    );

    doc.addPage(pw.MultiPage(
      pageFormat: fmt,
      margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 20),
      header: (ctx) => _pageHeader(ctx, company, logo, detail),
      footer: (ctx) => _pageFooter(ctx),
      build: (ctx) => [
        _summarySection(sale, detail, computed),
        pw.SizedBox(height: 14),
        _tableSection(computed),
        pw.SizedBox(height: 14),
        _totalsRow(computed),
      ],
    ));

    return doc.save();
  }

  // â”€â”€â”€ Page header (repeats on every page) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _pageHeader(
    pw.Context ctx,
    CompanyInfo co,
    pw.MemoryImage? logo,
    SaleDetail detail,
  ) {
    if (ctx.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: pw.BoxDecoration(
          color: _amAccentDark,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('TABLA DE AMORTIZACIÃ“N  â€”  Venta #${detail.sale.id ?? "-"}',
              style: pw.TextStyle(fontSize: 8.2,
                fontWeight: pw.FontWeight.bold, color: PdfColors.white,
                letterSpacing: 0.8)),
            pw.Text('PÃ¡gina ${ctx.pageNumber}',
              style: pw.TextStyle(fontSize: 8.0, color: _amSubtle)),
          ],
        ),
      );
    }

    final name    = co.nombre.trim().isEmpty ? 'Sistema de Solares' : co.nombre.trim();
    final phone   = (co.telefono  ?? '').trim();
    final address = (co.direccion ?? '').trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        color: _amAccent,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Logo
                pw.Container(
                  width: 52, height: 52,
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  child: logo != null
                      ? pw.Image(logo, fit: pw.BoxFit.contain)
                      : pw.Center(child: pw.Text('LOGO',
                          style: pw.TextStyle(fontSize: 7,
                            fontWeight: pw.FontWeight.bold, color: _amAccent))),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(name,
                        style: pw.TextStyle(fontSize: 15,
                          fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                      if (phone.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text('Tel. $phone',
                          style: pw.TextStyle(fontSize: 8.4, color: _amSubtle)),
                      ],
                      if (address.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(address,
                          style: pw.TextStyle(fontSize: 8.2, color: _amSubtle)),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Container(
                  width: 165,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: _amAccentDark,
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _wMeta('Venta',     '#${detail.sale.id ?? "-"}'),
                      pw.SizedBox(height: 4),
                      _wMeta('Cliente',   detail.clientName),
                      pw.SizedBox(height: 4),
                      _wMeta('Documento', 'AMORTIZACIÃ“N'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: pw.BoxDecoration(
              color: _amAccentDark,
              borderRadius: const pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(12),
                bottomRight: pw.Radius.circular(12),
              ),
            ),
            child: pw.Text('TABLA DE AMORTIZACIÃ“N â€” PLAN DE PAGOS',
              style: pw.TextStyle(fontSize: 9.5,
                fontWeight: pw.FontWeight.bold, color: PdfColors.white,
                letterSpacing: 1.6)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _wMeta(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label.toUpperCase(),
          style: pw.TextStyle(fontSize: 6.8,
            fontWeight: pw.FontWeight.bold, color: _amSubtle)),
        pw.SizedBox(height: 1),
        pw.Text(value,
          style: pw.TextStyle(fontSize: 8.6,
            fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      ],
    );
  }

  // â”€â”€â”€ Page footer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _pageFooter(pw.Context ctx) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Sujeto a condiciones contractuales',
            style: pw.TextStyle(fontSize: 7.2, color: _amMuted)),
          pw.Text('PÃ¡gina ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7.2, color: _amMuted)),
        ],
      ),
    );
  }

  // â”€â”€â”€ Summary section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _summarySection(
    dynamic sale,
    SaleDetail detail,
    _ComputedTable computed,
  ) {
    final firstInstallment = detail.installments.isEmpty
        ? null : detail.installments.first;
    final estAmt = firstInstallment?.totalAmount ??
        (sale.installmentCount > 0
            ? sale.financedBalance / sale.installmentCount
            : 0.0);

    final items = <_SumItem>[
      _SumItem('Solar',            detail.lotDisplayCode),
      _SumItem('Cliente',          detail.clientName),
      _SumItem('Precio del solar', _money(sale.salePrice)),
      _SumItem('Inicial pagado',   _money(sale.paidInitialPayment)),
      _SumItem('Saldo financiado', _money(sale.financedBalance), bold: true),
      _SumItem('InterÃ©s mensual',  '${sale.monthlyInterest.toStringAsFixed(2)}%'),
      _SumItem('No. de cuotas',    '${sale.installmentCount}'),
      _SumItem('Cuota estimada',   _money(estAmt), bold: true),
    ];

    const cols = 4;
    final padded = List<_SumItem>.from(items);
    while (padded.length % cols != 0) padded.add(const _SumItem('', ''));

    final rows = <pw.TableRow>[];
    for (var i = 0; i < padded.length; i += cols) {
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          for (var c = 0; c < cols; c++) _sumCell(padded[i + c]),
        ],
      ));
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _amBorder),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _amAccentLight,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text('RESUMEN DE LA VENTA',
              style: pw.TextStyle(fontSize: 7.2,
                fontWeight: pw.FontWeight.bold, color: _amAccent,
                letterSpacing: 0.4)),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.symmetric(
              inside:  pw.BorderSide(color: _amBorder, width: 0.5),
              outside: pw.BorderSide(color: _amBorder, width: 0.7),
            ),
            children: rows,
          ),
        ],
      ),
    );
  }

  static pw.Widget _sumCell(_SumItem s) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: s.label.isEmpty
          ? pw.SizedBox()
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(s.label.toUpperCase(),
                  style: pw.TextStyle(fontSize: 7.2,
                    fontWeight: pw.FontWeight.bold, color: _amMuted)),
                pw.SizedBox(height: 2),
                pw.Text(s.value,
                  style: pw.TextStyle(
                    fontSize: s.bold ? 10.0 : 9.0,
                    fontWeight: pw.FontWeight.bold,
                    color: s.bold ? _amSuccess : _amInk)),
              ],
            ),
    );
  }

  // â”€â”€â”€ Installments table â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _tableSection(_ComputedTable computed) {
    const headers = [
      'Cuota', 'Fecha', 'Capital', 'InterÃ©s', 'Total', 'Saldo Pendiente',
    ];
    const hStyle = pw.TextStyle();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: computed.rows,
      border: pw.TableBorder(
        bottom:           pw.BorderSide(color: _amBorder, width: 0.7),
        top:              pw.BorderSide(color: _amBorder, width: 0.7),
        left:             pw.BorderSide(color: _amBorder, width: 0.7),
        right:            pw.BorderSide(color: _amBorder, width: 0.7),
        horizontalInside: pw.BorderSide(color: _amBorder, width: 0.4),
        verticalInside:   pw.BorderSide(color: _amBorder, width: 0.4),
      ),
      cellStyle: pw.TextStyle(fontSize: 8.4, color: _amInk),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5.5),
      headerStyle: pw.TextStyle(
        fontSize: 8.0, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: _amAccent),
      rowDecoration: pw.BoxDecoration(color: _amSurface),
      oddRowDecoration: pw.BoxDecoration(color: PdfColors.white),
      oddCellStyle: pw.TextStyle(fontSize: 8.4, color: _amInk),
      columnWidths: const {
        0: pw.FixedColumnWidth(40),
        1: pw.FixedColumnWidth(72),
        2: pw.FlexColumnWidth(),
        3: pw.FlexColumnWidth(),
        4: pw.FlexColumnWidth(),
        5: pw.FlexColumnWidth(),
      },
    );
  }

  // â”€â”€â”€ Totals row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _totalsRow(_ComputedTable computed) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: pw.BoxDecoration(
        color: _amAccentLight,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _amBorder),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          _totalItem('Total capital',  _money(computed.totalCapital)),
          pw.Container(width: 0.8, height: 30, color: _amBorder),
          _totalItem('Total interÃ©s',  _money(computed.totalInterest)),
          pw.Container(width: 0.8, height: 30, color: _amBorder),
          _totalItem('Total a pagar',  _money(computed.totalAmount), accent: true),
        ],
      ),
    );
  }

  static pw.Widget _totalItem(String label, String value,
      {bool accent = false}) {
    return pw.Column(
      children: [
        pw.Text(label.toUpperCase(),
          style: pw.TextStyle(fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: accent ? _amAccent : _amMuted)),
        pw.SizedBox(height: 3),
        pw.Text(value,
          style: pw.TextStyle(
            fontSize: accent ? 11.0 : 9.5,
            fontWeight: pw.FontWeight.bold,
            color: accent ? _amSuccess : _amInk)),
      ],
    );
  }

  // â”€â”€â”€ Utilities â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<pw.Font> _loadFont(String path) async {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  }

  static pw.MemoryImage? _decodeLogo(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try { return pw.MemoryImage(base64Decode(b64)); } catch (_) { return null; }
  }

  static String _money(double v) => 'RD\$ ${formatRdCurrency(v)}';
}

// â”€â”€â”€ Supporting types â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SumItem {
  const _SumItem(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;
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

  factory _ComputedTable.fromDetail(SaleDetail detail) {
    final sale = detail.sale;
    final schedule = SaleCalculator.generateSchedule(
      financedBalance: sale.financedBalance,
      monthlyInterest: sale.monthlyInterest,
      installmentCount: sale.installmentCount,
    );

    double totalCapital  = 0;
    double totalInterest = 0;
    double totalAmount   = 0;
    double balance       = sale.financedBalance;

    final rows = <List<String>>[];
    DateTime cursor = sale.saleDate;

    for (var i = 0; i < schedule.length; i++) {
      final item = schedule[i];
      cursor = DateTime(cursor.year, cursor.month + 1, cursor.day);
      balance -= item.capitalPayment;
      if (balance < 0) balance = 0;
      totalCapital  += item.capitalPayment;
      totalInterest += item.interestPayment;
      totalAmount   += item.totalPayment;

      final day   = cursor.day.toString().padLeft(2, '0');
      final month = cursor.month.toString().padLeft(2, '0');

      rows.add([
        '${i + 1}',
        '$day/$month/${cursor.year}',
        'RD\$ ${formatRdCurrency(item.capitalPayment)}',
        'RD\$ ${formatRdCurrency(item.interestPayment)}',
        'RD\$ ${formatRdCurrency(item.totalPayment)}',
        'RD\$ ${formatRdCurrency(balance)}',
      ]);
    }

    return _ComputedTable(
      rows: rows,
      totalCapital: totalCapital,
      totalInterest: totalInterest,
      totalAmount: totalAmount,
    );
  }
}
