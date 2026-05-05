import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/utils/dominican_formatters.dart';
import '../../domain/receipt.dart';

class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.receipt});

  static const double documentWidth = 1120;
  static const double documentHeight = 866;
  static const double documentAspectRatio = documentWidth / documentHeight;

  static const Color _canvasColor = Color(0xFFF3F6F9);
  static const Color _borderColor = Color(0xFFD8E0E8);
  static const Color _softBorderColor = Color(0xFFE7EDF4);
  static const Color _surfaceTint = Color(0xFFF4F7FB);
  static const Color _accentColor = Color(0xFF234A84);
  static const Color _inkColor = Color(0xFF172433);
  static const Color _mutedColor = Color(0xFF667788);
  static const Color _successColor = Color(0xFF0E6B4C);

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : documentWidth;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : documentHeight;
        final scale = math
            .min(width / documentWidth, height / documentHeight)
            .clamp(0.52, 1.0);

        return DecoratedBox(
          decoration: const BoxDecoration(color: _canvasColor),
          child: Padding(
            padding: EdgeInsets.all(8 * scale),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18 * scale),
                border: Border.all(color: _borderColor),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18 * scale,
                  16 * scale,
                  18 * scale,
                  14 * scale,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(scale),
                    SizedBox(height: 10 * scale),
                    _buildDivider(scale),
                    SizedBox(height: 10 * scale),
                    _buildSectionTitle('Informacion principal', scale),
                    SizedBox(height: 6 * scale),
                    _buildDocumentGrid(
                      [
                        _FieldItem(
                          'Cliente',
                          _textOrDash(receipt.sale.clientName),
                        ),
                        _FieldItem(
                          'Cedula',
                          _textOrDash(receipt.sale.clientDocumentId),
                        ),
                        _FieldItem(
                          'Solar',
                          '${_textOrDash(receipt.blockNumber)} · ${_textOrDash(receipt.lotNumber)}',
                        ),
                        _FieldItem('Venta asociada', '#${receipt.sale.saleId}'),
                        _FieldItem('Fecha', receipt.formattedDateShort),
                        _FieldItem(
                          'Metodo de pago',
                          _textOrDash(receipt.paymentMethodLabel),
                        ),
                        _FieldItem('Referencia', _paymentReference),
                        _FieldItem(
                          'Monto pagado',
                          'RD\$ ${receipt.formattedAmount}',
                          highlight: true,
                        ),
                        _FieldItem(
                          'Concepto',
                          _textOrDash(receipt.paymentConcept),
                        ),
                        _FieldItem(
                          'Recibo no.',
                          _textOrDash(receipt.receiptNumber),
                        ),
                        _FieldItem(
                          'Recibido por',
                          _textOrDash(receipt.receivedBy),
                        ),
                        _FieldItem(
                          'Entregado por',
                          _textOrDash(receipt.deliveredBy),
                        ),
                      ],
                      scale,
                      columns: 3,
                    ),
                    SizedBox(height: 10 * scale),
                    _buildSectionTitle('Detalle y resumen', scale),
                    SizedBox(height: 6 * scale),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildBoxSection(
                                    'Detalle del pago',
                                    scale,
                                    _buildDetailSection(scale),
                                  ),
                                ),
                                SizedBox(height: 10 * scale),
                                Expanded(
                                  flex: 4,
                                  child: _buildBoxSection(
                                    'Monto en letras y observaciones',
                                    scale,
                                    _buildNarrativesSection(scale),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 12 * scale),
                          Expanded(
                            flex: 9,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildBoxSection(
                                    'Resumen financiero',
                                    scale,
                                    _buildSummarySection(scale),
                                  ),
                                ),
                                SizedBox(height: 10 * scale),
                                Expanded(
                                  flex: 4,
                                  child: _buildBoxSection(
                                    'Validacion y archivo',
                                    scale,
                                    _buildValidationSection(scale),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10 * scale),
                    _buildDivider(scale),
                    SizedBox(height: 9 * scale),
                    _buildSignatureStrip(scale),
                    SizedBox(height: 6 * scale),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'No aceptamos devoluciones',
                        style: TextStyle(
                          fontSize: 7.6 * scale,
                          color: _mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String get _paymentReference {
    final reference = (receipt.payment.reference ?? '').trim();
    return reference.isEmpty ? '-' : reference;
  }

  Widget _buildHeader(double scale) {
    final logoBytes = _tryDecodeBase64(receipt.company.logoBytesBase64);
    final companyName = receipt.company.nombre.trim().isEmpty
        ? 'Sistema de Solares'
        : receipt.company.nombre.trim();
    final companyPhone = (receipt.company.telefono ?? '').trim();
    final companyAddress = (receipt.company.direccion ?? '').trim();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogo(logoBytes, scale),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPROBANTE DE PAGO',
                      style: TextStyle(
                        fontSize: 14.6 * scale,
                        fontWeight: FontWeight.w800,
                        color: _accentColor,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      'Documento de cobro para archivo, impresion y exportacion PDF.',
                      style: TextStyle(
                        fontSize: 8.2 * scale,
                        color: _mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12 * scale),
              Container(
                width: 170 * scale,
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: BorderRadius.circular(12 * scale),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMetaLine(
                      'Recibo no.',
                      _textOrDash(receipt.receiptNumber),
                      scale,
                    ),
                    _buildMetaLine('Fecha', receipt.formattedDateShort, scale),
                    _buildMetaLine(
                      'Monto',
                      'RD\$ ${receipt.formattedAmount}',
                      scale,
                      highlight: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companyName,
                  style: TextStyle(
                    fontSize: 13.8 * scale,
                    fontWeight: FontWeight.w800,
                    color: _inkColor,
                  ),
                ),
                if (companyPhone.isNotEmpty) ...[
                  SizedBox(height: 4 * scale),
                  Text(
                    'Tel. $companyPhone',
                    style: TextStyle(fontSize: 8.8 * scale, color: _mutedColor),
                  ),
                ],
                if (companyAddress.isNotEmpty) ...[
                  SizedBox(height: 3 * scale),
                  Text(
                    companyAddress,
                    style: TextStyle(
                      fontSize: 8.6 * scale,
                      color: _mutedColor,
                      height: 1.22,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(Uint8List? logoBytes, double scale) {
    return Container(
      width: 54 * scale,
      height: 54 * scale,
      padding: EdgeInsets.all(7 * scale),
      decoration: BoxDecoration(
        color: _surfaceTint,
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: _borderColor),
      ),
      child: logoBytes == null || logoBytes.isEmpty
          ? Center(
              child: Icon(
                Icons.business_outlined,
                size: 22 * scale,
                color: _accentColor,
              ),
            )
          : Image.memory(
              logoBytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.business_outlined,
                  size: 22 * scale,
                  color: _accentColor,
                );
              },
            ),
    );
  }

  Widget _buildMetaLine(
    String label,
    String value,
    double scale, {
    bool highlight = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 5 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 7.4 * scale,
              fontWeight: FontWeight.w700,
              color: _mutedColor,
            ),
          ),
          SizedBox(height: 2 * scale),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 9.8 * scale : 8.9 * scale,
              fontWeight: FontWeight.w800,
              color: highlight ? _successColor : _inkColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, double scale) {
    return Row(
      children: [
        Container(width: 18 * scale, height: 1.3 * scale, color: _accentColor),
        SizedBox(width: 8 * scale),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 8.4 * scale,
            fontWeight: FontWeight.w800,
            color: _accentColor,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentGrid(
    List<_FieldItem> items,
    double scale, {
    required int columns,
  }) {
    final normalized = List<_FieldItem>.from(items);
    while (normalized.length % columns != 0) {
      normalized.add(const _FieldItem('', ''));
    }

    final rows = <TableRow>[];
    for (var index = 0; index < normalized.length; index += columns) {
      rows.add(
        TableRow(
          children: [
            for (var column = 0; column < columns; column++)
              _buildGridCell(normalized[index + column], scale),
          ],
        ),
      );
    }

    return Table(
      border: TableBorder.symmetric(
        inside: BorderSide(color: _softBorderColor, width: 0.7 * scale),
        outside: BorderSide(color: _borderColor, width: 0.8 * scale),
      ),
      children: rows,
    );
  }

  Widget _buildGridCell(_FieldItem item, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10 * scale,
        vertical: 7 * scale,
      ),
      child: item.label.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 7.5 * scale,
                    fontWeight: FontWeight.w700,
                    color: _mutedColor,
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  item.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: item.highlight ? 10.2 * scale : 9.0 * scale,
                    fontWeight: FontWeight.w800,
                    color: item.highlight ? _successColor : _inkColor,
                    height: 1.15,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBoxSection(String title, double scale, Widget child) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8 * scale,
              vertical: 4 * scale,
            ),
            decoration: BoxDecoration(
              color: _surfaceTint,
              borderRadius: BorderRadius.circular(999 * scale),
            ),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 8.0 * scale,
                fontWeight: FontWeight.w800,
                color: _accentColor,
              ),
            ),
          ),
          SizedBox(height: 8 * scale),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(double scale) {
    return Column(
      children: [
        _buildPaymentTableHeader(scale),
        SizedBox(height: 4 * scale),
        for (final entry in receipt.paymentBreakdown)
          _buildPaymentLine(entry, scale),
        SizedBox(height: 8 * scale),
        _buildCompactMetric(
          'Metodo de pago',
          _textOrDash(receipt.paymentMethodLabel),
          scale,
        ),
        if (_paymentReference != '-')
          _buildCompactMetric('Referencia', _paymentReference, scale),
        _buildCompactMetric(
          'Monto pagado',
          'RD\$ ${receipt.formattedAmount}',
          scale,
          emphasize: true,
        ),
      ],
    );
  }

  Widget _buildPaymentTableHeader(double scale) {
    final style = TextStyle(
      fontSize: 7.7 * scale,
      fontWeight: FontWeight.w700,
      color: _mutedColor,
    );

    return Row(
      children: [
        Expanded(flex: 10, child: Text('CONCEPTO', style: style)),
        Expanded(flex: 8, child: Text('DETALLE', style: style)),
        SizedBox(
          width: 96 * scale,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('MONTO', style: style),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentLine(ReceiptLineItem entry, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 5 * scale),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _softBorderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 10,
            child: Text(
              entry.label,
              style: TextStyle(
                fontSize: 9.1 * scale,
                fontWeight: FontWeight.w700,
                color: _inkColor,
              ),
            ),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            flex: 8,
            child: Text(
              _paymentDetailText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8.4 * scale, color: _mutedColor),
            ),
          ),
          SizedBox(width: 10 * scale),
          SizedBox(
            width: 96 * scale,
            child: Text(
              _money(entry.amount),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 9.2 * scale,
                fontWeight: FontWeight.w800,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetric(
    String label,
    String value,
    double scale, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: 6 * scale),
      child: Row(
        children: [
          SizedBox(
            width: 100 * scale,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 8.3 * scale,
                fontWeight: FontWeight.w700,
                color: _mutedColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: emphasize ? 10.4 * scale : 9.0 * scale,
                fontWeight: FontWeight.w800,
                color: emphasize ? _successColor : _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(double scale) {
    return Column(
      children: [
        _buildDocumentGrid(
          [
            _FieldItem(
              'Pagado en recibo',
              'RD\$ ${receipt.formattedAmount}',
              highlight: true,
            ),
            _FieldItem(
              'Balance actual',
              _money(receipt.currentOutstandingBalance),
            ),
            _FieldItem(
              'Saldo pendiente del plan',
              _money(receipt.remainingFinancedBalance),
            ),
            _FieldItem(
              'Inicial pendiente',
              _money(receipt.remainingInitialBalance),
            ),
            _FieldItem(
              'Abonado acumulado',
              _money(receipt.totalPaidAccumulated),
            ),
            _FieldItem('Estado actual', receipt.accountStatusLabel),
          ],
          scale,
          columns: 2,
        ),
        SizedBox(height: 8 * scale),
        _buildStatusRow('Cuotas pagadas', '${receipt.installmentsPaid}', scale),
        _buildStatusRow(
          'Cuotas restantes',
          '${receipt.installmentsRemaining}',
          scale,
        ),
        _buildStatusRow('Proxima cuota', _nextInstallmentLabel(), scale),
        _buildStatusRow(
          'Proximo vencimiento',
          receipt.nextInstallmentDueDate == null
              ? '-'
              : receipt.formatShortDate(receipt.nextInstallmentDueDate!),
          scale,
        ),
        _buildStatusRow(
          'Aplicacion',
          _textOrDash(receipt.paymentConcept),
          scale,
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value, double scale) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * scale),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 8.7 * scale,
                fontWeight: FontWeight.w700,
                color: _mutedColor,
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.0 * scale,
                fontWeight: FontWeight.w800,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrativesSection(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNarrativeBox(
          'Monto en letras',
          receipt.amountInWords.toUpperCase(),
          scale,
          emphasize: true,
          maxLines: 3,
        ),
        SizedBox(height: 8 * scale),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildNarrativeBox(
                'Observacion',
                _textOrDash(receipt.note),
                scale,
                maxLines: 5,
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: _buildNarrativeBox(
                'Condiciones',
                _textOrDash(receipt.conditionsOfPayment),
                scale,
                maxLines: 5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrativeBox(
    String label,
    String value,
    double scale, {
    bool emphasize = false,
    required int maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 7.7 * scale,
            fontWeight: FontWeight.w700,
            color: _mutedColor,
          ),
        ),
        SizedBox(height: 3 * scale),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 10 * scale,
            vertical: 8 * scale,
          ),
          decoration: BoxDecoration(
            color: _surfaceTint,
            borderRadius: BorderRadius.circular(10 * scale),
            border: Border.all(color: _softBorderColor),
          ),
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasize ? 9.4 * scale : 8.7 * scale,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              color: _inkColor,
              height: 1.22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidationSection(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildValidationLine(
          'Recibimos de',
          _textOrDash(receipt.receivedFrom),
          scale,
        ),
        _buildValidationLine(
          'Recibido por',
          _textOrDash(receipt.receivedBy),
          scale,
        ),
        _buildValidationLine(
          'Entregado por',
          _textOrDash(receipt.deliveredBy),
          scale,
        ),
        _buildValidationLine('Venta', '#${receipt.sale.saleId}', scale),
        SizedBox(height: 12 * scale),
        Text(
          'Documento financiero listo para archivo interno, impresion y exportacion en formato horizontal.',
          style: TextStyle(
            fontSize: 8.2 * scale,
            color: _mutedColor,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildValidationLine(String label, String value, double scale) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 7.7 * scale,
              fontWeight: FontWeight.w700,
              color: _mutedColor,
            ),
          ),
          SizedBox(height: 2 * scale),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.0 * scale,
              fontWeight: FontWeight.w800,
              color: _inkColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureStrip(double scale) {
    return Row(
      children: [
        Expanded(
          child: _buildSignatureBlock(
            'Entregado por',
            _textOrDash(receipt.deliveredBy),
            scale,
          ),
        ),
        SizedBox(width: 22 * scale),
        Expanded(
          child: _buildSignatureBlock(
            'Recibido por',
            _textOrDash(receipt.receivedBy),
            scale,
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureBlock(String label, String value, double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: _inkColor),
        SizedBox(height: 7 * scale),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.2 * scale,
            fontWeight: FontWeight.w800,
            color: _inkColor,
          ),
        ),
        SizedBox(height: 2 * scale),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 7.8 * scale,
            fontWeight: FontWeight.w700,
            color: _mutedColor,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(double scale) {
    return Container(height: math.max(0.8, scale), color: _borderColor);
  }

  String _paymentDetailText() {
    if (_paymentReference == '-') {
      return _textOrDash(receipt.paymentMethodLabel);
    }
    return '${_textOrDash(receipt.paymentMethodLabel)} · $_paymentReference';
  }

  String _nextInstallmentLabel() {
    final installmentNumber = receipt.nextInstallmentNumber;
    final installmentAmount = receipt.nextInstallmentAmount;
    if (installmentNumber == null || installmentAmount == null) {
      return '-';
    }
    return '#$installmentNumber · ${_money(installmentAmount)}';
  }

  String _money(double value) => 'RD\$ ${formatRdCurrency(value)}';

  Uint8List? _tryDecodeBase64(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  String _textOrDash(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? '-' : normalized;
  }
}

class _FieldItem {
  const _FieldItem(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}
