import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

enum _SaleDetailMenuAction { export, print, close }

bool _isMeaningfulText(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return false;
  if (normalized == '-' || normalized == '—') return false;
  return true;
}

void _showPrintHint(BuildContext context, String action) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        '$action usa la impresion del navegador en la PWA. Si necesitas PDF, selecciona Guardar como PDF en el dialogo de impresion.',
      ),
    ),
  );
}

class SaleDetailDialog extends StatelessWidget {
  const SaleDetailDialog({super.key, required this.detail});

  final Map<String, dynamic> detail;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 860;
    final fullscreen = size.width < 640 || size.height < 720;
    final viewModel = _SaleDetailViewModel.fromMap(detail);

    return Dialog(
      insetPadding: fullscreen
          ? const EdgeInsets.all(0)
          : EdgeInsets.symmetric(
              horizontal: compact ? 10 : 24,
              vertical: compact ? 10 : 18,
            ),
      backgroundColor: Colors.transparent,
      child: SafeArea(
        minimum: EdgeInsets.all(fullscreen ? 0 : 4),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: fullscreen ? size.width : (compact ? 460 : 1260),
            maxHeight: fullscreen
                ? size.height
                : size.height - (compact ? 20 : 36),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(
              fullscreen ? 0 : (compact ? 20 : 24),
            ),
            border: Border.all(
              color: fullscreen ? Colors.transparent : const Color(0xFFE4EAF2),
            ),
            boxShadow: fullscreen
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x16000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailHeader(viewModel: viewModel, compact: compact),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Scrollbar(
                        thumbVisibility: !compact,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 12 : 18,
                            compact ? 12 : 16,
                            compact ? 12 : 18,
                            compact ? 14 : 18,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TopInfoBand(viewModel: viewModel),
                              const SizedBox(height: 12),
                              _PrimaryMetricStrip(viewModel: viewModel),
                              const SizedBox(height: 12),
                              _TotalsStrip(viewModel: viewModel),
                              if (viewModel.payments.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _PaymentsSection(viewModel: viewModel),
                              ],
                              if (viewModel.notes.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _NotesSection(notes: viewModel.notes),
                              ],
                              const SizedBox(height: 70),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: compact ? 14 : 18,
                      bottom: compact ? 14 : 18,
                      child: FloatingActionButton.extended(
                        heroTag: 'sale-detail-installments',
                        backgroundColor: const Color(0xFF14385F),
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.view_list_outlined, size: 18),
                        label: const Text('Cuotas'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                _SaleInstallmentsPage(viewModel: viewModel),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const Divider(height: 1),
                _DialogFooter(viewModel: viewModel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.viewModel, required this.compact});

  final _SaleDetailViewModel viewModel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 18,
        compact ? 10 : 14,
        compact ? 6 : 12,
        compact ? 10 : 14,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;

          final menuButton = PopupMenuButton<_SaleDetailMenuAction>(
            tooltip: '',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) {
              switch (action) {
                case _SaleDetailMenuAction.export:
                  _showPrintHint(context, 'Exportar PDF');
                  break;
                case _SaleDetailMenuAction.print:
                  _showPrintHint(context, 'Imprimir');
                  break;
                case _SaleDetailMenuAction.close:
                  Navigator.of(context).pop();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<_SaleDetailMenuAction>(
                value: _SaleDetailMenuAction.export,
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Exportar'),
                  ],
                ),
              ),
              PopupMenuItem<_SaleDetailMenuAction>(
                value: _SaleDetailMenuAction.print,
                child: Row(
                  children: [
                    Icon(Icons.print_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Imprimir'),
                  ],
                ),
              ),
              PopupMenuItem<_SaleDetailMenuAction>(
                value: _SaleDetailMenuAction.close,
                child: Row(
                  children: [
                    Icon(Icons.close, size: 18),
                    SizedBox(width: 10),
                    Text('Cerrar'),
                  ],
                ),
              ),
            ],
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Exportar',
                onPressed: () => _showPrintHint(context, 'Exportar PDF'),
                icon: const Icon(Icons.file_download_outlined, size: 20),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(34, 34),
                  foregroundColor: const Color(0xFF6A7684),
                ),
              ),
              IconButton(
                tooltip: 'Imprimir',
                onPressed: () => _showPrintHint(context, 'Imprimir'),
                icon: const Icon(Icons.print_outlined, size: 20),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(34, 34),
                  foregroundColor: const Color(0xFF6A7684),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(34, 34),
                  foregroundColor: const Color(0xFF6A7684),
                ),
              ),
            ],
          );

          final leading = Container(
            width: compact ? 36 : 42,
            height: compact ? 36 : 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4FA),
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
            ),
            child: compact
                ? IconButton(
                    tooltip: 'Atrás',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: const Color(0xFF274567),
                    ),
                  )
                : const Icon(
                    Icons.receipt_long_outlined,
                    size: 20,
                    color: Color(0xFF274567),
                  ),
          );

          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact)
                Text(
                  viewModel.saleId.trim().isEmpty
                      ? viewModel.clientName
                      : 'Venta #${viewModel.saleId}  ·  ${viewModel.clientName}',
                  maxLines: stacked ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 18 : 21,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF14273F),
                  ),
                ),
              if (compact)
                Text(
                  viewModel.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF14273F),
                  ),
                ),
              const SizedBox(height: 3),
              Text(
                viewModel.headerSubtitle,
                maxLines: compact ? 1 : (stacked ? 2 : 1),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 13,
                  color: Color(0xFF7E8BA0),
                  height: compact ? 1.2 : 1.35,
                ),
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    leading,
                    const SizedBox(width: 8),
                    Expanded(child: titleBlock),
                    compact
                        ? IconTheme(
                            data: const IconThemeData(
                              color: Color(0xFF6A7684),
                              size: 22,
                            ),
                            child: menuButton,
                          )
                        : actions,
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusChip(
                      label: viewModel.statusLabel,
                      tone: viewModel.statusTone,
                    ),
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              leading,
              SizedBox(width: compact ? 10 : 12),
              Expanded(child: titleBlock),
              if (!compact) ...[
                _StatusChip(
                  label: viewModel.statusLabel,
                  tone: viewModel.statusTone,
                ),
                const SizedBox(width: 8),
              ],
              compact
                  ? IconTheme(
                      data: const IconThemeData(
                        color: Color(0xFF6A7684),
                        size: 22,
                      ),
                      child: menuButton,
                    )
                  : actions,
            ],
          );
        },
      ),
    );
  }
}

class _TopInfoBand extends StatelessWidget {
  const _TopInfoBand({required this.viewModel});

  final _SaleDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 860;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1120
              ? 3
              : constraints.maxWidth >= 720
              ? 2
              : 1;
          final infoColumns = [
            _InfoColumn(
              title: 'CLIENTE Y SOLAR',
              items: [
                _InfoItem('Cliente', viewModel.clientName),
                _InfoItem('Cedula', viewModel.clientDocumentId),
                _InfoItem('Solar', viewModel.lotCodeLabel),
                _InfoItem('Metros cuadrados', viewModel.lotAreaLabel),
              ],
            ),
            _InfoColumn(
              title: 'VENTA Y SEGUIMIENTO',
              items: [
                _InfoItem(
                  'Precio por metro',
                  viewModel.pricePerSquareMeterLabel,
                ),
                _InfoItem(
                  'Inicial minimo',
                  viewModel.requiredInitialPaymentLabel,
                ),
                _InfoItem('Inicial real', viewModel.paidInitialPaymentLabel),
                _InfoItem('Fecha venta', viewModel.saleDateLabel),
                _InfoItem('Activacion', viewModel.activationDateLabel),
                _InfoItem('Limite inicial', viewModel.initialDeadlineLabel),
              ],
            ),
            _InfoColumn(
              title: 'VENDEDOR Y PLAN',
              items: [
                _InfoItem('Atendido por', viewModel.userName),
                _InfoItem('Vendedor', viewModel.sellerName),
                _InfoItem('Cedula vend.', viewModel.sellerDocumentId),
                _InfoItem('Tel. vendedor', viewModel.sellerPhone),
                _InfoItem('Contrato', viewModel.contractNumber),
                _InfoItem('Estado', viewModel.statusLabel),
              ],
            ),
          ];

          final visibleColumns = infoColumns
              .where((column) => column.hasVisibleItems)
              .toList(growable: false);
          if (visibleColumns.isEmpty) {
            return const SizedBox.shrink();
          }

          final effectiveColumns = math.min(columns, visibleColumns.length);
          final itemWidth = effectiveColumns == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - ((effectiveColumns - 1) * 22)) /
                    effectiveColumns;

          return Wrap(
            spacing: 22,
            runSpacing: 18,
            children: [
              for (final child in visibleColumns)
                SizedBox(width: itemWidth, child: child),
            ],
          );
        },
      ),
    );
  }
}

class _PrimaryMetricStrip extends StatelessWidget {
  const _PrimaryMetricStrip({required this.viewModel});

  final _SaleDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final items = [
          _MetricCard(
            icon: Icons.sell_outlined,
            iconColor: const Color(0xFF5176C9),
            iconBackground: const Color(0xFFE9F0FF),
            label: 'Precio total',
            value: viewModel.salePriceLabel,
          ),
          _MetricCard(
            icon: Icons.grid_view_rounded,
            iconColor: const Color(0xFF4479B8),
            iconBackground: const Color(0xFFE7EFFA),
            label: 'Cuota fija mensual',
            value: viewModel.fixedInstallmentLabel,
          ),
          _MetricCard(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: const Color(0xFFE48B2C),
            iconBackground: const Color(0xFFFFF1E1),
            label: 'Saldo pendiente',
            value: viewModel.pendingBalanceLabel,
          ),
          _MetricCard(
            icon: Icons.format_list_numbered_rounded,
            iconColor: const Color(0xFF8B5DBA),
            iconBackground: const Color(0xFFF3E9FF),
            label: 'Plazo restante',
            value: viewModel.remainingInstallmentsLabel,
          ),
        ];

        return _AdaptiveCardWrap(
          minItemWidth: 220,
          maxColumns: 4,
          spacing: 10,
          runSpacing: 10,
          children: items,
        );
      },
    );
  }
}

class _SaleInstallmentsPage extends StatelessWidget {
  const _SaleInstallmentsPage({required this.viewModel});

  final _SaleDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
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
              DesktopSurface(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      'Venta #${viewModel.saleId} · ${viewModel.clientName}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D2640),
                      ),
                    ),
                    DesktopTag(
                      label: '${viewModel.installments.length} cuotas',
                      background: const Color(0xFFF1F4FA),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DesktopSurface(
                  padding: const EdgeInsets.all(0),
                  child: viewModel.installments.isEmpty
                      ? const DesktopEmptyState(
                          icon: Icons.view_list_outlined,
                          title: 'Sin cuotas registradas',
                          message:
                              'Esta venta no tiene cuotas visibles en el backend.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: viewModel.installments.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final row = viewModel.installments[index];
                            return _InstallmentOneLineRow(
                              row: row,
                              compact: compact,
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallmentOneLineRow extends StatelessWidget {
  const _InstallmentOneLineRow({required this.row, required this.compact});

  final _InstallmentViewRow row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AmountChip(
          label: 'Fija',
          value: row.totalAmountLabel,
          emphasize: true,
        ),
        const SizedBox(width: 8),
        _AmountChip(label: 'Pend', value: row.pendingAmountLabel),
        const SizedBox(width: 8),
        _AmountChip(label: 'Pag', value: row.paidAmountLabel),
        const SizedBox(width: 8),
        _AmountChip(label: 'Cap', value: row.principalLabel),
        const SizedBox(width: 8),
        _AmountChip(label: 'Int', value: row.interestLabel),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E7F0)),
            ),
            child: Text(
              '${row.installmentNumber}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF31445F),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.dueDateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D2640),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: row.statusLabel,
                  tone: row.statusTone,
                  compact: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: compact
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: chips,
                    )
                  : chips,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final tone = emphasize ? const Color(0xFF14385F) : const Color(0xFF6B7682);

    return SizedBox(
      width: 108,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: tone,
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

class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.viewModel});

  final _SaleDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return _AdaptiveCardWrap(
      minItemWidth: 190,
      maxColumns: 3,
      spacing: 12,
      runSpacing: 12,
      children: [
        _TotalCard(
          label: 'Capital total',
          value: viewModel.totalCapitalLabel,
          background: const Color(0xFFEAF3FF),
          foreground: const Color(0xFF2172D0),
        ),
        _TotalCard(
          label: 'Interes total',
          value: viewModel.totalInterestLabel,
          background: const Color(0xFFFFF4E8),
          foreground: const Color(0xFFE07B00),
        ),
        _TotalCard(
          label: 'Total del plan',
          value: viewModel.totalPlanLabel,
          background: const Color(0xFFF0F8F0),
          foreground: const Color(0xFF35904E),
        ),
      ],
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({required this.viewModel});

  final _SaleDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactList = constraints.maxWidth < 760;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                spacing: 8,
                children: [
                  const Text(
                    'Historial de pagos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D2640),
                    ),
                  ),
                  DesktopTag(
                    label: '${viewModel.payments.length} registros',
                    background: const Color(0xFFF1F4FA),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              compactList
                  ? Column(
                      children: [
                        for (
                          var index = 0;
                          index < viewModel.payments.length;
                          index++
                        ) ...[
                          _PaymentRowCard(payment: viewModel.payments[index]),
                          if (index != viewModel.payments.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE4EAF2)),
                      ),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < viewModel.payments.length;
                            index++
                          ) ...[
                            _PaymentRowCard(
                              payment: viewModel.payments[index],
                              embedded: true,
                            ),
                            if (index != viewModel.payments.length - 1)
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                          ],
                        ],
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Observaciones',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D2640),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            notes,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Color(0xFF536174),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({required this.viewModel});

  final _SaleDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 860;

    final exportButton = OutlinedButton.icon(
      onPressed: () => _showPrintHint(context, 'Exportar PDF'),
      icon: Icon(Icons.file_download_outlined, size: compact ? 15 : 18),
      label: Text(
        'Exportar',
        style: TextStyle(fontSize: compact ? 11.5 : null),
      ),
      style: compact
          ? OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
    );
    final printButton = FilledButton.tonalIcon(
      onPressed: () => _showPrintHint(context, 'Imprimir'),
      icon: Icon(Icons.print_outlined, size: compact ? 15 : 18),
      label: Text(
        'Imprimir',
        style: TextStyle(fontSize: compact ? 11.5 : null),
      ),
      style: compact
          ? FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
    );
    final closeButton = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF14385F),
        foregroundColor: Colors.white,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : null,
        minimumSize: compact ? const Size(0, 34) : null,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      ),
      onPressed: () => Navigator.of(context).pop(),
      child: Text('Cerrar', style: TextStyle(fontSize: compact ? 11.5 : null)),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        12,
        compact ? 12 : 18,
        compact ? 12 : 14,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (viewModel.statusLabel.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusChip(
                      label: viewModel.statusLabel,
                      tone: viewModel.statusTone,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      exportButton,
                      const SizedBox(width: 8),
                      printButton,
                      const SizedBox(width: 8),
                      closeButton,
                    ],
                  ),
                ),
              ],
            )
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              spacing: 10,
              children: [
                _StatusChip(
                  label: viewModel.statusLabel,
                  tone: viewModel.statusTone,
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [exportButton, printButton, closeButton],
                ),
              ],
            ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({required this.title, required this.items});

  final String title;
  final List<_InfoItem> items;

  bool get hasVisibleItems => items.any((item) => item.isVisible);

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .where((item) => item.isVisible)
        .toList(growable: false);
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Color(0xFF8794A8),
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < visibleItems.length; index++) ...[
          visibleItems[index],
          if (index != visibleItems.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem(this.label, this.value);

  final String label;
  final String value;

  bool get isVisible => _isMeaningfulText(value);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 280;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8794A8),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF304357),
                  height: 1.35,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8794A8),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF304357),
                  height: 1.35,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8B98AC),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF304357),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
  });

  final String label;
  final String value;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRowCard extends StatelessWidget {
  const _PaymentRowCard({required this.payment, this.embedded = false});

  final _PaymentViewRow payment;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 360;
        final iconBox = Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4ED),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(payment.icon, size: 18, color: const Color(0xFF2F6F5C)),
        );

        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              payment.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF213549),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              payment.subtitle,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF6E7791),
                height: 1.35,
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        iconBox,
                        const SizedBox(width: 12),
                        Expanded(child: textBlock),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DesktopTag(
                        label: payment.amountLabel,
                        background: const Color(0xFFF6EFE3),
                        foreground: const Color(0xFF8C5A2C),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: textBlock),
                    const SizedBox(width: 12),
                    DesktopTag(
                      label: payment.amountLabel,
                      background: const Color(0xFFF6EFE3),
                      foreground: const Color(0xFF8C5A2C),
                    ),
                  ],
                ),
        );
      },
    );

    if (embedded) {
      return content;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: content,
    );
  }
}

class _AdaptiveCardWrap extends StatelessWidget {
  const _AdaptiveCardWrap({
    required this.children,
    required this.minItemWidth,
    required this.maxColumns,
    this.spacing = 10,
    this.runSpacing = 10,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: children,
          );
        }

        final availableWidth = constraints.maxWidth;
        var columns = maxColumns;
        while (columns > 1) {
          final itemWidth =
              (availableWidth - ((columns - 1) * spacing)) / columns;
          if (itemWidth >= minItemWidth) {
            break;
          }
          columns--;
        }

        final finalColumns = math.max(columns, 1);
        final itemWidth = finalColumns == 1
            ? availableWidth
            : (availableWidth - ((finalColumns - 1) * spacing)) / finalColumns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final _StatusTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.foreground.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11.5 : 12.5,
          fontWeight: FontWeight.w700,
          color: tone.foreground,
        ),
      ),
    );
  }
}

class _StatusTone {
  const _StatusTone(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

class _SaleDetailViewModel {
  _SaleDetailViewModel({
    required this.saleId,
    required this.clientName,
    required this.clientDocumentId,
    required this.lotCodeLabel,
    required this.lotDisplayLabel,
    required this.lotAreaLabel,
    required this.pricePerSquareMeterLabel,
    required this.saleDateLabel,
    required this.activationDateLabel,
    required this.initialDeadlineLabel,
    required this.userName,
    required this.sellerName,
    required this.sellerDocumentId,
    required this.sellerPhone,
    required this.contractNumber,
    required this.statusLabel,
    required this.statusTone,
    required this.salePriceLabel,
    required this.fixedInstallmentLabel,
    required this.pendingBalanceLabel,
    required this.remainingInstallmentsLabel,
    required this.requiredInitialPaymentLabel,
    required this.paidInitialPaymentLabel,
    required this.activeTermLabel,
    required this.totalCapitalLabel,
    required this.totalInterestLabel,
    required this.totalPlanLabel,
    required this.notes,
    required this.headerSubtitle,
    required this.installments,
    required this.payments,
    required this.paidInstallmentsCount,
    required this.remainingInstallmentsCount,
  });

  final String saleId;
  final String clientName;
  final String clientDocumentId;
  final String lotCodeLabel;
  final String lotDisplayLabel;
  final String lotAreaLabel;
  final String pricePerSquareMeterLabel;
  final String saleDateLabel;
  final String activationDateLabel;
  final String initialDeadlineLabel;
  final String userName;
  final String sellerName;
  final String sellerDocumentId;
  final String sellerPhone;
  final String contractNumber;
  final String statusLabel;
  final _StatusTone statusTone;
  final String salePriceLabel;
  final String fixedInstallmentLabel;
  final String pendingBalanceLabel;
  final String remainingInstallmentsLabel;
  final String requiredInitialPaymentLabel;
  final String paidInitialPaymentLabel;
  final String activeTermLabel;
  final String totalCapitalLabel;
  final String totalInterestLabel;
  final String totalPlanLabel;
  final String notes;
  final String headerSubtitle;
  final List<_InstallmentViewRow> installments;
  final List<_PaymentViewRow> payments;
  final int paidInstallmentsCount;
  final int remainingInstallmentsCount;

  static _SaleDetailViewModel fromMap(Map<String, dynamic> detail) {
    final currency = AppNumberFormats.currency;
    final saleSync = _map(detail['syncPayload']);
    final client = _map(detail['client']);
    final product = _map(detail['product']);
    final productSync = _map(product['syncPayload']);
    final user = _map(detail['user']);
    final seller = _map(detail['seller']);

    final saleId = _string(detail['id']);
    final clientName = _fullName(client, fallback: 'Sin cliente');
    final clientDocumentId = _string(client['documentId']);
    final productCode = _string(product['code']);
    final productName = _string(product['name'], fallback: 'Sin solar');
    final blockNumber = _string(productSync['block_number']);
    final lotNumber = _string(productSync['lot_number']);
    final lotCodeLabel = [
      if (productCode.isNotEmpty) productCode,
      if (blockNumber.isNotEmpty || lotNumber.isNotEmpty)
        'M$blockNumber-S$lotNumber',
      if (productCode.isEmpty && productName.isNotEmpty) productName,
    ].firstWhere((item) => item.trim().isNotEmpty, orElse: () => 'Sin solar');
    final lotDisplayLabel = productName.trim().isEmpty
        ? lotCodeLabel
        : productName;
    final lotArea = _number(productSync['area']);
    final pricePerSquareMeter = _number(productSync['price_per_square_meter']);

    final salePrice = _firstNumber([
      saleSync['sale_price'],
      detail['principalAmount'],
      detail['totalAmount'],
    ]);
    final financedBalance = _firstNumber([
      saleSync['financed_balance'],
      detail['financedAmount'],
      math.max(salePrice - _firstNumber([detail['downPayment']]), 0.0),
    ]);
    final requiredInitialPayment = _firstNumber([
      saleSync['required_initial_payment'],
      detail['downPayment'],
    ]);
    final paidInitialPayment = _firstNumber([
      saleSync['paid_initial_payment'],
      detail['downPayment'],
      detail['paidAmount'],
    ]);
    final pendingBalance = _firstNumber([
      saleSync['pending_balance'],
      detail['outstandingBalance'],
      math.max(financedBalance - _firstNumber([detail['paidAmount']]), 0.0),
    ]);
    final termMonths = _firstInt([
      saleSync['installment_count'],
      detail['termMonths'],
    ]);
    final saleDate = _date(saleSync['sale_date'] ?? detail['saleDate']);
    final activationDate = _date(saleSync['activation_date']);
    final initialDeadline = _date(saleSync['initial_payment_deadline']);

    final installmentMaps =
        (detail['installments'] as List<dynamic>? ?? const <dynamic>[])
            .map(_map)
            .toList(growable: false)
          ..sort(
            (a, b) => _int(
              a['installmentNumber'],
            ).compareTo(_int(b['installmentNumber'])),
          );

    var runningBalance = financedBalance > 0
        ? financedBalance
        : installmentMaps.fold<double>(
            0,
            (sum, item) =>
                sum +
                _firstNumber([
                  _map(item['syncPayload'])['principal_amount'],
                  item['principalAmount'],
                ]),
          );

    final installments = <_InstallmentViewRow>[];
    var totalCapital = 0.0;
    var totalInterest = 0.0;
    var totalPlan = 0.0;
    var paidInstallmentsCount = 0;

    for (final installment in installmentMaps) {
      final installmentSync = _map(installment['syncPayload']);
      final totalAmount = _firstNumber([
        installmentSync['total_amount'],
        installment['amount'],
      ]);
      final principalAmount = _firstNumber([
        installmentSync['principal_amount'],
        installment['principalAmount'],
      ]);
      final interestAmount = _firstNumber([
        installmentSync['interest_amount'],
        installment['interestAmount'],
      ]);
      final paidAmount = _firstNumber([
        installmentSync['paid_amount'],
        installment['paidAmount'],
      ]);
      final openingBalance = installmentSync.containsKey('opening_balance')
          ? _number(installmentSync['opening_balance'])
          : runningBalance;
      final endingBalance = installmentSync.containsKey('ending_balance')
          ? _number(installmentSync['ending_balance'])
          : math.max(openingBalance - principalAmount, 0.0);
      final pendingAmount = math.max(totalAmount - paidAmount, 0.0);
      final statusRaw = _string(
        installmentSync['status'] ?? installment['status'],
        fallback: 'pending',
      );
      final statusLabel = _installmentStatusLabel(statusRaw, pendingAmount);
      final statusTone = _installmentStatusTone(statusRaw, pendingAmount);

      totalCapital += principalAmount;
      totalInterest += interestAmount;
      totalPlan += totalAmount;
      if (pendingAmount <= 0.009 || statusRaw.toLowerCase() == 'paid') {
        paidInstallmentsCount++;
      }

      installments.add(
        _InstallmentViewRow(
          installmentNumber: _firstInt([
            installmentSync['installment_number'],
            installment['installmentNumber'],
          ]),
          dueDateLabel: _formatDate(
            _date(installmentSync['due_date'] ?? installment['dueDate']),
          ),
          openingBalanceLabel: currency.format(openingBalance),
          interestLabel: currency.format(interestAmount),
          principalLabel: currency.format(principalAmount),
          totalAmountLabel: currency.format(totalAmount),
          paidAmountLabel: currency.format(paidAmount),
          pendingAmountLabel: currency.format(pendingAmount),
          endingBalanceLabel: currency.format(endingBalance),
          statusLabel: statusLabel,
          statusTone: statusTone,
        ),
      );

      runningBalance = endingBalance;
    }

    final totalPaid =
        (detail['payments'] as List<dynamic>? ?? const <dynamic>[])
            .map(_map)
            .fold<double>(0, (sum, payment) {
              final paymentSync = _map(payment['syncPayload']);
              return sum +
                  _firstNumber([paymentSync['amount_paid'], payment['amount']]);
            });

    final firstInstallmentAmount = installmentMaps.isNotEmpty
        ? _firstNumber([
            _map(installmentMaps.first['syncPayload'])['total_amount'],
            installmentMaps.first['amount'],
          ])
        : 0;

    final payments =
        (detail['payments'] as List<dynamic>? ?? const <dynamic>[])
            .map(_map)
            .toList(growable: false)
          ..sort(
            (a, b) =>
                _date(b['paymentDate']).compareTo(_date(a['paymentDate'])),
          );

    final paymentRows = payments
        .map((payment) {
          final paymentSync = _map(payment['syncPayload']);
          final amount = _firstNumber([
            paymentSync['amount_paid'],
            payment['amount'],
          ]);
          final installment = _map(payment['installment']);
          final installmentNumber = _firstInt([
            paymentSync['numero_cuota'],
            paymentSync['installment_number'],
            installment['installmentNumber'],
          ], fallback: 0);
          final reference = _string(payment['reference']);
          final method = _string(payment['method'], fallback: 'Pago');
          final title = installmentNumber > 0
              ? '${_paymentMethodLabel(method)}  ·  Cuota $installmentNumber'
              : _paymentMethodLabel(method);
          final subtitleParts = <String>[
            _formatDate(
              _date(paymentSync['payment_date'] ?? payment['paymentDate']),
            ),
            if (reference.isNotEmpty) reference,
            if (_string(payment['notes']).isNotEmpty) _string(payment['notes']),
          ];
          return _PaymentViewRow(
            title: title,
            subtitle: subtitleParts.join('  •  '),
            amountLabel: currency.format(amount),
            icon: _paymentIcon(method),
          );
        })
        .toList(growable: false);

    final fixedInstallment = firstInstallmentAmount > 0
        ? firstInstallmentAmount
        : (termMonths > 0 ? totalPlan / termMonths : totalPlan);
    final targetTerm = math.max(termMonths, installments.length);
    final remainingInstallmentsCount = math.max(
      installments.length - paidInstallmentsCount,
      0,
    );
    final effectivePaidInitialPayment = paidInitialPayment > 0
        ? paidInitialPayment
        : math.min(totalPaid, requiredInitialPayment);
    final statusRaw = _string(detail['status'], fallback: 'active');
    final statusLabel = _saleStatusLabel(statusRaw);
    final statusTone = _saleStatusTone(statusRaw, pendingBalance);
    final saleDateHeaderLabel = _formatDate(saleDate);
    final headerSubtitleParts = <String>[
      lotDisplayLabel,
      if (lotCodeLabel.trim().isNotEmpty && lotCodeLabel != lotDisplayLabel)
        lotCodeLabel,
      if (_string(detail['contractNumber']).isNotEmpty)
        _string(detail['contractNumber']),
      if (saleDateHeaderLabel != '-') saleDateHeaderLabel,
    ];

    return _SaleDetailViewModel(
      saleId: saleId,
      clientName: clientName,
      clientDocumentId: clientDocumentId,
      lotCodeLabel: lotCodeLabel,
      lotDisplayLabel: lotDisplayLabel,
      lotAreaLabel: lotArea > 0 ? '${lotArea.toStringAsFixed(2)} m²' : '',
      pricePerSquareMeterLabel: pricePerSquareMeter > 0
          ? '${currency.format(pricePerSquareMeter)} /m²'
          : '',
      saleDateLabel: saleDateHeaderLabel == '-' ? '' : saleDateHeaderLabel,
      activationDateLabel: _formatDate(activationDate) == '-'
          ? ''
          : _formatDate(activationDate),
      initialDeadlineLabel: _formatDate(initialDeadline) == '-'
          ? ''
          : _formatDate(initialDeadline),
      userName: _string(user['fullName']),
      sellerName: _string(seller['name']),
      sellerDocumentId: _string(seller['documentId']),
      sellerPhone: _string(seller['phone']),
      contractNumber: _string(detail['contractNumber']),
      statusLabel: statusLabel,
      statusTone: statusTone,
      salePriceLabel: currency.format(salePrice),
      fixedInstallmentLabel: currency.format(fixedInstallment),
      pendingBalanceLabel: currency.format(pendingBalance),
      remainingInstallmentsLabel: '$remainingInstallmentsCount cuotas',
      requiredInitialPaymentLabel: currency.format(requiredInitialPayment),
      paidInitialPaymentLabel: currency.format(effectivePaidInitialPayment),
      activeTermLabel: '${installments.length}/$targetTerm',
      totalCapitalLabel: currency.format(totalCapital),
      totalInterestLabel: currency.format(totalInterest),
      totalPlanLabel: currency.format(
        totalPlan > 0 ? totalPlan : _firstNumber([detail['totalAmount']]),
      ),
      notes: _string(detail['notes']),
      headerSubtitle: headerSubtitleParts
          .where((item) => item.trim().isNotEmpty)
          .join('  •  '),
      installments: installments,
      payments: paymentRows,
      paidInstallmentsCount: paidInstallmentsCount,
      remainingInstallmentsCount: remainingInstallmentsCount,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _fullName(Map<String, dynamic> map, {String fallback = ''}) {
    final fullName = _string(map['fullName']);
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final firstName = _string(map['firstName']);
    final lastName = _string(map['lastName']);
    final combined = '$firstName $lastName'.trim();
    return combined.isEmpty ? fallback : combined;
  }

  static double _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _firstNumber(List<Object?> values) {
    for (final value in values) {
      final parsed = _number(value);
      if (parsed != 0 || value == 0 || value == 0.0) {
        return parsed;
      }
    }
    return 0;
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _firstInt(List<Object?> values, {int fallback = 0}) {
    for (final value in values) {
      final parsed = _int(value);
      if (parsed != 0 || value == 0) {
        return parsed;
      }
    }
    return fallback;
  }

  static DateTime _date(Object? value) {
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _formatDate(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) {
      return '-';
    }
    return DateFormat('dd/MM/yyyy').format(value.toLocal());
  }

  static String _saleStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'completed':
      case 'completada':
        return 'completada';
      case 'cancelled':
      case 'cancelada':
        return 'cancelada';
      case 'overdue':
      case 'vencida':
        return 'vencida';
      default:
        return 'activa';
    }
  }

  static _StatusTone _saleStatusTone(String status, double pendingBalance) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'completed' ||
        normalized == 'completada' ||
        pendingBalance <= 0.009) {
      return const _StatusTone(Color(0xFFEAF4ED), Color(0xFF2F6F5C));
    }
    if (normalized == 'cancelled' || normalized == 'cancelada') {
      return const _StatusTone(Color(0xFFFBE6E0), Color(0xFFB05233));
    }
    if (normalized == 'overdue' || normalized == 'vencida') {
      return const _StatusTone(Color(0xFFFFF1E3), Color(0xFFD87A0E));
    }
    return const _StatusTone(Color(0xFFEAF0F7), Color(0xFF223048));
  }

  static String _installmentStatusLabel(String status, double pendingAmount) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'paid' ||
        normalized == 'pagada' ||
        pendingAmount <= 0.009) {
      return 'pagada';
    }
    if (normalized == 'partial' || normalized == 'parcial') {
      return 'parcial';
    }
    if (normalized == 'overdue' || normalized == 'vencida') {
      return 'vencida';
    }
    if (normalized == 'cancelled' || normalized == 'cancelada') {
      return 'cancelada';
    }
    return 'pendiente';
  }

  static _StatusTone _installmentStatusTone(
    String status,
    double pendingAmount,
  ) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'paid' ||
        normalized == 'pagada' ||
        pendingAmount <= 0.009) {
      return const _StatusTone(Color(0xFFF1F8EE), Color(0xFF3B8F2D));
    }
    if (normalized == 'partial' || normalized == 'parcial') {
      return const _StatusTone(Color(0xFFEAF0FF), Color(0xFF2E5AAC));
    }
    if (normalized == 'overdue' || normalized == 'vencida') {
      return const _StatusTone(Color(0xFFFFF1E3), Color(0xFFD87A0E));
    }
    if (normalized == 'cancelled' || normalized == 'cancelada') {
      return const _StatusTone(Color(0xFFFBE6E0), Color(0xFFB05233));
    }
    return const _StatusTone(Color(0xFFFFF6E8), Color(0xFFE08A1A));
  }

  static String _paymentMethodLabel(String method) {
    switch (method.trim().toLowerCase()) {
      case 'cash':
      case 'efectivo':
        return 'Efectivo';
      case 'transfer':
      case 'transferencia':
        return 'Transferencia';
      case 'card':
      case 'tarjeta':
        return 'Tarjeta';
      case 'check':
      case 'cheque':
        return 'Cheque';
      default:
        final normalized = method.trim();
        if (normalized.isEmpty) {
          return 'Pago';
        }
        return '${normalized[0].toUpperCase()}${normalized.substring(1).toLowerCase()}';
    }
  }

  static IconData _paymentIcon(String method) {
    switch (method.trim().toLowerCase()) {
      case 'card':
      case 'tarjeta':
        return Icons.credit_card_outlined;
      case 'transfer':
      case 'transferencia':
        return Icons.swap_horiz_rounded;
      case 'check':
      case 'cheque':
        return Icons.receipt_long_outlined;
      default:
        return Icons.payments_outlined;
    }
  }
}

class _InstallmentViewRow {
  const _InstallmentViewRow({
    required this.installmentNumber,
    required this.dueDateLabel,
    required this.openingBalanceLabel,
    required this.interestLabel,
    required this.principalLabel,
    required this.totalAmountLabel,
    required this.paidAmountLabel,
    required this.pendingAmountLabel,
    required this.endingBalanceLabel,
    required this.statusLabel,
    required this.statusTone,
  });

  final int installmentNumber;
  final String dueDateLabel;
  final String openingBalanceLabel;
  final String interestLabel;
  final String principalLabel;
  final String totalAmountLabel;
  final String paidAmountLabel;
  final String pendingAmountLabel;
  final String endingBalanceLabel;
  final String statusLabel;
  final _StatusTone statusTone;
}

class _PaymentViewRow {
  const _PaymentViewRow({
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String amountLabel;
  final IconData icon;
}
