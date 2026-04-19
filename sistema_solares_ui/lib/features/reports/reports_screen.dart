import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'dart:math' as math;
import 'package:sistema_solares_ui/features/dashboard/dashboard_service.dart';
import 'package:sistema_solares_ui/features/reports/reports_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 30;
  Future<_ReportsScreenData>? _future;
  int _lastTick = -1;

  void _reloadFor(int days) {
    setState(() {
      _days = days;
      _future = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = _loadData(context);
    }

    return FutureBuilder<_ReportsScreenData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: () => _reloadFor(_days),
          );
        }

        final data = snapshot.data!;
        final summary = data.dashboard;
        final reports = data.reports;
        final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
        final compact = MediaQuery.sizeOf(context).width < 760;

        final totalPortfolio = _asNum(summary.summary['totalPortfolio']);
        final totalCollected = _asNum(summary.summary['totalCollected']);
        final outstanding = _asNum(summary.summary['outstanding']);
        final products = _asInt(summary.summary['products']);
        final clients = _asInt(summary.summary['clients']);
        final activeSales = _asInt(summary.summary['activeSales']);
        final overdueInstallments = _asInt(
          summary.summary['overdueInstallments'],
        );

        final salesCount = reports.sales.length;
        final paymentsCount = reports.payments.length;
        final delinquencyCount = reports.delinquency.length;
        final salesTotal = _sumAmount(reports.sales, 'totalAmount');
        final paymentsTotal = _sumAmount(reports.payments, 'amount');
        final delinquencyTotal = _sumAmount(reports.delinquency, 'amountDue');

        final metrics = [
          _StatCardData(
            label: 'Clientes',
            value: '$clients',
            icon: Icons.people_outline,
            accentColor: const Color(0xFF173450),
          ),
          _StatCardData(
            label: 'Solares',
            value: '$products',
            icon: Icons.map_outlined,
            accentColor: const Color(0xFF204A71),
          ),
          _StatCardData(
            label: 'Ventas activas',
            value: '$activeSales',
            icon: Icons.domain_verification_outlined,
            accentColor: const Color(0xFF2E7D5B),
          ),
          _StatCardData(
            label: 'Pagos del periodo',
            value: '$paymentsCount',
            icon: Icons.payments_outlined,
            accentColor: const Color(0xFFB66A12),
          ),
          _StatCardData(
            label: 'Cuotas vencidas',
            value: '$overdueInstallments',
            icon: Icons.warning_amber_rounded,
            accentColor: const Color(0xFF8E3A59),
          ),
        ];

        final detailCards = [
          _ReportCard(
            title: 'Ventas del periodo',
            value: '$salesCount',
            accentColor: const Color(0xFF173450),
            segments: [
              _ReportSegment(
                label: 'Monto vendido',
                value: currency.format(salesTotal),
              ),
              _ReportSegment(label: 'Ventas activas', value: '$activeSales'),
            ],
          ),
          _ReportCard(
            title: 'Pagos del periodo',
            value: '$paymentsCount',
            accentColor: const Color(0xFF0D2844),
            segments: [
              _ReportSegment(
                label: 'Monto cobrado',
                value: currency.format(paymentsTotal),
              ),
              _ReportSegment(
                label: 'Cartera total',
                value: currency.format(totalPortfolio),
              ),
            ],
          ),
          _ReportCard(
            title: 'Morosidad',
            value: '$delinquencyCount',
            accentColor: const Color(0xFF8E3A59),
            segments: [
              _ReportSegment(
                label: 'Saldo vencido',
                value: currency.format(delinquencyTotal),
              ),
              _ReportSegment(
                label: 'Pendiente',
                value: currency.format(outstanding),
              ),
            ],
          ),
        ];

        final mobileSummaryCards = [
          _StatCardData(
            label: 'Cartera',
            value: currency.format(totalPortfolio),
            icon: Icons.account_balance_wallet_outlined,
            accentColor: const Color(0xFF173450),
          ),
          _StatCardData(
            label: 'Cobrado',
            value: currency.format(totalCollected),
            icon: Icons.task_alt_outlined,
            accentColor: const Color(0xFF2E7D5B),
          ),
          _StatCardData(
            label: 'Pendiente',
            value: currency.format(outstanding),
            icon: Icons.schedule_outlined,
            accentColor: const Color(0xFFB66A12),
          ),
          _StatCardData(
            label: 'Ventas',
            value: '$salesCount',
            icon: Icons.point_of_sale_outlined,
            accentColor: const Color(0xFF204A71),
          ),
          _StatCardData(
            label: 'Pagos',
            value: '$paymentsCount',
            icon: Icons.payments_outlined,
            accentColor: const Color(0xFF94611A),
          ),
          _StatCardData(
            label: 'Vencidas',
            value: '$overdueInstallments',
            icon: Icons.warning_amber_rounded,
            accentColor: const Color(0xFF8E3A59),
          ),
        ];

        if (compact) {
          return DesktopPageScaffold(
            title: 'Reportes',
            subtitle:
                'Resumen prioritario del periodo con foco en ventas y cobranza.',
            toolbar: DesktopFieldToolbar(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...[7, 30, 90].map(
                      (days) => ChoiceChip(
                        label: Text('$days dias'),
                        selected: _days == days,
                        onSelected: (_) => _reloadFor(days),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: ListView(
              children: [
                _CompactMetricsPanel(cards: mobileSummaryCards),
                const SizedBox(height: 12),
                _CompactFocusCard(
                  title: 'Actividad comercial',
                  accentColor: const Color(0xFF173450),
                  items: [
                    _CompactFocusItem(
                      label: 'Ventas del periodo',
                      value: currency.format(salesTotal),
                    ),
                    _CompactFocusItem(
                      label: 'Ventas activas',
                      value: '$activeSales',
                    ),
                    _CompactFocusItem(
                      label: 'Clientes activos',
                      value: '$clients',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _CompactFocusCard(
                  title: 'Cobranza prioritaria',
                  accentColor: const Color(0xFF8E3A59),
                  items: [
                    _CompactFocusItem(
                      label: 'Cobrado',
                      value: currency.format(paymentsTotal),
                    ),
                    _CompactFocusItem(
                      label: 'Saldo vencido',
                      value: currency.format(delinquencyTotal),
                    ),
                    _CompactFocusItem(
                      label: 'Cuotas vencidas',
                      value: '$overdueInstallments',
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        final salesRows = reports.sales.map((item) {
          return [
            item['client']?['firstName']?.toString() ?? '-',
            item['product']?['name']?.toString() ?? '-',
            item['status']?.toString() ?? '-',
            currency.format(item['totalAmount'] ?? 0),
          ];
        }).toList();

        final paymentsRows = reports.payments.map((item) {
          return [
            item['sale']?['client']?['firstName']?.toString() ?? '-',
            item['method']?.toString() ?? '-',
            item['paymentDate']?.toString().split('T').first ?? '-',
            currency.format(item['amount'] ?? 0),
          ];
        }).toList();

        final delinquencyRows = reports.delinquency.map((item) {
          return [
            item['sale']?['client']?['firstName']?.toString() ?? '-',
            item['sale']?['product']?['name']?.toString() ?? '-',
            item['dueDate']?.toString().split('T').first ?? '-',
            currency.format(item['amountDue'] ?? 0),
          ];
        }).toList();

        return DesktopPageScaffold(
          title: 'Reporte',
          subtitle:
              'Vista unificada y ordenada del resumen general y la operacion del periodo.',
          toolbar: DesktopFieldToolbar(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Corte operativo:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...[7, 30, 90].map(
                    (days) => ChoiceChip(
                      label: Text('Ultimos $days dias'),
                      selected: _days == days,
                      onSelected: (_) => _reloadFor(days),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: ListView(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1180;
                  final medium = constraints.maxWidth >= 820;

                  final metricsPanel = _MetricsPanel(
                    cards: metrics,
                    columns: wide
                        ? 3
                        : medium
                        ? 2
                        : 1,
                  );

                  final activityCard = _ReportCard(
                    title: 'Actividad comercial',
                    value: '$activeSales',
                    accentColor: const Color(0xFF173450),
                    compact: !wide,
                    segments: [
                      _ReportSegment(label: 'Clientes', value: '$clients'),
                      _ReportSegment(label: 'Solares', value: '$products'),
                      _ReportSegment(
                        label: 'Ventas periodo',
                        value: '$salesCount',
                      ),
                    ],
                  );

                  final collectionsCard = _ReportCard(
                    title: 'Seguimiento de cobros',
                    value: currency.format(outstanding),
                    accentColor: const Color(0xFF0D2844),
                    compact: !wide,
                    segments: [
                      _ReportSegment(
                        label: 'Cobrado',
                        value: currency.format(totalCollected),
                      ),
                      _ReportSegment(
                        label: 'Vencidas',
                        value: '$overdueInstallments',
                      ),
                      _ReportSegment(
                        label: 'Saldo vencido',
                        value: currency.format(delinquencyTotal),
                      ),
                    ],
                  );

                  final priorityCard = _CollectionPriorityCard(
                    title: 'Pulso del periodo',
                    summary:
                        'Los indicadores que mas conviene vigilar en el rango seleccionado.',
                    description:
                        'Compara ventas, pagos y cuotas vencidas para detectar rapido donde esta la carga operativa.',
                    bars: [
                      _PriorityBar(
                        label: 'Ventas',
                        value: salesCount,
                        color: const Color(0xFF1B5E8C),
                      ),
                      _PriorityBar(
                        label: 'Pagos',
                        value: paymentsCount,
                        color: const Color(0xFFCF8B17),
                      ),
                      _PriorityBar(
                        label: 'Morosidad',
                        value: delinquencyCount,
                        color: const Color(0xFFB3261E),
                      ),
                    ],
                  );

                  final overview = _ExecutiveOverviewCard(
                    totalPortfolio: currency.format(totalPortfolio),
                    totalCollected: currency.format(totalCollected),
                    outstanding: currency.format(outstanding),
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            children: [
                              metricsPanel,
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: activityCard),
                                  const SizedBox(width: 16),
                                  Expanded(child: collectionsCard),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              priorityCard,
                              const SizedBox(height: 16),
                              overview,
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  if (medium) {
                    return Column(
                      children: [
                        overview,
                        const SizedBox(height: 16),
                        metricsPanel,
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: priorityCard),
                            const SizedBox(width: 16),
                            Expanded(child: activityCard),
                          ],
                        ),
                        const SizedBox(height: 16),
                        collectionsCard,
                      ],
                    );
                  }

                  return Column(
                    children: [
                      overview,
                      const SizedBox(height: 16),
                      metricsPanel,
                      const SizedBox(height: 16),
                      priorityCard,
                      const SizedBox(height: 16),
                      activityCard,
                      const SizedBox(height: 16),
                      collectionsCard,
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const _SectionHeader(
                title: 'Detalle del periodo',
                subtitle:
                    'Desglose operativo del corte seleccionado para ventas, pagos y morosidad.',
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1080;
                  final medium = constraints.maxWidth >= 720;

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: detailCards[0]),
                        const SizedBox(width: 16),
                        Expanded(child: detailCards[1]),
                        const SizedBox(width: 16),
                        Expanded(child: detailCards[2]),
                      ],
                    );
                  }

                  if (medium) {
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: detailCards[0]),
                            const SizedBox(width: 16),
                            Expanded(child: detailCards[1]),
                          ],
                        ),
                        const SizedBox(height: 16),
                        detailCards[2],
                      ],
                    );
                  }

                  return Column(
                    children: [
                      detailCards[0],
                      const SizedBox(height: 16),
                      detailCards[1],
                      const SizedBox(height: 16),
                      detailCards[2],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _ReportTable(
                title: 'Ventas',
                compact: compact,
                columns: const ['Cliente', 'Solar', 'Estado', 'Total'],
                rows: salesRows,
                emptyTitle: 'Sin ventas en el periodo',
                emptyMessage:
                    'Amplia el rango o espera nueva sincronizacion para ver ventas recientes.',
              ),
              const SizedBox(height: 16),
              _ReportTable(
                title: 'Pagos',
                compact: compact,
                columns: const ['Cliente', 'Metodo', 'Fecha', 'Monto'],
                rows: paymentsRows,
                emptyTitle: 'Sin pagos en el periodo',
                emptyMessage:
                    'No hay pagos sincronizados dentro del rango seleccionado.',
              ),
              const SizedBox(height: 16),
              _ReportTable(
                title: 'Morosidad',
                compact: compact,
                columns: const ['Cliente', 'Solar', 'Vencimiento', 'Saldo'],
                rows: delinquencyRows,
                emptyTitle: 'Sin cuotas vencidas',
                emptyMessage:
                    'La cartera no reporta morosidad para este corte.',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_ReportsScreenData> _loadData(BuildContext context) async {
    final apiClient = context.read<ApiClient>();
    final results = await Future.wait<dynamic>([
      DashboardService(apiClient).fetchSnapshot(),
      ReportsService(apiClient).fetchBundle(days: _days),
    ]);

    return _ReportsScreenData(
      dashboard: results[0] as DashboardSnapshot,
      reports: results[1] as ReportsBundle,
    );
  }

  double _sumAmount(List<Map<String, dynamic>> items, String key) {
    return items.fold<double>(0, (total, item) => total + _asNum(item[key]));
  }

  int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _ReportsScreenData {
  const _ReportsScreenData({required this.dashboard, required this.reports});

  final DashboardSnapshot dashboard;
  final ReportsBundle reports;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF173450),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF6B7682),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.cards, required this.columns});

  final List<_StatCardData> cards;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 12.0;
        final safeColumns = columns <= 0 ? 1 : columns;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        final normalizedWidth = math.max(availableWidth, 240.0);
        final itemWidth = safeColumns == 1
            ? normalizedWidth
            : math.max(
                (normalizedWidth - (gap * (safeColumns - 1))) / safeColumns,
                220.0,
              );

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: itemWidth,
                child: _StatCard(data: card),
              ),
          ],
        );
      },
    );
  }
}

class _CompactMetricsPanel extends StatelessWidget {
  const _CompactMetricsPanel({required this.cards});

  final List<_StatCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        const gap = 10.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final itemWidth = math.max(
          (availableWidth - (gap * (columns - 1))) / columns,
          92.0,
        );

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: itemWidth,
                child: _CompactStatCard(data: card),
              ),
          ],
        );
      },
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
}

class _CompactStatCard extends StatelessWidget {
  const _CompactStatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EBF3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0810263D),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: data.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(data.icon, size: 16, color: data.accentColor),
            ),
            const SizedBox(height: 10),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6B7682),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: data.accentColor,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFocusItem {
  const _CompactFocusItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _CompactFocusCard extends StatelessWidget {
  const _CompactFocusCard({
    required this.title,
    required this.accentColor,
    required this.items,
  });

  final String title;
  final Color accentColor;
  final List<_CompactFocusItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE4EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF173450),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Divider(height: 16, color: accentColor.withValues(alpha: 0.12)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      items[index].label,
                      style: const TextStyle(
                        color: Color(0xFF6B7682),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    items[index].value,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, data.accentColor.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DFD2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: data.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(data.icon, color: data.accentColor),
            ),
            const SizedBox(height: 12),
            Text(
              data.label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              data.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: data.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutiveOverviewCard extends StatelessWidget {
  const _ExecutiveOverviewCard({
    required this.totalPortfolio,
    required this.totalCollected,
    required this.outstanding,
  });

  final String totalPortfolio;
  final String totalCollected;
  final String outstanding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2844), Color(0xFF071829)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumen operativo',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Vista rapida del inventario, la cobranza y las ventas que requieren seguimiento.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.74),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _OverviewMetric(label: 'Cartera total', value: totalPortfolio),
                _OverviewMetric(label: 'Cobrado', value: totalCollected),
                _OverviewMetric(label: 'Pendiente', value: outstanding),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xB3FFFFFF))),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionPriorityCard extends StatelessWidget {
  const _CollectionPriorityCard({
    required this.title,
    required this.summary,
    required this.description,
    required this.bars,
  });

  final String title;
  final String summary;
  final String description;
  final List<_PriorityBar> bars;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE4EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF173450),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              summary,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7682)),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8A94A3),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < bars.length; index++) ...[
                    Expanded(
                      child: _PriorityBarView(bar: bars[index], bars: bars),
                    ),
                    if (index != bars.length - 1) const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityBar {
  const _PriorityBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _PriorityBarView extends StatelessWidget {
  const _PriorityBarView({required this.bar, required this.bars});

  final _PriorityBar bar;
  final List<_PriorityBar> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<int>(
      1,
      (max, item) => item.value > max ? item.value : max,
    );
    final heightFactor = bar.value <= 0 ? 0.08 : bar.value / maxValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${bar.value}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF173450),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: heightFactor.clamp(0.08, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0D2844),
                      bar.color.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: bar.color.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          bar.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7682),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.value,
    required this.accentColor,
    required this.segments,
    this.compact = false,
  });

  final String title;
  final String value;
  final Color accentColor;
  final List<_ReportSegment> segments;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE4EAF2)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5B6672),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final segment in segments)
                  SizedBox(
                    width: segments.length == 2
                        ? null
                        : compact
                        ? 98
                        : 110,
                    child: _ReportMetricTile(segment: segment),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSegment {
  const _ReportSegment({required this.label, required this.value});

  final String label;
  final String value;
}

class _ReportMetricTile extends StatelessWidget {
  const _ReportMetricTile({required this.segment});

  final _ReportSegment segment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5EE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              segment.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF6B7682),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              segment.value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF1D3550),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.title,
    required this.compact,
    required this.columns,
    required this.rows,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final String title;
  final bool compact;
  final List<String> columns;
  final List<List<String>> rows;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return DesktopDataListSection(
        title: title,
        children: rows.isEmpty
            ? [
                DesktopEmptyState(
                  icon: Icons.table_rows_outlined,
                  title: emptyTitle,
                  message: emptyMessage,
                ),
              ]
            : rows.map((row) {
                final details = row.length > 2
                    ? row.sublist(1, row.length - 1).join('\n')
                    : '';
                return DesktopListRow(
                  height: 112,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: Color(0xFF223048),
                    ),
                  ),
                  title: Text(
                    row.first,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    details,
                    style: const TextStyle(color: Color(0xFF6E7791)),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: DesktopTag(
                    label: row.last,
                    background: const Color(0xFFF6EFE3),
                    foreground: const Color(0xFF8C5A2C),
                  ),
                );
              }).toList(),
      );
    }

    return DesktopTableCard(
      title: title,
      child: rows.isEmpty
          ? DesktopEmptyState(
              icon: Icons.table_rows_outlined,
              title: emptyTitle,
              message: emptyMessage,
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: columns
                    .map((label) => DataColumn(label: Text(label)))
                    .toList(),
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: row.map((cell) => DataCell(Text(cell))).toList(),
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}
