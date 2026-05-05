import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/utils/dominican_formatters.dart';
import '../../../settings/domain/company_info.dart';
import '../../domain/sale_detail.dart';

// â”€â”€â”€ Brand tokens (same palette as receipt_pdf_builder) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
final _siAccent      = PdfColor.fromHex('#1B3F7A');
final _siAccentDark  = PdfColor.fromHex('#163168');
final _siAccentLight = PdfColor.fromHex('#E8EFFA');
final _siInk         = PdfColor.fromHex('#0F1E2E');
final _siMuted       = PdfColor.fromHex('#5C6E82');
final _siSurface     = PdfColor.fromHex('#F5F8FC');
final _siBorder      = PdfColor.fromHex('#CDD8E6');
final _siSoftBorder  = PdfColor.fromHex('#E2EAF4');
final _siSuccess     = PdfColor.fromHex('#0A5C3E');
final _siSubtle      = PdfColor.fromHex('#B8CCEC');

class SaleInitialReceiptPdfBuilder {
  static PdfPageFormat get pageFormat => PdfPageFormat.letter.landscape;

  static Future<Uint8List> build({
    required SaleDetail detail,
    required CompanyInfo company,
    PdfPageFormat? pageFormat,
  }) async {
    final fmt      = pageFormat ?? SaleInitialReceiptPdfBuilder.pageFormat;
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pw.MemoryImage? logo;
    final b64 = company.logoBytesBase64;
    if (b64 != null && b64.isNotEmpty) {
      try { logo = pw.MemoryImage(base64Decode(b64)); } catch (_) { logo = null; }
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.fromLTRB(
        fmt.width > fmt.height ? 22 : 18, 18,
        fmt.width > fmt.height ? 22 : 18, 20),
      build: (_) => _buildPage(detail, company, logo),
    ));

    return doc.save();
  }

  // â”€â”€â”€ Main page layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _buildPage(
    SaleDetail detail,
    CompanyInfo company,
    pw.MemoryImage? logo,
  ) {
    final sale = detail.sale;
    final first  = detail.installments.isEmpty ? null : detail.installments.first;
    final estAmt = first?.totalAmount ??
        (sale.installmentCount > 0
            ? sale.financedBalance / sale.installmentCount
            : 0.0);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        _header(company, logo, sale.id ?? 0, sale.saleDate),
        pw.SizedBox(height: 12),
        // â”€â”€ Two-column body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left column â€“ client + sale data
              pw.Expanded(
                flex: 55,
                child: pw.Column(
                  children: [
                    _card('Datos del cliente', _clientGrid(detail)),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: _card('Condiciones de venta',
                        _saleConditionsGrid(sale, detail, estAmt)),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              // Right column â€“ financials + payment breakdown
              pw.Expanded(
                flex: 45,
                child: pw.Column(
                  children: [
                    _card('Resumen financiero',
                      _financialGrid(sale, detail, estAmt)),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: _card('InformaciÃ³n de la transacciÃ³n',
                        _transactionGrid(detail)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        _footer(),
      ],
    );
  }

  // â”€â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _header(
    CompanyInfo co,
    pw.MemoryImage? logo,
    int saleId,
    DateTime saleDate,
  ) {
    final name    = co.nombre.trim().isEmpty ? 'Sistema de Solares' : co.nombre.trim();
    final phone   = (co.telefono  ?? '').trim();
    final address = (co.direccion ?? '').trim();

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _siAccent,
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
                            fontWeight: pw.FontWeight.bold, color: _siAccent))),
                ),
                pw.SizedBox(width: 12),
                // Company info
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(name,
                        style: pw.TextStyle(fontSize: 15,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                      if (phone.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text('Tel. $phone',
                          style: pw.TextStyle(fontSize: 8.4, color: _siSubtle)),
                      ],
                      if (address.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(address,
                          style: pw.TextStyle(fontSize: 8.2, color: _siSubtle)),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                // Sale meta box
                pw.Container(
                  width: 165,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: _siAccentDark,
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _wMeta('Venta',  '#$saleId'),
                      pw.SizedBox(height: 5),
                      _wMeta('Fecha',  _fmtDate(saleDate)),
                      pw.SizedBox(height: 5),
                      _wMeta('Documento', 'RECIBO DE INICIAL'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Banner
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: pw.BoxDecoration(
              color: _siAccentDark,
              borderRadius: const pw.BorderRadius.only(
                bottomLeft:  pw.Radius.circular(12),
                bottomRight: pw.Radius.circular(12),
              ),
            ),
            child: pw.Text('RECIBO DE INICIAL â€” CONTRATO DE VENTA',
              style: pw.TextStyle(fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white, letterSpacing: 1.6)),
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
            fontWeight: pw.FontWeight.bold, color: _siSubtle)),
        pw.SizedBox(height: 1),
        pw.Text(value,
          style: pw.TextStyle(fontSize: 8.8,
            fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      ],
    );
  }

  // â”€â”€â”€ Card wrapper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _card(String title, pw.Widget child) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _siBorder),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _siAccentLight,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(title.toUpperCase(),
              style: pw.TextStyle(fontSize: 7.2,
                fontWeight: pw.FontWeight.bold,
                color: _siAccent, letterSpacing: 0.4)),
          ),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  // â”€â”€â”€ Client grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _clientGrid(SaleDetail detail) {
    final sale = detail.sale;
    return _grid([
      _F('Cliente',     detail.clientName),
      _F('CÃ©dula',      detail.clientDocumentId),
      _F('Vendedor',    detail.sellerName ?? '-'),
      _F('Solar',       detail.lotDisplayCode),
      _F('CÃ©dula vendedor', detail.sellerDocumentId ?? '-'),
      _F('TelÃ©fono vendedor', detail.sellerPhone ?? '-'),
      _F('Ãrea del solar', '${detail.lotArea.toStringAsFixed(2)} mÂ²'),
      _F('Precio por mÂ²', _money(detail.lotPricePerSquareMeter)),
      _F('Precio total solar', _money(sale.salePrice), highlight: true),
    ], columns: 3);
  }

  // â”€â”€â”€ Sale conditions grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _saleConditionsGrid(
    dynamic sale,
    SaleDetail detail,
    double estAmt,
  ) {
    final rows = [
      _F('Fecha de venta',       _fmtDate(sale.saleDate)),
      _F('MÃ©todo primer pago',   _fmtMethod(detail.initialPaymentMethod)),
      _F('InterÃ©s mensual',      '${sale.monthlyInterest.toStringAsFixed(2)}%'),
      _F('Cantidad de cuotas',   '${sale.installmentCount}'),
      _F('Cuota fija estimada',  _money(estAmt), highlight: true),
      if (sale.initialPaymentDeadline != null)
        _F('Fecha lÃ­mite inicial', _fmtDate(sale.initialPaymentDeadline!)),
    ];
    return _grid(rows, columns: 3);
  }

  // â”€â”€â”€ Financial grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _financialGrid(
    dynamic sale,
    SaleDetail detail,
    double estAmt,
  ) {
    return _grid([
      _F('Inicial mÃ­nimo requerido', _money(sale.requiredInitialPayment)),
      _F('Inicial real pagado',      _money(sale.paidInitialPayment), highlight: true),
      _F('Inicial pendiente',        _money(sale.pendingInitialPayment)),
      _F('Saldo financiado',         _money(sale.financedBalance),    highlight: true),
      _F('Saldo pendiente',          _money(sale.pendingBalance)),
      _F('Cuota fija estimada',      _money(estAmt)),
    ], columns: 2);
  }

  // â”€â”€â”€ Transaction grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _transactionGrid(SaleDetail detail) {
    return _grid([
      _F('Registrado por',    detail.userName),
      _F('MÃ©todo de pago',    _fmtMethod(detail.initialPaymentMethod)),
      _F('Solar',             detail.lotDisplayCode),
      _F('Ãrea del solar',    '${detail.lotArea.toStringAsFixed(2)} mÂ²'),
    ], columns: 2);
  }

  // â”€â”€â”€ Footer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _footer() {
    return pw.Column(
      children: [
        pw.Container(height: 0.8, color: _siBorder),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Expanded(child: _signLine('Firma del cliente')),
          pw.SizedBox(width: 32),
          pw.Expanded(child: _signLine('Firma autorizado / Vendedor')),
        ]),
        pw.SizedBox(height: 7),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'No se aceptan devoluciones  Â·  Este documento tiene validez legal con ambas firmas.',
            style: pw.TextStyle(fontSize: 7.2, color: _siMuted)),
        ),
      ],
    );
  }

  static pw.Widget _signLine(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 0.8, color: _siInk),
        pw.SizedBox(height: 5),
        pw.Text(label.toUpperCase(), textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 7.6,
            fontWeight: pw.FontWeight.bold, color: _siMuted)),
      ],
    );
  }

  // â”€â”€â”€ Shared grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _grid(List<_F> fields, {required int columns}) {
    final items = List<_F>.from(fields);
    while (items.length % columns != 0) items.add(const _F('', ''));
    final rows = <pw.TableRow>[];
    for (var i = 0; i < items.length; i += columns) {
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          for (var c = 0; c < columns; c++) _cell(items[i + c]),
        ],
      ));
    }
    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside:  pw.BorderSide(color: _siSoftBorder, width: 0.6),
        outside: pw.BorderSide(color: _siBorder,     width: 0.7),
      ),
      children: rows,
    );
  }

  static pw.Widget _cell(_F f) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: f.label.isEmpty
          ? pw.SizedBox()
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(f.label.toUpperCase(),
                  style: pw.TextStyle(fontSize: 7.2,
                    fontWeight: pw.FontWeight.bold, color: _siMuted)),
                pw.SizedBox(height: 2),
                pw.Text(f.value, maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: f.highlight ? 10.2 : 9.0,
                    fontWeight: pw.FontWeight.bold,
                    color: f.highlight ? _siSuccess : _siInk,
                    lineSpacing: 1.15)),
              ],
            ),
    );
  }

  // â”€â”€â”€ Utilities â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static String _money(double v) => 'RD\$ ${formatRdCurrency(v)}';

  static String _fmtDate(DateTime d) {
    final day   = d.day.toString().padLeft(2,   '0');
    final month = d.month.toString().padLeft(2,  '0');
    return '$day/$month/${d.year}';
  }

  static String _fmtMethod(String v) {
    switch (v.trim().toLowerCase()) {
      case 'transferencia': return 'Transferencia';
      case 'cheque':        return 'Cheque';
      case 'tarjeta':       return 'Tarjeta';
      default:              return 'Efectivo';
    }
  }
}

class _F {
  const _F(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;
}
