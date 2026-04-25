import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../installments/domain/installment.dart';
import '../../payments/data/payments_repository.dart';
import '../../payments/presentation/payments_page.dart';
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
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final dialogInsetPadding = isWindows
        ? const EdgeInsets.all(24)
        : EdgeInsets.symmetric(
            horizontal: screenSize.width * 0.10,
            vertical: screenSize.height * 0.10,
          );

    final double maxDialogWidth = isWindows
        ? math.min(1020.0, math.max(560.0, screenSize.width - 48.0))
        : screenSize.width * 0.80;
    final double maxDialogHeight = isWindows
        ? math.min(900.0, math.max(520.0, screenSize.height - 48.0))
        : screenSize.height * 0.80;
    return Dialog(
      insetPadding: dialogInsetPadding,
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(detail: detail),
            const Divider(height: 1),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TopDetailsBand(detail: detail),
                    const SizedBox(height: 12),
                    _SummarySection(detail: detail),
                    const SizedBox(height: 12),
                    _InstallmentsSection(detail: detail),
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

Future<void> openPaymentsFullscreen(
  BuildContext context, {
  required int saleId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PaymentsPage(
        paymentsRepository: PaymentsRepository(),
        initialSaleId: saleId,
      ),
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
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Exportar',
            onPressed: () => _exportSaleDocument(context, detail),
            icon: const Icon(Icons.file_download_outlined, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6B7494),
            ),
          ),
          IconButton(
            tooltip: 'Imprimir',
            onPressed: () => _printSaleDocument(context, detail),
            icon: const Icon(Icons.print_outlined, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6B7494),
            ),
          ),
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
    final hasInstallments = detail.installments.isNotEmpty;
    final viewportHeight = hasInstallments ? 160.0 : 120.0;

    final actionButtons = Positioned(
      right: 14,
      bottom: 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasInstallments)
            _CompactFloatingActionButton.extended(
              heroTag: 'sale-installments-fullscreen',
              onPressed: () => openInstallmentsFullscreen(context, detail),
              icon: Icons.open_in_full,
              label: 'Ver cuotas',
            ),
          if (hasInstallments) const SizedBox(height: 10),
          _CompactFloatingActionButton.extended(
            heroTag: 'sale-payments-fullscreen',
            onPressed: () => openPaymentsFullscreen(
              context,
              saleId: detail.sale.id,
            ),
            icon: Icons.payments_outlined,
            label: 'Ver pagos',
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Cuotas amortizadas'),
        const SizedBox(height: 10),
        SizedBox(
          height: viewportHeight,
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
                    hasInstallments
                        ? 'Usa “Ver cuotas” o “Ver pagos” para ver el detalle.'
                        : emptyMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8893AA),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              actionButtons,
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactFloatingActionButton extends StatelessWidget {
  const _CompactFloatingActionButton.extended({
    required this.heroTag,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final String heroTag;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed,
      backgroundColor: const Color(0xFF1F4B99),
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 4,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _InstallmentsTableViewport extends StatefulWidget {
  const _InstallmentsTableViewport({required this.detail});

  final SaleDetail detail;

  @override
  State<_InstallmentsTableViewport> createState() =>
      _InstallmentsTableViewportState();
}

class _InstallmentsTableViewportState
    extends State<_InstallmentsTableViewport> {
  late final ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

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
          controller: _verticalController,
          thumbVisibility: true,
          child: ListView.separated(
            controller: _verticalController,
            padding: EdgeInsets.zero,
            itemCount: widget.detail.installments.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return _InstallmentCompactLine(
                installment: widget.detail.installments[index],
              );
            },
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
        title: const Text('Cuotas amortizadas'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _InstallmentsTableViewport(detail: detail)),
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

class _InstallmentCompactLine extends StatelessWidget {
  const _InstallmentCompactLine({required this.installment});

  final Installment installment;

  @override
  Widget build(BuildContext context) {
    final statusColor = _installmentStatusColor(installment.status);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              'Cuota ${installment.installmentNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2235),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  installment.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              _formatDate(installment.dueDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF54627B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _InlineMetricChip(
                    label: 'Fija',
                    value: _money(installment.totalAmount),
                    emphasize: true,
                  ),
                  const SizedBox(width: 8),
                  _InlineMetricChip(
                    label: 'Pend',
                    value: _money(installment.remainingAmount),
                  ),
                  const SizedBox(width: 8),
                  _InlineMetricChip(
                    label: 'Pag',
                    value: _money(installment.paidAmount),
                  ),
                  const SizedBox(width: 8),
                  _InlineMetricChip(
                    label: 'Cap',
                    value: _money(installment.principalAmount),
                  ),
                  const SizedBox(width: 8),
                  _InlineMetricChip(
                    label: 'Int',
                    value: _money(installment.interestAmount),
                  ),
                  const SizedBox(width: 8),
                  _InlineMetricChip(
                    label: 'Ini',
                    value: _money(installment.openingBalance),
                  ),
                  const SizedBox(width: 8),
                  _InlineMetricChip(
                    label: 'Fin',
                    value: _money(installment.endingBalance),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMetricChip extends StatelessWidget {
  const _InlineMetricChip({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7494),
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: emphasize ? 11.5 : 11,
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
                color: const Color(0xFF1A2235),
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
