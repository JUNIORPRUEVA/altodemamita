import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/dominican_formatters.dart';
import '../../domain/receipt.dart';

// ─── Shared brand tokens ───────────────────────────────────────────────────
final _kAccent      = PdfColor.fromHex('#1B3F7A');
final _kAccentDark  = PdfColor.fromHex('#163168');
final _kAccentLight = PdfColor.fromHex('#E8EFFA');
final _kInk         = PdfColor.fromHex('#0F1E2E');
final _kMuted       = PdfColor.fromHex('#5C6E82');
final _kSurface     = PdfColor.fromHex('#F5F8FC');
final _kBorder      = PdfColor.fromHex('#CDD8E6');
final _kSoftBorder  = PdfColor.fromHex('#E2EAF4');
final _kSuccess     = PdfColor.fromHex('#0A5C3E');
final _kSubtle      = PdfColor.fromHex('#B8CCEC');
final _kGreenTint   = PdfColor.fromHex('#7EE8B8');

// ─── ReceiptPdfBuilder ─────────────────────────────────────────────────────
class ReceiptPdfBuilder {
  static final Future<pw.Font> _baseFontFuture = _loadFont(
    'assets/fonts/NotoSans-Regular.ttf',
  );
  static final Future<pw.Font> _boldFontFuture = _loadFont(
    'assets/fonts/NotoSans-Bold.ttf',
  );

  /// Builds a two-page document: landscape (portrait fallback) on one PDF.
  static Future<Uint8List> build(Receipt receipt) async {
    final base = await _baseFontFuture;
    final bold = await _boldFontFuture;
    final logo = _decodeLogo(receipt.company.logoBytesBase64);

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: base, bold: bold),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 20),
        build: (ctx) => _buildContent(ctx, receipt, logo),
      ),
    );

    return doc.save();
  }

  // ─── Main page layout ────────────────────────────────────────────────────
  static pw.Widget _buildContent(
    pw.Context ctx,
    Receipt receipt,
    pw.MemoryImage? logo,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _header(receipt, logo),
        pw.SizedBox(height: 12),
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Left (60 %) ────────────────────────────────────────────
              pw.Expanded(
                flex: 60,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _card(
                      title: 'Información del cliente y operación',
                      child: _clientGrid(receipt),
                    ),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: _card(
                        title: 'Detalle del pago',
                        child: _paymentTable(receipt),
                      ),
                    ),
                    pw.SizedBox(height: 9),
                    _amountInWords(receipt),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              // ── Right (40 %) ───────────────────────────────────────────
              pw.Expanded(
                flex: 40,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _card(
                      title: 'Resumen financiero',
                      child: _financialGrid(receipt),
                    ),
                    pw.SizedBox(height: 9),
                    pw.Expanded(
                      child: _card(
                        title: 'Próximas cuotas y estado',
                        child: _installmentStatus(receipt),
                      ),
                    ),
                    pw.SizedBox(height: 9),
                    _card(
                      title: 'Validación',
                      child: _validationPanel(receipt),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        _footerSignatures(receipt),
      ],
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────
  static pw.Widget _header(Receipt receipt, pw.MemoryImage? logo) {
    final co = receipt.company;
    final name = co.nombre.trim().isEmpty ? 'Sistema de Solares' : co.nombre.trim();
    final phone   = (co.telefono  ?? '').trim();
    final address = (co.direccion ?? '').trim();

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _kAccent,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        children: [
          // Top band
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
                      : pw.Center(
                          child: pw.Text('LOGO',
                            style: pw.TextStyle(fontSize: 7,
                              fontWeight: pw.FontWeight.bold, color: _kAccent)),
                        ),
                ),
                pw.SizedBox(width: 12),
                // Company details
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
                          style: pw.TextStyle(fontSize: 8.4, color: _kSubtle)),
                      ],
                      if (address.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(address,
                          style: pw.TextStyle(fontSize: 8.2, color: _kSubtle)),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                // Meta box
                pw.Container(
                  width: 165,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: _kAccentDark,
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _wMeta('Recibo', _d(receipt.receiptNumber)),
                      pw.SizedBox(height: 4),
                      _wMeta('Fecha', receipt.formattedDateShort),
                      pw.SizedBox(height: 4),
                      _wMeta('Monto pagado',
                        'RD\$ ${receipt.formattedAmount}',
                        highlight: true),
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
              color: _kAccentDark,
              borderRadius: const pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(12),
                bottomRight: pw.Radius.circular(12),
              ),
            ),
            child: pw.Text('COMPROBANTE DE PAGO',
              style: pw.TextStyle(fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 1.8)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _wMeta(String label, String value,
      {bool highlight = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label.toUpperCase(),
          style: pw.TextStyle(fontSize: 6.8,
            fontWeight: pw.FontWeight.bold, color: _kSubtle)),
        pw.SizedBox(height: 1),
        pw.Text(value,
          style: pw.TextStyle(
            fontSize: highlight ? 10.4 : 8.8,
            fontWeight: pw.FontWeight.bold,
            color: highlight ? _kGreenTint : PdfColors.white)),
      ],
    );
  }

  // ─── Card wrapper ─────────────────────────────────────────────────────────
  static pw.Widget _card({required String title, required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _kBorder),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _kAccentLight,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(title.toUpperCase(),
              style: pw.TextStyle(fontSize: 7.2,
                fontWeight: pw.FontWeight.bold, color: _kAccent,
                letterSpacing: 0.4)),
          ),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  // ─── Client info grid ─────────────────────────────────────────────────────
  static pw.Widget _clientGrid(Receipt receipt) {
    return _grid([
      _F('Cliente',      _d(receipt.sale.clientName)),
      _F('Cédula',       _d(receipt.sale.clientDocumentId)),
      _F('Solar',        _solarLabel(receipt)),
      _F('Venta',        '#${receipt.sale.saleId}'),
      _F('Concepto',     _d(receipt.paymentConcept)),
      _F('Método pago',  _d(receipt.paymentMethodLabel)),
      _F('Referencia',   _ref(receipt)),
      _F('Recibido por', _d(receipt.receivedBy)),
      _F('Registrado por', _d(receipt.paymentRegisteredByName)),
      _F('Recibimos de', _d(receipt.receivedFrom)),
      _F('Estado cuenta', _d(receipt.accountStatusLabel)),
      _F('Entregado por', _d(receipt.deliveredBy)),
    ], columns: 3);
  }

  // ─── Payment detail table ─────────────────────────────────────────────────
  static pw.Widget _paymentTable(Receipt receipt) {
    final hStyle = pw.TextStyle(
      fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _kMuted);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header row
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          color: _kSurface,
          child: pw.Row(children: [
            pw.Expanded(flex: 5, child: pw.Text('CONCEPTO', style: hStyle)),
            pw.Expanded(flex: 6, child: pw.Text('DETALLE',  style: hStyle)),
            pw.SizedBox(width: 88,
              child: pw.Align(alignment: pw.Alignment.centerRight,
                child: pw.Text('MONTO', style: hStyle))),
          ]),
        ),
        pw.Container(height: 0.5, color: _kBorder),
        ...receipt.paymentBreakdown.map((entry) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5.5),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _kSoftBorder, width: 0.5))),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 5,
                child: pw.Text(entry.label,
                  style: pw.TextStyle(fontSize: 9,
                    fontWeight: pw.FontWeight.bold, color: _kInk))),
              pw.Expanded(flex: 6,
                child: pw.Text(_detailText(receipt), maxLines: 1,
                  style: pw.TextStyle(fontSize: 8.4, color: _kMuted))),
              pw.SizedBox(width: 88,
                child: pw.Text(_money(entry.amount),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: 9.2,
                    fontWeight: pw.FontWeight.bold, color: _kInk))),
            ],
          ),
        )),
        pw.Container(height: 0.8, color: _kBorder),
        // Total row
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: _kAccentLight,
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Text('TOTAL PAGADO',
                style: pw.TextStyle(fontSize: 8.4,
                  fontWeight: pw.FontWeight.bold, color: _kAccent))),
            pw.Text('RD\$ ${receipt.formattedAmount}',
              style: pw.TextStyle(fontSize: 10.6,
                fontWeight: pw.FontWeight.bold, color: _kSuccess)),
          ]),
        ),
      ],
    );
  }

  // ─── Amount in words ──────────────────────────────────────────────────────
  static pw.Widget _amountInWords(Receipt receipt) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _kAccentLight,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _kBorder),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('MONTO EN LETRAS',
            style: pw.TextStyle(fontSize: 7.3,
              fontWeight: pw.FontWeight.bold, color: _kAccent)),
          pw.SizedBox(height: 4),
          pw.Text(receipt.amountInWords.toUpperCase(),
            style: pw.TextStyle(fontSize: 9.4,
              fontWeight: pw.FontWeight.bold, color: _kInk,
              lineSpacing: 1.3)),
          if ((receipt.note ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('OBSERVACIÓN',
              style: pw.TextStyle(fontSize: 7.3,
                fontWeight: pw.FontWeight.bold, color: _kMuted)),
            pw.SizedBox(height: 3),
            pw.Text(receipt.note!.trim(),
              style: pw.TextStyle(fontSize: 8.8, color: _kInk,
                lineSpacing: 1.3)),
          ],
        ],
      ),
    );
  }

  // ─── Financial grid ───────────────────────────────────────────────────────
  static pw.Widget _financialGrid(Receipt receipt) {
    return _grid([
      _F('Pagado en recibo',    'RD\$ ${receipt.formattedAmount}', highlight: true),
      _F('Balance actual',      _money(receipt.currentOutstandingBalance)),
      _F('Saldo pendiente del plan', _money(receipt.remainingFinancedBalance)),
      _F('Inicial pendiente',   _money(receipt.remainingInitialBalance)),
      _F('Total pagado acum.',  _money(receipt.totalPaidAccumulated)),
      _F('Estado de cuenta',    _d(receipt.accountStatusLabel)),
    ], columns: 2);
  }

  // ─── Installment status ───────────────────────────────────────────────────
  static pw.Widget _installmentStatus(Receipt receipt) {
    final next = receipt.nextInstallmentNumber;
    final amt  = receipt.nextInstallmentAmount;
    final due  = receipt.nextInstallmentDueDate;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _kv('Cuotas pagadas',     '${receipt.installmentsPaid}'),
        _kv('Cuotas restantes',   '${receipt.installmentsRemaining}'),
        _kv('Próxima cuota',       next == null ? '-' : '#$next'),
        _kv('Monto próx. cuota',   amt  == null ? '-' : _money(amt)),
        _kv('Fecha vencimiento',
          due == null ? '-' : receipt.formatShortDate(due)),
        _kv('Aplicación',         _d(receipt.paymentConcept)),
      ],
    );
  }

  // ─── Validation panel ─────────────────────────────────────────────────────
  static pw.Widget _validationPanel(Receipt receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _kv('Recibimos de', _d(receipt.receivedFrom)),
        _kv('Recibido por', _d(receipt.receivedBy)),
        _kv('Entregado por', _d(receipt.deliveredBy)),
        _kv('No. de venta', '#${receipt.sale.saleId}'),
      ],
    );
  }

  // ─── Footer signatures ────────────────────────────────────────────────────
  static pw.Widget _footerSignatures(Receipt receipt) {
    return pw.Column(
      children: [
        pw.Container(height: 0.8, color: _kBorder),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Expanded(
            child: _signBlock('Entregado por', _d(receipt.deliveredBy))),
          pw.SizedBox(width: 32),
          pw.Expanded(
            child: _signBlock('Recibido por / Firma del cliente',
              _d(receipt.receivedBy))),
        ]),
        pw.SizedBox(height: 7),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'No se aceptan devoluciones  ·  Comprobante válido con firma y sello.',
            style: pw.TextStyle(fontSize: 7.2, color: _kMuted)),
        ),
      ],
    );
  }

  static pw.Widget _signBlock(String label, String name) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 0.8, color: _kInk),
        pw.SizedBox(height: 5),
        pw.Text(name, textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 9,
            fontWeight: pw.FontWeight.bold, color: _kInk)),
        pw.SizedBox(height: 2),
        pw.Text(label.toUpperCase(), textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 7.4,
            fontWeight: pw.FontWeight.bold, color: _kMuted)),
      ],
    );
  }

  // ─── Shared grid ─────────────────────────────────────────────────────────
  static pw.Widget _grid(List<_F> fields, {required int columns}) {
    final items = List<_F>.from(fields);
    while (items.length % columns != 0) items.add(const _F('', ''));
    final rows = <pw.TableRow>[];
    for (var i = 0; i < items.length; i += columns) {
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          for (var c = 0; c < columns; c++) _gridCell(items[i + c]),
        ],
      ));
    }
    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside:  pw.BorderSide(color: _kSoftBorder, width: 0.6),
        outside: pw.BorderSide(color: _kBorder,     width: 0.7),
      ),
      children: rows,
    );
  }

  static pw.Widget _gridCell(_F f) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: f.label.isEmpty
          ? pw.SizedBox()
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(f.label.toUpperCase(),
                  style: pw.TextStyle(fontSize: 7.2,
                    fontWeight: pw.FontWeight.bold, color: _kMuted)),
                pw.SizedBox(height: 2),
                pw.Text(f.value, maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: f.highlight ? 10.2 : 8.9,
                    fontWeight: pw.FontWeight.bold,
                    color: f.highlight ? _kSuccess : _kInk,
                    lineSpacing: 1.15)),
              ],
            ),
    );
  }

  static pw.Widget _kv(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 108,
            child: pw.Text(label,
              style: pw.TextStyle(fontSize: 8.4, color: _kMuted,
                fontWeight: pw.FontWeight.bold))),
          pw.Expanded(
            child: pw.Text(value, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 8.8,
                fontWeight: pw.FontWeight.bold, color: _kInk))),
        ],
      ),
    );
  }

  // ─── Utilities ────────────────────────────────────────────────────────────
  static Future<pw.Font> _loadFont(String path) async {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  }

  static pw.MemoryImage? _decodeLogo(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try { return pw.MemoryImage(base64Decode(b64)); } catch (_) { return null; }
  }

  static String _solarLabel(Receipt receipt) {
    final blk = (receipt.blockNumber ?? '').trim();
    final lot = (receipt.lotNumber   ?? '').trim();
    return (blk.isEmpty && lot.isEmpty) ? '-' : 'M$blk-S$lot';
  }

  static String _ref(Receipt receipt) {
    final r = (receipt.payment.reference ?? '').trim();
    return r.isEmpty ? '-' : r;
  }

  static String _detailText(Receipt receipt) {
    final m = _d(receipt.paymentMethodLabel);
    final r = _ref(receipt);
    return r == '-' ? m : '$m · $r';
  }

  static String _money(double v) => 'RD\$ ${formatRdCurrency(v)}';
  static String _d(String? v) {
    final s = (v ?? '').trim(); return s.isEmpty ? '-' : s;
  }
}

class _F {
  const _F(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;
}
