import 'package:flutter/material.dart';

import '../domain/client_pagare_report.dart';
import '../domain/payment_sale_option.dart';

Future<void> openClientPaymentHistoryFullscreen(
  BuildContext context, {
  required PaymentSaleOption sale,
  required ClientPagareReport report,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _ClientPaymentHistoryFullscreenPage(
        sale: sale,
        report: report,
      ),
    ),
  );
}

class _ClientPaymentHistoryFullscreenPage extends StatelessWidget {
  const _ClientPaymentHistoryFullscreenPage({
    required this.sale,
    required this.report,
  });

  final PaymentSaleOption sale;
  final ClientPagareReport report;

  @override
  Widget build(BuildContext context) {
    final remainingAmount = sale.pendingBalance + sale.pendingInitialPayment;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 56, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HistoryHeader(sale: sale, report: report),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _HistoryTableViewport(report: report),
                  ),
                  const SizedBox(height: 8),
                  _HistoryTotalsFooter(
                    totalPaid: report.totalPaid,
                    remainingAmount: remainingAmount,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 10,
              left: 12,
              child: FloatingActionButton.small(
                heroTag: 'payments-history-fullscreen-back',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F4B99),
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.sale, required this.report});

  final PaymentSaleOption sale;
  final ClientPagareReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: Color(0xFF2D5AA6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Historial de pagos · ${sale.clientName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172433),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${report.items.length} pago(s)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7494),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _HeaderMetric(label: 'Venta', value: '#${sale.saleId}'),
              _HeaderMetric(label: 'Solar', value: sale.lotDisplayCode),
              _HeaderMetric(label: 'Cédula', value: sale.clientDocumentId),
              _HeaderMetric(
                label: 'Modalidad',
                value: sale.isFinancingActive ? 'Financiamiento' : 'Inicial',
              ),
              _HeaderMetric(
                label: 'Saldo restante',
                value: _money(sale.pendingBalance + sale.pendingInitialPayment),
                emphasize: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFF6B7494),
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value.isEmpty ? '-' : value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: emphasize
                  ? const Color(0xFF1F4B99)
                  : const Color(0xFF1A2235),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTableViewport extends StatefulWidget {
  const _HistoryTableViewport({required this.report});

  final ClientPagareReport report;

  @override
  State<_HistoryTableViewport> createState() => _HistoryTableViewportState();
}

class _HistoryTableViewportState extends State<_HistoryTableViewport> {
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;
  int? _selectedPaymentId;
  int? _hoveredPaymentId;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
    if (widget.report.items.isNotEmpty) {
      _selectedPaymentId = widget.report.items.first.paymentId;
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        border: Border.all(color: const Color(0xFFE4EAF2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 980,
              child: Column(
                children: [
                  const _HistoryTableHeader(),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _verticalController,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: widget.report.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = widget.report.items[index];
                          return _HistoryTableRow(
                            item: item,
                            selected: _selectedPaymentId == item.paymentId,
                            hovered: _hoveredPaymentId == item.paymentId,
                            onTap: () {
                              setState(() {
                                _selectedPaymentId = item.paymentId;
                              });
                            },
                            onHoverChanged: (hovered) {
                              setState(() {
                                _hoveredPaymentId = hovered
                                    ? item.paymentId
                                    : (_hoveredPaymentId == item.paymentId
                                          ? null
                                          : _hoveredPaymentId);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTableHeader extends StatelessWidget {
  const _HistoryTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F7FB),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: const Row(
        children: [
          _HeaderCell('Fecha', width: 92),
          _HeaderCell('Concepto', width: 210),
          _HeaderCell('Metodo', width: 120),
          _HeaderCell('Referencia', width: 150),
          _HeaderCell('Solar', width: 100),
          _HeaderCell('Venta', width: 88),
          _HeaderCell('Monto', width: 128, alignEnd: true),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width, this.alignEnd = false});

  final String label;
  final double width;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF7C89A3),
        ),
      ),
    );
  }
}

class _HistoryTableRow extends StatelessWidget {
  const _HistoryTableRow({
    required this.item,
    required this.selected,
    required this.hovered,
    this.onTap,
    this.onHoverChanged,
  });

  final ClientPagareItem item;
  final bool selected;
  final bool hovered;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? const Color(0xFFEAF2FF)
        : hovered
            ? const Color(0xFFF6F9FF)
            : Colors.white;
    final borderColor = selected
        ? const Color(0xFF3B5BDB)
        : hovered
            ? const Color(0xFFD7E4FF)
            : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged?.call(true),
      onExit: (_) => onHoverChanged?.call(false),
      child: Material(
        color: backgroundColor,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(
                left: BorderSide(color: borderColor, width: 3),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _formatDate(item.paymentDate),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF54627B),
                    ),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: Text(
                    _paymentTypeLabel(item.paymentType, item.installmentNumber),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    _capitalize(item.paymentMethod),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF54627B),
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Text(
                    (item.reference ?? '').trim().isEmpty
                        ? '-'
                        : item.reference!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF54627B),
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    item.lotDisplayCode,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    '#${item.saleId}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ),
                SizedBox(
                  width: 128,
                  child: Text(
                    _money(item.amountPaid),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTotalsFooter extends StatelessWidget {
  const _HistoryTotalsFooter({
    required this.totalPaid,
    required this.remainingAmount,
  });

  final double totalPaid;
  final double remainingAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Row(
        children: [
          _FooterMetric(
            label: 'Total pagado',
            value: _money(totalPaid),
            color: const Color(0xFF2E7D32),
          ),
          const Spacer(),
          _FooterMetric(
            label: 'Restante por pagar',
            value: _money(remainingAmount),
            color: const Color(0xFFE67E00),
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _FooterMetric extends StatelessWidget {
  const _FooterMetric({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7494),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 12.5 : 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _money(double value) => 'RD\$ ${value.toStringAsFixed(2)}';

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _paymentTypeLabel(String paymentType, int? installmentNumber) {
  return switch (paymentType) {
    'apartado' => 'Pago de apartado',
    'abono_inicial' => 'Abono a inicial',
    'abono_capital' => 'Abono a capital',
    _ => 'Pago de cuota #${installmentNumber ?? '-'}',
  };
}