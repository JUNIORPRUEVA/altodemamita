import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/receipt.dart';

class ReceiptPdfBuilder {
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

  static Future<Uint8List> build(Receipt receipt) async {
    final baseFont = await _baseFontFuture;
    final boldFont = await _boldFontFuture;
    final logoImage = _decodeLogo(receipt.company.logoBytesBase64);

    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(20, 16, 20, 16),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(receipt, logoImage),
              pw.SizedBox(height: 10),
              _divider(),
              pw.SizedBox(height: 10),
              _sectionTitle('Informacion principal'),
              pw.SizedBox(height: 6),
              _documentGrid([
                _PdfField('Cliente', _textOrDash(receipt.sale.clientName)),
                _PdfField('Cedula', _textOrDash(receipt.sale.clientDocumentId)),
                _PdfField(
                  'Solar',
                  '${_textOrDash(receipt.blockNumber)} · ${_textOrDash(receipt.lotNumber)}',
                ),
                _PdfField('Venta asociada', '#${receipt.sale.saleId}'),
                _PdfField(
                  'Metodo de pago',
                  _textOrDash(receipt.paymentMethodLabel),
                ),
                _PdfField('Concepto', _textOrDash(receipt.paymentConcept)),
                _PdfField('Referencia', _paymentReference(receipt)),
                _PdfField('Recibido por', _textOrDash(receipt.receivedBy)),
                _PdfField('Entregado por', _textOrDash(receipt.deliveredBy)),
                _PdfField(
                  'Registrado por',
                  _textOrDash(receipt.paymentRegisteredByName),
                ),
                _PdfField(
                  'Estado actual',
                  _textOrDash(receipt.accountStatusLabel),
                ),
                _PdfField('Proxima cuota', _nextInstallmentLabel(receipt)),
              ], columns: 3),
              pw.SizedBox(height: 10),
              _sectionTitle('Detalle del pago'),
              pw.SizedBox(height: 6),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Expanded(
                      flex: 12,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _boxSection(
                            'Detalle del pago',
                            _detailSection(receipt),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Expanded(
                            child: _boxSection(
                              'Monto en letras y observaciones',
                              _narrativesSection(receipt),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      flex: 9,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _boxSection(
                            'Resumen financiero',
                            _summarySection(receipt),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Expanded(
                            child: _boxSection(
                              'Validacion y archivo',
                              _validationSection(receipt),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              _miniSummaryStrip(receipt),
              pw.SizedBox(height: 10),
              _divider(),
              pw.SizedBox(height: 9),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _signatureBlock(
                      'Entregado por',
                      _textOrDash(receipt.deliveredBy),
                    ),
                  ),
                  pw.SizedBox(width: 22),
                  pw.Expanded(
                    child: _signatureBlock(
                      'Recibido por',
                      _textOrDash(receipt.receivedBy),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'No aceptamos devoluciones',
                  style: pw.TextStyle(
                    fontSize: 7.4,
                    color: _mutedColor,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
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

  static pw.Widget _buildHeader(Receipt receipt, pw.MemoryImage? logoImage) {
    final companyName = receipt.company.nombre.trim().isEmpty
        ? 'Sistema de Solares'
        : receipt.company.nombre.trim();
    final companyPhone = (receipt.company.telefono ?? '').trim();
    final companyAddress = (receipt.company.direccion ?? '').trim();

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
              _logoBox(logoImage),
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
                        'Tel. $companyPhone',
                        style: pw.TextStyle(fontSize: 8.8, color: _mutedColor),
                      ),
                    ],
                    if (companyAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        companyAddress,
                        style: pw.TextStyle(
                          fontSize: 8.6,
                          color: _mutedColor,
                          lineSpacing: 1.22,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Container(
                width: 170,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: _borderColor),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _metaLine('Recibo no.', _textOrDash(receipt.receiptNumber)),
                    _metaLine('Fecha', receipt.formattedDateShort),
                    _metaLine(
                      'Monto',
                      'RD\$ ${receipt.formattedAmount}',
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
                  height: 34,
                  decoration: pw.BoxDecoration(
                    color: _accentColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Text(
                  'COMPROBANTE DE PAGO',
                  style: pw.TextStyle(
                    fontSize: 11.8,
                    fontWeight: pw.FontWeight.bold,
                    color: _accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _logoBox(pw.MemoryImage? logoImage) {
    return pw.Container(
      width: 54,
      height: 54,
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

  static pw.Widget _sectionTitle(String title) {
    return pw.Row(
      children: [
        pw.Container(width: 18, height: 1.3, color: _accentColor),
        pw.SizedBox(width: 8),
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8.4,
            fontWeight: pw.FontWeight.bold,
            color: _accentColor,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  static pw.Widget _documentGrid(
    List<_PdfField> items, {
    required int columns,
  }) {
    final normalized = List<_PdfField>.from(items);
    while (normalized.length % columns != 0) {
      normalized.add(const _PdfField('', ''));
    }

    final rows = <pw.TableRow>[];
    for (var index = 0; index < normalized.length; index += columns) {
      rows.add(
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            for (var column = 0; column < columns; column++)
              _gridCell(normalized[index + column]),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside: pw.BorderSide(color: _softBorderColor, width: 0.7),
        outside: pw.BorderSide(color: _borderColor, width: 0.8),
      ),
      children: rows,
    );
  }

  static pw.Widget _gridCell(_PdfField item) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: item.label.isEmpty
          ? pw.SizedBox()
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.label.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _mutedColor,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  item.value,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: item.highlight ? 10.2 : 9.0,
                    fontWeight: pw.FontWeight.bold,
                    color: item.highlight ? _successColor : _inkColor,
                    lineSpacing: 1.15,
                  ),
                ),
              ],
            ),
    );
  }

  static pw.Widget _boxSection(String title, pw.Widget child) {
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
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _surfaceTint,
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _accentColor,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  static pw.Widget _detailSection(Receipt receipt) {
    return pw.Column(
      children: [
        _paymentTableHeader(),
        pw.SizedBox(height: 4),
        ...receipt.paymentBreakdown.map(
          (entry) => _paymentLine(receipt, entry),
        ),
      ],
    );
  }

  static pw.Widget _paymentTableHeader() {
    final style = pw.TextStyle(
      fontSize: 7.7,
      fontWeight: pw.FontWeight.bold,
      color: _mutedColor,
    );

    return pw.Row(
      children: [
        pw.Expanded(flex: 10, child: pw.Text('CONCEPTO', style: style)),
        pw.Expanded(flex: 8, child: pw.Text('DETALLE', style: style)),
        pw.SizedBox(
          width: 96,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('MONTO', style: style),
          ),
        ),
      ],
    );
  }

  static pw.Widget _paymentLine(Receipt receipt, ReceiptLineItem entry) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _softBorderColor)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 10,
            child: pw.Text(
              entry.label,
              style: pw.TextStyle(
                fontSize: 9.1,
                fontWeight: pw.FontWeight.bold,
                color: _inkColor,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 8,
            child: pw.Text(
              _paymentDetailText(receipt),
              maxLines: 1,
              style: pw.TextStyle(fontSize: 8.4, color: _mutedColor),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.SizedBox(
            width: 96,
            child: pw.Text(
              'RD\$ ${entry.amount.toStringAsFixed(2)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9.2,
                fontWeight: pw.FontWeight.bold,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summarySection(Receipt receipt) {
    return pw.Column(
      children: [
        _documentGrid([
          _PdfField(
            'Pagado en recibo',
            'RD\$ ${receipt.formattedAmount}',
            highlight: true,
          ),
          _PdfField(
            'Balance actual',
            'RD\$ ${receipt.currentOutstandingBalance.toStringAsFixed(2)}',
          ),
          _PdfField(
            'Saldo financiado',
            'RD\$ ${receipt.remainingFinancedBalance.toStringAsFixed(2)}',
          ),
          _PdfField(
            'Inicial pendiente',
            'RD\$ ${receipt.remainingInitialBalance.toStringAsFixed(2)}',
          ),
          _PdfField(
            'Abonado acumulado',
            'RD\$ ${receipt.totalPaidAccumulated.toStringAsFixed(2)}',
          ),
          _PdfField('Estado actual', receipt.accountStatusLabel),
        ], columns: 2),
        pw.SizedBox(height: 8),
        _statusRow('Cuotas pagadas', '${receipt.installmentsPaid}'),
        _statusRow('Cuotas restantes', '${receipt.installmentsRemaining}'),
        _statusRow('Proxima cuota', _nextInstallmentLabel(receipt)),
        _statusRow(
          'Proximo vencimiento',
          receipt.nextInstallmentDueDate == null
              ? '-'
              : receipt.formatShortDate(receipt.nextInstallmentDueDate!),
        ),
        _statusRow('Aplicacion', _textOrDash(receipt.paymentConcept)),
      ],
    );
  }

  static pw.Widget _statusRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.7,
                fontWeight: pw.FontWeight.bold,
                color: _mutedColor,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 9.0,
                fontWeight: pw.FontWeight.bold,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _narrativesSection(Receipt receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _narrativeBox(
          'Monto en letras',
          receipt.amountInWords.toUpperCase(),
          emphasize: true,
          maxLines: 3,
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _narrativeBox(
                'Observacion',
                _textOrDash(receipt.note),
                maxLines: 5,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _narrativeBox(
                'Condiciones',
                _textOrDash(receipt.conditionsOfPayment),
                maxLines: 5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _narrativeBox(
    String label,
    String value, {
    bool emphasize = false,
    required int maxLines,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.7,
            fontWeight: pw.FontWeight.bold,
            color: _mutedColor,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _surfaceTint,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: _softBorderColor),
          ),
          child: pw.Text(
            value,
            maxLines: maxLines,
            style: pw.TextStyle(
              fontSize: emphasize ? 9.4 : 8.7,
              fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _inkColor,
              lineSpacing: 1.22,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _validationSection(Receipt receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _validationLine('Recibimos de', _textOrDash(receipt.receivedFrom)),
        _validationLine('Recibido por', _textOrDash(receipt.receivedBy)),
        _validationLine('Entregado por', _textOrDash(receipt.deliveredBy)),
        _validationLine('Venta', '#${receipt.sale.saleId}'),
      ],
    );
  }

  static pw.Widget _miniSummaryStrip(Receipt receipt) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _miniSummaryItem(
              'Balance actual',
              'RD\$ ${receipt.currentOutstandingBalance.toStringAsFixed(2)}',
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _miniSummaryItem(
              'Saldo financiado',
              'RD\$ ${receipt.remainingFinancedBalance.toStringAsFixed(2)}',
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _miniSummaryItem(
              'Estado',
              _textOrDash(receipt.accountStatusLabel),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _miniSummaryItem(String label, String value) {
    return pw.Column(
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
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9.4,
            fontWeight: pw.FontWeight.bold,
            color: _inkColor,
          ),
        ),
      ],
    );
  }

  static pw.Widget _validationLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7.7,
              fontWeight: pw.FontWeight.bold,
              color: _mutedColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            maxLines: 2,
            style: pw.TextStyle(
              fontSize: 9.0,
              fontWeight: pw.FontWeight.bold,
              color: _inkColor,
              lineSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 1, color: _inkColor),
        pw.SizedBox(height: 7),
        pw.Text(
          value,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9.2,
            fontWeight: pw.FontWeight.bold,
            color: _inkColor,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          label.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 7.8,
            fontWeight: pw.FontWeight.bold,
            color: _mutedColor,
          ),
        ),
      ],
    );
  }

  static pw.Widget _divider() {
    return pw.Container(height: 1, color: _borderColor);
  }

  static String _paymentReference(Receipt receipt) {
    final reference = (receipt.payment.reference ?? '').trim();
    return reference.isEmpty ? '-' : reference;
  }

  static String _paymentDetailText(Receipt receipt) {
    final reference = _paymentReference(receipt);
    if (reference == '-') {
      return _textOrDash(receipt.paymentMethodLabel);
    }
    return '${_textOrDash(receipt.paymentMethodLabel)} · $reference';
  }

  static String _nextInstallmentLabel(Receipt receipt) {
    final installmentNumber = receipt.nextInstallmentNumber;
    final installmentAmount = receipt.nextInstallmentAmount;
    if (installmentNumber == null || installmentAmount == null) {
      return '-';
    }
    return '#$installmentNumber · RD\$ ${installmentAmount.toStringAsFixed(2)}';
  }

  static String _textOrDash(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? '-' : normalized;
  }
}

class _PdfField {
  const _PdfField(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}
