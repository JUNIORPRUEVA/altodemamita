import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../../shared/widgets/base_layout.dart';
import '../../clients/data/client_repository.dart';
import '../../installments/data/installments_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale_summary.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.clientRepository,
    required this.lotRepository,
    required this.salesRepository,
    required this.installmentsRepository,
  });

  final ClientRepository clientRepository;
  final LotRepository lotRepository;
  final SalesRepository salesRepository;
  final InstallmentsRepository installmentsRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientRepository != widget.clientRepository ||
        oldWidget.lotRepository != widget.lotRepository ||
        oldWidget.salesRepository != widget.salesRepository ||
        oldWidget.installmentsRepository != widget.installmentsRepository) {
      _statsFuture = _loadStats();
    }
  }

  Future<_DashboardStats> _loadStats() async {
    final results = await Future.wait<dynamic>([
      widget.clientRepository.countAll(),
      widget.lotRepository.countAll(),
      widget.lotRepository.countByStatus('disponible'),
      widget.lotRepository.countByStatus('vendido'),
      widget.salesRepository.fetchAll(),
      widget.installmentsRepository.getAll(),
    ]);

    final sales = results[4] as List<SaleSummary>;
    final installments = results[5] as List<dynamic>;

    final pendingPayments = installments
        .where((item) => item.calculatedStatus != 'pagada')
        .length;
    final overduePayments = installments
        .where((item) => item.calculatedStatus == 'vencida')
        .length;
    final incompleteInitialPayments = sales
        .where((sale) => sale.pendingInitialPayment > 0.009)
        .length;
    final activeFinancing = sales
        .where((sale) => sale.status == 'activa' && sale.pendingBalance > 0.009)
        .length;
    final portfolioPendingAmount = sales.fold<double>(
      0,
      (total, sale) => total + sale.pendingInitialPayment + sale.pendingBalance,
    );
    final collectedAmount = sales.fold<double>(
      0,
      (total, sale) =>
          total +
          sale.paidInitialPayment +
          (sale.salePrice - sale.pendingBalance - sale.downPaymentAmount),
    );

    return _DashboardStats(
      totalClients: results[0],
      totalLots: results[1],
      availableLots: results[2],
      soldLots: results[3],
      pendingPayments: pendingPayments,
      incompleteInitialPayments: incompleteInitialPayments,
      overduePayments: overduePayments,
      activeFinancing: activeFinancing,
      portfolioPendingAmount: portfolioPendingAmount,
      collectedAmount: collectedAmount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Panel Principal',
      child: FutureBuilder<_DashboardStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data ?? const _DashboardStats.empty();
          final dataAlerts = _buildDataAlerts(stats);

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isDesktop = width >= 1200;
              final isMedium = width >= 860;

              if (isDesktop) {
                return SingleChildScrollView(
                  child: SizedBox(
                    width: width,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (dataAlerts.isNotEmpty) ...[
                                _DashboardDataAlert(messages: dataAlerts),
                                const SizedBox(height: 16),
                              ],
                              _MetricsPanel(stats: stats, columns: 3),
                              const SizedBox(height: 24),
                              _InsightPanels(
                                stats: stats,
                                stacked: false,
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CollectionPriorityCard(stats: stats),
                              const SizedBox(height: 24),
                              _ExecutiveOverview(stats: stats, compact: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (isMedium) {
                return SingleChildScrollView(
                  child: SizedBox(
                    width: width,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (dataAlerts.isNotEmpty) ...[
                                _DashboardDataAlert(messages: dataAlerts),
                                const SizedBox(height: 16),
                              ],
                              _MetricsPanel(stats: stats, columns: 2),
                              const SizedBox(height: 16),
                              _InventoryCard(stats: stats, compact: true),
                              const SizedBox(height: 16),
                              _ExecutiveOverview(stats: stats, compact: true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CollectionPriorityCard(stats: stats),
                              const SizedBox(height: 16),
                              _CollectionsCard(stats: stats, compact: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView(
                children: [
                  if (dataAlerts.isNotEmpty) ...[
                    _DashboardDataAlert(messages: dataAlerts),
                    const SizedBox(height: 16),
                  ],
                  _MetricsPanel(stats: stats, columns: 1),
                  const SizedBox(height: 16),
                  _CollectionPriorityCard(stats: stats),
                  const SizedBox(height: 16),
                  _InventoryCard(stats: stats),
                  const SizedBox(height: 16),
                  _CollectionsCard(stats: stats),
                  const SizedBox(height: 16),
                  _ExecutiveOverview(stats: stats, compact: true),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

List<String> _buildDataAlerts(_DashboardStats stats) {
  final alerts = <String>[];

  if (stats.totalClients > 0 && stats.totalLots == 0) {
    alerts.add(
      'Hay clientes en la base local, pero no hay solares sincronizados. El resumen está leyendo SQLite local; esto suele indicar que el scope products no llegó o que el backend no devolvió productos con payload válido de solar.',
    );
  }

  if (stats.totalLots > 0 && stats.soldLots == 0 && stats.pendingPayments == 0) {
    alerts.add(
      'El inventario local existe, pero no hay ventas ni cuotas aplicadas. Si en nube sí existen, revisa el scope sales/installments del sync.',
    );
  }

  return alerts;
}

class _DashboardDataAlert extends StatelessWidget {
  const _DashboardDataAlert({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: const Color(0xFFFFF8E8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFF1D28D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.info_outline,
                color: Color(0xFF9A5B00),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado real de datos locales',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF6E4300),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final message in messages) ...[
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF6E4300),
                      ),
                    ),
                    if (message != messages.last) const SizedBox(height: 6),
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

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.stats, required this.columns});

  final _DashboardStats stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        label: 'Clientes',
        value: stats.totalClients.toString(),
        icon: Icons.people_outline,
        accentColor: const Color(0xFF173450),
      ),
      _StatCard(
        label: 'Solares',
        value: stats.totalLots.toString(),
        icon: Icons.map_outlined,
        accentColor: const Color(0xFF204A71),
      ),
      _StatCard(
        label: 'Vendidos',
        value: stats.soldLots.toString(),
        icon: Icons.check_circle_outline,
        accentColor: const Color(0xFF2E7D5B),
      ),
      _StatCard(
        label: 'Pagos pendientes',
        value: stats.pendingPayments.toString(),
        icon: Icons.payments_outlined,
        accentColor: const Color(0xFFB66A12),
      ),
      _StatCard(
        label: 'Inicial incompleto',
        value: stats.incompleteInitialPayments.toString(),
        icon: Icons.timelapse_outlined,
        accentColor: const Color(0xFF8E3A59),
      ),
    ];

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
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _ExecutiveOverview extends StatelessWidget {
  const _ExecutiveOverview({required this.stats, this.compact = false});

  final _DashboardStats stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = compact ? 16.0 : 18.0;
    final verticalPadding = compact ? 16.0 : 18.0;

    return Container(
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
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 44 : 48,
                  height: compact ? 44 : 48,
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
                        'Vista rápida del inventario, la cobranza y las ventas que requieren seguimiento.',
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
                _HeroMetric(
                  label: 'Cobro pendiente total',
                  value: _formatCurrency(stats.portfolioPendingAmount),
                ),
                _HeroMetric(
                  label: 'Cobrado registrado',
                  value: _formatCurrency(stats.collectedAmount),
                ),
                _HeroMetric(
                  label: 'Financiamientos activos',
                  value: '${stats.activeFinancing}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightPanels extends StatelessWidget {
  const _InsightPanels({
    required this.stats,
    required this.stacked,
    this.compact = false,
  });

  final _DashboardStats stats;
  final bool stacked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final inventoryCard = _InventoryCard(stats: stats, compact: compact);
    final collectionsCard = _CollectionsCard(stats: stats, compact: compact);

    if (!stacked) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.maxWidth.isFinite) {
            return Column(
              children: [
                inventoryCard,
                const SizedBox(height: 16),
                collectionsCard,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: inventoryCard),
              const SizedBox(width: 16),
              Expanded(child: collectionsCard),
            ],
          );
        },
      );
    }

    return Column(
      children: [inventoryCard, const SizedBox(height: 16), collectionsCard],
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({required this.stats, this.compact = false});

  final _DashboardStats stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Inventario',
      value: stats.totalLots.toString(),
      accentColor: const Color(0xFF173450),
      compact: compact,
      segments: [
        _ReportSegment(label: 'Disponibles', value: stats.availableLots),
        _ReportSegment(label: 'Vendidos', value: stats.soldLots),
      ],
    );
  }
}

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard({required this.stats, this.compact = false});

  final _DashboardStats stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Seguimiento de cobros',
      value: stats.pendingPayments.toString(),
      accentColor: const Color(0xFF0D2844),
      compact: compact,
      segments: [
        _ReportSegment(
          label: 'Inicial incompleto',
          value: stats.incompleteInitialPayments,
        ),
        _ReportSegment(label: 'Vencidas', value: stats.overduePayments),
        _ReportSegment(label: 'Activas', value: stats.activeFinancing),
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
              segment.value.toString(),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, accentColor.withValues(alpha: 0.05)],
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionPriorityCard extends StatelessWidget {
  const _CollectionPriorityCard({required this.stats});

  final _DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final bars = [
      _PriorityBar(
        label: 'Cuotas pendientes',
        value: stats.pendingPayments,
        color: const Color(0xFFCF8B17),
      ),
      _PriorityBar(
        label: 'Inicial pendiente',
        value: stats.incompleteInitialPayments,
        color: const Color(0xFF8E3A59),
      ),
      _PriorityBar(
        label: 'Cuotas vencidas',
        value: stats.overduePayments,
        color: const Color(0xFFB3261E),
      ),
    ];

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
              'Pulso de cobranza',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF173450),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Los indicadores que más conviene vigilar hoy.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7682)),
            ),
            const SizedBox(height: 4),
            Text(
              'Muestra cuotas pendientes, ventas con inicial pendiente y cuotas vencidas.',
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

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFBFD0E4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSegment {
  const _ReportSegment({required this.label, required this.value});

  final String label;
  final Object value;
}

class _DashboardStats {
  const _DashboardStats({
    required this.totalClients,
    required this.totalLots,
    required this.availableLots,
    required this.soldLots,
    required this.pendingPayments,
    required this.incompleteInitialPayments,
    required this.overduePayments,
    required this.activeFinancing,
    required this.portfolioPendingAmount,
    required this.collectedAmount,
  });

  const _DashboardStats.empty()
    : totalClients = 0,
      totalLots = 0,
      availableLots = 0,
      soldLots = 0,
      pendingPayments = 0,
      incompleteInitialPayments = 0,
      overduePayments = 0,
      activeFinancing = 0,
      portfolioPendingAmount = 0,
      collectedAmount = 0;

  final int totalClients;
  final int totalLots;
  final int availableLots;
  final int soldLots;
  final int pendingPayments;
  final int incompleteInitialPayments;
  final int overduePayments;
  final int activeFinancing;
  final double portfolioPendingAmount;
  final double collectedAmount;
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

String _formatCurrency(double value) {
  return 'RD\$ ${value.toStringAsFixed(2)}';
}
