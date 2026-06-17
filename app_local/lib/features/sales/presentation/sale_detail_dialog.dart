import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../payments/data/payments_repository.dart';
import '../../payments/presentation/payment_history_fullscreen.dart';
import '../domain/sale_calculator.dart';
import '../domain/sale_detail.dart';
import 'documents/sale_documents_dialog.dart';
import 'widgets/installments_flat_table.dart';

Future<void> _printSaleDocument(BuildContext context, SaleDetail detail) async {
  await _showPrintDocumentOptions(context, detail);
}

Future<void> _showPrintDocumentOptions(
  BuildContext context,
  SaleDetail detail,
) async {
  final selectedType = await showDialog<SaleDocumentType>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Imprimir documento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PrintOptionRow(
              title: 'Recibo',
              icon: Icons.receipt_long_outlined,
              onPrint: () => Navigator.of(
                dialogContext,
              ).pop(SaleDocumentType.initialReceipt),
              onPreview: () {
                Navigator.of(dialogContext).pop();
                SaleDocumentsDialog.show(
                  context,
                  detail: detail,
                  initialType: SaleDocumentType.initialReceipt,
                );
              },
            ),
            const SizedBox(height: 8),
            _PrintOptionRow(
              title: 'Tabla de amortizacion',
              icon: Icons.table_chart_outlined,
              onPrint: () => Navigator.of(
                dialogContext,
              ).pop(SaleDocumentType.amortization),
              onPreview: () {
                Navigator.of(dialogContext).pop();
                SaleDocumentsDialog.show(
                  context,
                  detail: detail,
                  initialType: SaleDocumentType.amortization,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
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
    final windowsDialogWidth = math.min(760.0, screenSize.width - 24.0);
    final dialogInsetPadding = isWindows
        ? EdgeInsets.fromLTRB(
            math.max(0, screenSize.width - windowsDialogWidth - 12),
            12,
            12,
            12,
          )
        : EdgeInsets.symmetric(
            horizontal: screenSize.width * 0.10,
            vertical: screenSize.height * 0.10,
          );

    final double maxDialogWidth = isWindows
        ? math.max(520.0, windowsDialogWidth)
        : screenSize.width * 0.80;
    final double maxDialogHeight = isWindows
        ? math.max(520.0, screenSize.height - 24.0)
        : screenSize.height * 0.80;
    final dialog = Dialog(
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
            Expanded(
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

    if (!isWindows) {
      return dialog;
    }

    return Align(alignment: Alignment.centerRight, child: dialog);
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

Future<void> openSalePaymentsHistory(
  BuildContext context, {
  required int saleId,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repository = PaymentsRepository();

  try {
    final paymentContext = await repository.fetchSaleContext(saleId);
    if (!context.mounted || paymentContext == null) {
      return;
    }

    if (paymentContext.history.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Esta venta todavia no tiene pagos registrados.'),
        ),
      );
      return;
    }

    await openSalePaymentHistoryFullscreen(
      context,
      sale: paymentContext.sale,
      history: paymentContext.history,
    );
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('No se pudo cargar el historial de pagos de la venta.'),
      ),
    );
  }
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
          if (detail.overdueInstallmentCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'En atrasos (${detail.overdueInstallmentCount})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC62828),
                ),
              ),
            ),
          ],
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
            icon: const Icon(Icons.print_outlined, size: 26),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6B7494),
              iconSize: 26,
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

class _PrintOptionRow extends StatelessWidget {
  const _PrintOptionRow({
    required this.title,
    required this.icon,
    required this.onPrint,
    required this.onPreview,
  });

  final String title;
  final IconData icon;
  final VoidCallback onPrint;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4EAF2)),
        color: const Color(0xFFFCFDFE),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF49608C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A2235),
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: onPrint,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontSize: 11.5),
            ),
            child: const Text('Imprimir'),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onPreview,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: const Text('Ver PDF', style: TextStyle(fontSize: 10.5)),
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
    final syncId = sale.syncId?.trim();
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
                _CompactInfoItem(
                  'ID local',
                  sale.id?.toString() ?? 'No disponible',
                  copyValue: sale.id?.toString(),
                ),
                _CompactInfoItem(
                  'Sync ID',
                  (syncId?.isNotEmpty ?? false) ? syncId! : 'No disponible',
                  copyValue: (syncId?.isNotEmpty ?? false) ? syncId : null,
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
    final saleId = detail.sale.id;
    final hasAppliedPayments =
        detail.sale.paidInitialPayment > 0.009 ||
        detail.installments.any((item) => item.paidAmount > 0.009);
    final emptyMessage = detail.sale.isFinancingActive
        ? 'Esta venta no tiene cuotas generadas.'
        : 'Las cuotas se generarán cuando el inicial quede completado.';
    final hasInstallments = detail.installments.isNotEmpty;
    final totalCount = detail.installments.length;
    final paidCount = detail.installments
        .where((item) => item.remainingAmount <= 0.009)
        .length;
    final pendingCount = totalCount - paidCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Cuotas amortizadas'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFDFE),
            border: Border.all(color: const Color(0xFFE4EAF2)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasInstallments
                          ? 'Resumen rápido de cuotas'
                          : 'Sin cuotas activas',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2235),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasInstallments
                          ? '$totalCount cuotas · $paidCount pagadas · $pendingCount pendientes'
                          : emptyMessage,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7494),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasInstallments)
                    _CompactFloatingActionButton.extended(
                      heroTag: 'sale-installments-fullscreen',
                      onPressed: () =>
                          openInstallmentsFullscreen(context, detail),
                      icon: Icons.open_in_full,
                      label: 'Ver cuotas',
                    ),
                  if (hasInstallments && saleId != null && hasAppliedPayments)
                    const SizedBox(height: 8),
                  if (hasInstallments && saleId != null && hasAppliedPayments)
                    _CompactFloatingActionButton.extended(
                      heroTag: 'sale-payments-fullscreen',
                      onPressed: () =>
                          openSalePaymentsHistory(context, saleId: saleId),
                      icon: Icons.list_alt_outlined,
                      label: 'Ver lista de pago',
                    ),
                ],
              ),
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
    return InstallmentsFlatTable(
      installments: widget.detail.installments,
      scrollController: _verticalController,
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
    final totalPaid = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.paidAmount,
    );
    final totalPending = detail.installments.fold<double>(
      0,
      (sum, installment) => sum + installment.remainingAmount,
    );
    final paidCount = detail.installments
        .where((item) => item.remainingAmount <= 0.009)
        .length;
    final pendingCount = detail.installments.length - paidCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FBFE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEAF0F7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.summarize_outlined,
                    size: 14,
                    color: Color(0xFF1F4B99),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Resumen de amortización',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2235),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${detail.installments.length} cuotas · $paidCount pagadas · $pendingCount pendientes',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF8893AA),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Fila 1: Capital total · Interés total · Total del plan
            Row(
              children: [
                Expanded(
                  child: _FlatMetric(
                    label: 'Capital total',
                    value: _money(totalPrincipal),
                    color: const Color(0xFF1565C0),
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _FlatMetric(
                    label: 'Interés total',
                    value: _money(totalInterest),
                    color: const Color(0xFFE67E00),
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _FlatMetric(
                    label: 'Total del plan',
                    value: _money(totalPlan),
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 1, color: Color(0xFFEAF0F7)),
            const SizedBox(height: 6),
            // Fila 2: Total pagado · Saldo pendiente
            Row(
              children: [
                Expanded(
                  child: _FlatMetric(
                    label: 'Total pagado',
                    value: _money(totalPaid),
                    color: const Color(0xFF00897B),
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _FlatMetric(
                    label: 'Saldo pendiente',
                    value: _money(totalPending),
                    color: const Color(0xFFAD1457),
                  ),
                ),
                // Spacer para mantener alineación con la fila de 3
                const _MetricDivider(),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlatMetric extends StatelessWidget {
  const _FlatMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: const Color(0xFFE4EAF2));
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
          _CompactInfoRow(
            label: items[index].label,
            value: items[index].value,
            copyValue: items[index].copyValue,
          ),
          if (index != items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CompactInfoItem {
  const _CompactInfoItem(this.label, this.value, {this.copyValue});

  final String label;
  final String value;
  final String? copyValue;
}

class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({
    required this.label,
    required this.value,
    this.copyValue,
  });

  final String label;
  final String value;
  final String? copyValue;

  Future<void> _copyValue(BuildContext context) async {
    final valueToCopy = copyValue?.trim();
    if (valueToCopy == null || valueToCopy.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: valueToCopy));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$label copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final canCopy = (copyValue?.trim().isNotEmpty ?? false);
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
        if (canCopy) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _copyValue(context),
            icon: const Icon(Icons.copy_rounded, size: 14),
            tooltip: 'Copiar $label',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              minimumSize: const Size(22, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF6B7494),
              padding: const EdgeInsets.all(2),
            ),
          ),
        ],
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
