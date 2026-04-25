import 'package:flutter/material.dart';

import '../domain/sale_calculator.dart';
import '../domain/sale_detail.dart';
import 'documents/sale_documents_dialog.dart';

enum _SaleDetailHeaderAction { export, print }

Future<void> _printSaleDocument(BuildContext context, SaleDetail detail) async {
  final selectedType = await SaleDocumentsDialog.chooseType(
    context,
    title: '¿Que deseas imprimir?',
  );
  if (!context.mounted || selectedType == null) {
    return;
  }

  await SaleDocumentsDialog.printQuick(
    context,
    detail: detail,
    type: selectedType,
  );
}

Future<void> _exportSaleDocument(
  BuildContext context,
  SaleDetail detail,
) async {
  final selectedType = await SaleDocumentsDialog.chooseType(
    context,
    title: '¿Que deseas exportar?',
  );
  if (!context.mounted || selectedType == null) {
    return;
  }

  await SaleDocumentsDialog.exportQuick(
    context,
    detail: detail,
    type: selectedType,
  );
}

class SaleDetailDialog extends StatelessWidget {
  const SaleDetailDialog({super.key, required this.detail});

  final SaleDetail detail;

  static Future<void> show(BuildContext context, SaleDetail detail) {
    return showDialog<void>(
      context: context,
      builder: (_) => SaleDetailDialog(detail: detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.10,
        vertical: screenSize.height * 0.10,
      ),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenSize.width * 0.80,
          maxHeight: screenSize.height * 0.80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(detail: detail),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopDetailsBand(detail: detail),
                    const SizedBox(height: 12),
                    _SummarySection(detail: detail),
                    const SizedBox(height: 12),
                    Expanded(child: _InstallmentsSection(detail: detail)),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _BottomBar(detail: detail),
          ],
        ),
      ),
    );
  }
}

Future<void> openInstallmentsFullscreen(
  BuildContext context,
  SaleDetail detail,
) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _InstallmentsFullscreenPage(detail: detail),
    ),
  );
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final statusColor = _saleDetailStatusColor(detail.sale.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 20,
              color: Color(0xFF3B5BDB),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.lotDisplayCode,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7494),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              detail.sale.status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_SaleDetailHeaderAction>(
            tooltip: '',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) async {
              switch (action) {
                case _SaleDetailHeaderAction.export:
                  await _exportSaleDocument(context, detail);
                  break;
                case _SaleDetailHeaderAction.print:
                  await _printSaleDocument(context, detail);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<_SaleDetailHeaderAction>(
                value: _SaleDetailHeaderAction.export,
                child: Text('Exportar'),
              ),
              PopupMenuItem<_SaleDetailHeaderAction>(
                value: _SaleDetailHeaderAction.print,
                child: Text('Imprimir'),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6B7494),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopDetailsBand extends StatelessWidget {
  const _TopDetailsBand({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final sale = detail.sale;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = [
            _TopInfoColumn(
              title: 'Cliente y solar',
              items: [
                _CompactInfoItem('Cédula', detail.clientDocumentId),
                _CompactInfoItem(
                  'Solar',
                  '${detail.lotDisplayCode} · ${detail.lotArea.toStringAsFixed(2)} m²',
                ),
              ],
            ),
            _TopInfoColumn(
              title: 'Venta y seguimiento',
              items: [
                _CompactInfoItem('Fecha venta', _formatDate(sale.saleDate)),
                _CompactInfoItem(
                  'Inicial',
                  '${_money(sale.paidInitialPayment)} / ${_money(sale.requiredInitialPayment)}'
                      '${sale.initialPaymentDeadline == null ? '' : ' · Límite ${_formatDate(sale.initialPaymentDeadline!)}'}',
                ),
              ],
            ),
            _TopInfoColumn(
              title: 'Vendedor y plan',
              items: [
                _CompactInfoItem(
                  'Vendedor',
                  (detail.sellerName ?? '').trim().isEmpty
                      ? detail.userName
                      : detail.sellerName!,
                ),
                _CompactInfoItem(
                  'Plan',
                  '${sale.installmentCount} cuotas · ${sale.monthlyInterest.toStringAsFixed(2)}% mensual',
                ),
              ],
            ),
          ];

          if (constraints.maxWidth < 980) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < columns.length; index++) ...[
                  columns[index],
                  if (index != columns.length - 1) const SizedBox(height: 14),
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: columns[0]),
              const SizedBox(width: 18),
              Expanded(child: columns[1]),
              const SizedBox(width: 18),
              Expanded(child: columns[2]),
            ],
          );
        },
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final pendingColor = detail.sale.pendingBalance > 0
        ? const Color(0xFFE67E00)
        : const Color(0xFF2E7D32);
    final fixedInstallmentAmount = _resolveFixedInstallmentAmount(detail);
    final remainingTermLabel = detail.remainingInstallmentCount == 1
        ? '1 cuota'
        : '${detail.remainingInstallmentCount} cuotas';
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              width: cardWidth,
              label: 'Precio total',
              value: _money(detail.sale.salePrice),
              icon: Icons.sell_outlined,
              color: const Color(0xFF3B5BDB),
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Cuota fija mensual',
              value: _money(fixedInstallmentAmount),
              icon: Icons.calendar_view_month_outlined,
              color: const Color(0xFF1565C0),
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Saldo pendiente',
              value: _money(detail.sale.pendingBalance),
              icon: Icons.account_balance_wallet_outlined,
              color: pendingColor,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Plazo restante',
              value: remainingTermLabel,
              icon: Icons.format_list_numbered_outlined,
              color: const Color(0xFF6A1B9A),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.width,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 205,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4EAF2)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8893AA),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallmentsSection extends StatelessWidget {
  const _InstallmentsSection({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final emptyMessage = detail.sale.isFinancingActive
        ? 'Esta venta no tiene cuotas generadas.'
        : 'Las cuotas se generarán cuando el inicial quede completado.';
    final bodyMessage = detail.installments.isEmpty
        ? emptyMessage
        : 'Las cuotas y la tabla de amortización están disponibles en pantalla completa.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Cuotas'),
        const SizedBox(height: 10),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFDFE),
                    border: Border.all(color: const Color(0xFFE4EAF2)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    bodyMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8893AA),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'sale-installments-fullscreen',
                  onPressed: () => openInstallmentsFullscreen(context, detail),
                  backgroundColor: const Color(0xFF1F4B99),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Cuotas'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstallmentsTableViewport extends StatefulWidget {
  const _InstallmentsTableViewport({
    required this.detail,
    required this.horizontalController,
    required this.verticalController,
    this.dense = false,
  });

  final SaleDetail detail;
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final bool dense;

  @override
  State<_InstallmentsTableViewport> createState() =>
      _InstallmentsTableViewportState();
}

class _InstallmentsTableViewportState
    extends State<_InstallmentsTableViewport> {
  int? _selectedInstallmentNumber;
  int? _hoveredInstallmentNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        border: Border.all(color: const Color(0xFFE4EAF2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Scrollbar(
          controller: widget.horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: widget.horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1220,
              child: Column(
                children: [
                  _InstallmentsTableHeader(dense: widget.dense),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: widget.verticalController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: widget.verticalController,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: widget.detail.installments.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final inst = widget.detail.installments[index];
                          return _InstallmentTableRow(
                            installmentNumber: inst.installmentNumber,
                            dueDate: _formatDate(inst.dueDate),
                            openingBalance: inst.openingBalance,
                            interestAmount: inst.interestAmount,
                            principalAmount: inst.principalAmount,
                            totalAmount: inst.totalAmount,
                            paidAmount: inst.paidAmount,
                            remainingAmount: inst.remainingAmount,
                            endingBalance: inst.endingBalance,
                            status: inst.status,
                            dense: widget.dense,
                            selected:
                                _selectedInstallmentNumber ==
                                inst.installmentNumber,
                            hovered:
                                _hoveredInstallmentNumber ==
                                inst.installmentNumber,
                            onTap: () {
                              setState(() {
                                _selectedInstallmentNumber =
                                    inst.installmentNumber;
                              });
                            },
                            onHoverChanged: (hovered) {
                              setState(() {
                                _hoveredInstallmentNumber = hovered
                                    ? inst.installmentNumber
                                    : (_hoveredInstallmentNumber ==
                                              inst.installmentNumber
                                          ? null
                                          : _hoveredInstallmentNumber);
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

class _InstallmentsFullscreenPage extends StatelessWidget {
  const _InstallmentsFullscreenPage({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.installments.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: AppBar(
          title: const Text('Cuotas'),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: Center(
          child: Text(
            detail.sale.isFinancingActive
                ? 'Esta venta no tiene cuotas generadas.'
                : 'Las cuotas se generarán cuando el inicial quede completado.',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF8893AA),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalPrincipal = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.principalAmount,
    );
    final totalInterest = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.interestAmount,
    );
    final totalPlan = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.totalAmount,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Cuotas'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _FullscreenInstallmentsTable(detail: detail)),
              const SizedBox(height: 8),
              _FullscreenTotalsFooter(
                totalPrincipal: totalPrincipal,
                totalInterest: totalInterest,
                totalPlan: totalPlan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenInstallmentsTable extends StatefulWidget {
  const _FullscreenInstallmentsTable({required this.detail});

  final SaleDetail detail;

  @override
  State<_FullscreenInstallmentsTable> createState() =>
      _FullscreenInstallmentsTableState();
}

class _FullscreenInstallmentsTableState
    extends State<_FullscreenInstallmentsTable> {
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _InstallmentsTableViewport(
      detail: widget.detail,
      horizontalController: _horizontalController,
      verticalController: _verticalController,
      dense: true,
    );
  }
}

class _InstallmentSummaryChip extends StatelessWidget {
  const _InstallmentSummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7494),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallmentsTableHeader extends StatelessWidget {
  const _InstallmentsTableHeader({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F7FB),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 16,
        vertical: dense ? 9 : 14,
      ),
      child: Row(
        children: [
          _TableHeaderCell('Cuota', width: 84, dense: dense),
          _TableHeaderCell('Estado', width: 110, dense: dense),
          _TableHeaderCell('Vence', width: 112, dense: dense),
          _TableHeaderCell(
            'Cuota fija',
            width: 126,
            alignEnd: true,
            dense: dense,
          ),
          _TableHeaderCell(
            'Pendiente',
            width: 126,
            alignEnd: true,
            dense: dense,
          ),
          _TableHeaderCell('Pagado', width: 118, alignEnd: true, dense: dense),
          _TableHeaderCell('Capital', width: 118, alignEnd: true, dense: dense),
          _TableHeaderCell('Interés', width: 118, alignEnd: true, dense: dense),
          _TableHeaderCell(
            'Saldo inicial',
            width: 128,
            alignEnd: true,
            dense: dense,
          ),
          _TableHeaderCell(
            'Saldo final',
            width: 128,
            alignEnd: true,
            dense: dense,
          ),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(
    this.label, {
    required this.width,
    this.alignEnd = false,
    this.dense = false,
  });

  final String label;
  final double width;
  final bool alignEnd;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: dense ? 10.5 : 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF7C89A3),
        ),
      ),
    );
  }
}

class _InstallmentTableRow extends StatelessWidget {
  const _InstallmentTableRow({
    required this.installmentNumber,
    required this.dueDate,
    required this.openingBalance,
    required this.interestAmount,
    required this.principalAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.endingBalance,
    required this.status,
    this.dense = false,
    this.selected = false,
    this.hovered = false,
    this.onTap,
    this.onHoverChanged,
  });

  final int installmentNumber;
  final String dueDate;
  final double openingBalance;
  final double interestAmount;
  final double principalAmount;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final double endingBalance;
  final String status;
  final bool dense;
  final bool selected;
  final bool hovered;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final statusColor = _installmentStatusColor(status);
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
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 12 : 16,
              vertical: dense ? 8 : 14,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(left: BorderSide(color: borderColor, width: 3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    'Cuota $installmentNumber',
                    style: TextStyle(
                      fontSize: dense ? 11.5 : 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A2235),
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: dense ? 8 : 10,
                        vertical: dense ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: dense ? 10.5 : 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 112,
                  child: Text(
                    dueDate,
                    style: TextStyle(
                      fontSize: dense ? 11.5 : 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF54627B),
                    ),
                  ),
                ),
                _TableValueCell(
                  _money(totalAmount),
                  width: 126,
                  emphasize: true,
                  dense: dense,
                ),
                _TableValueCell(
                  _money(remainingAmount),
                  width: 126,
                  dense: dense,
                ),
                _TableValueCell(_money(paidAmount), width: 118, dense: dense),
                _TableValueCell(
                  _money(principalAmount),
                  width: 118,
                  dense: dense,
                ),
                _TableValueCell(
                  _money(interestAmount),
                  width: 118,
                  dense: dense,
                ),
                _TableValueCell(
                  _money(openingBalance),
                  width: 128,
                  dense: dense,
                ),
                _TableValueCell(
                  _money(endingBalance),
                  width: 128,
                  dense: dense,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableValueCell extends StatelessWidget {
  const _TableValueCell(
    this.value, {
    required this.width,
    this.emphasize = false,
    this.dense = false,
  });

  final String value;
  final double width;
  final bool emphasize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: dense ? (emphasize ? 12 : 11.5) : (emphasize ? 14 : 13),
          fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          color: const Color(0xFF1A2235),
        ),
      ),
    );
  }
}

class _FullscreenTotalsFooter extends StatelessWidget {
  const _FullscreenTotalsFooter({
    required this.totalPrincipal,
    required this.totalInterest,
    required this.totalPlan,
  });

  final double totalPrincipal;
  final double totalInterest;
  final double totalPlan;

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
            label: 'Capital',
            value: _money(totalPrincipal),
            color: const Color(0xFF1565C0),
          ),
          const SizedBox(width: 18),
          _FooterMetric(
            label: 'Interés',
            value: _money(totalInterest),
            color: const Color(0xFFE67E00),
          ),
          const Spacer(),
          _FooterMetric(
            label: 'Total',
            value: _money(totalPlan),
            color: const Color(0xFF2E7D32),
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

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final totalPrincipal = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.principalAmount,
    );
    final totalInterest = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.interestAmount,
    );
    final totalPlan = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.totalAmount,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chipWidth = (constraints.maxWidth - 12) / 2;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _BottomTotalChip(
                width: chipWidth,
                label: 'Capital total',
                value: _money(totalPrincipal),
                color: const Color(0xFF1565C0),
              ),
              _BottomTotalChip(
                width: chipWidth,
                label: 'Interés total',
                value: _money(totalInterest),
                color: const Color(0xFFE67E00),
              ),
              _BottomTotalChip(
                width: chipWidth,
                label: 'Total del plan',
                value: _money(totalPlan),
                color: const Color(0xFF2E7D32),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BottomTotalChip extends StatelessWidget {
  const _BottomTotalChip({
    required this.label,
    required this.value,
    required this.color,
    this.width,
  });

  final String label;
  final String value;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? 220,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7494),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopInfoColumn extends StatelessWidget {
  const _TopInfoColumn({required this.title, required this.items});

  final String title;
  final List<_CompactInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: Color(0xFF8893AA),
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < items.length; index++) ...[
          _CompactInfoRow(label: items[index].label, value: items[index].value),
          if (index != items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CompactInfoItem {
  const _CompactInfoItem(this.label, this.value);

  final String label;
  final String value;
}

class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8893AA),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2235),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF8893AA),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

double _resolveFixedInstallmentAmount(SaleDetail detail) {
  if (detail.installments.isNotEmpty) {
    return detail.installments.first.totalAmount;
  }

  return SaleCalculator.calculateEstimatedInstallmentAmount(
    financedBalance: detail.sale.financedBalance,
    monthlyInterest: detail.sale.monthlyInterest,
    installmentCount: detail.sale.installmentCount,
  );
}

String _money(double value) => 'RD\$${_formatAmount(value)}';

String _formatAmount(double value) {
  return value
      .toStringAsFixed(2)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

String _formatDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

Color _saleDetailStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'activa':
      return const Color(0xFF2E7D32);
    case 'reservada':
      return const Color(0xFFE67E00);
    case 'cancelada':
      return const Color(0xFFC62828);
    case 'completada':
      return const Color(0xFF1565C0);
    default:
      return const Color(0xFF455A64);
  }
}

Color _installmentStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pagada':
      return const Color(0xFF2E7D32);
    case 'vencida':
      return const Color(0xFFC62828);
    case 'pendiente':
      return const Color(0xFFE67E00);
    default:
      return const Color(0xFF455A64);
  }
}
