import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

import '../../../shared/widgets/base_layout.dart';
import '../../clients/data/client_repository.dart';
import '../../installments/data/installments_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../data/dashboard_stats_store.dart';
import 'widgets/money_metric_text.dart';

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
  late Future<DashboardStats> _statsFuture;
  DashboardStats? _lastGoodStats;
  bool _lastLoadFailed = false;
  final DashboardStatsStore _store = DashboardStatsStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_handleStoreChanged);

    // CACHE-FIRST EN TRES NIVELES:
    // A. snapshot en memoria -> se pinta YA.
    // B. snapshot persistido (SharedPreferences) -> se pinta sin tocar SQLite.
    // C. primera ejecución absoluta -> skeleton corto + lectura local.
    // En ningún caso se espera al sync general para dibujar la pantalla.
    final snapshot = _store.stats;
    if (snapshot != null) {
      _lastGoodStats = snapshot;
      _statsFuture = Future<DashboardStats>.value(snapshot);
      _refreshInBackground();
    } else {
      _statsFuture = _hydrateThenLoad();
    }
  }

  /// Primer pintado SIN depender de SQLite.
  ///
  /// El snapshot persistido vive en SharedPreferences: se lee en milisegundos y
  /// no compite con el writer del sync, que es lo que bloqueaba la pantalla
  /// durante 1-2 minutos.
  Future<DashboardStats> _hydrateThenLoad() async {
    await _store.hydrateFromDisk();
    if (!mounted) {
      return _store.stats ?? const DashboardStats.empty();
    }
    final hydrated = _store.stats;
    if (hydrated != null) {
      setState(() {
        _lastGoodStats = hydrated;
        _lastLoadFailed = false;
        _statsFuture = Future<DashboardStats>.value(hydrated);
      });
      _refreshInBackground();
      return hydrated;
    }
    return _loadStats();
  }

  @override
  void dispose() {
    _store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) {
      return;
    }
    // Una invalidación puede llegar desde la sync en medio de un frame
    // (descarga de pagos/cuotas). En ese caso se difiere al final del frame
    // para no llamar setState durante el build.
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _handleStoreChanged());
      return;
    }
    final stats = _store.stats;
    if (stats != null && !identical(stats, _lastGoodStats)) {
      setState(() {
        _lastGoodStats = stats;
        _lastLoadFailed = false;
        _statsFuture = Future<DashboardStats>.value(stats);
      });
    }
    // Si la invalidación se originó en una operación financiera o en una
    // descarga de nube, el snapshot queda marcado como vencido: se recalcula
    // en background sin quitar de la pantalla lo que ya se está mostrando.
    _refreshInBackground();
  }

  /// Refresco silencioso: nunca bloquea la pantalla ni lanza errores.
  ///
  /// El guardado evita que tres entradas seguidas disparen tres cálculos a la
  /// vez, y `needsRefresh` respeta el intervalo mínimo y el cambio de día.
  void _refreshInBackground() {
    if (!_store.needsRefresh) {
      return;
    }
    unawaited(
      DashboardRefreshGuard.run(() async {
        _store.markRefreshing(true);
        try {
          await _loadStats();
        } catch (_) {
          // El refresco silencioso no puede romper la pantalla.
        } finally {
          _store.markRefreshing(false);
        }
      }),
    );
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

  Future<DashboardStats> _loadStats() async {
    try {
      final stats = await computeDashboardStats(
        clientRepository: widget.clientRepository,
        lotRepository: widget.lotRepository,
        salesRepository: widget.salesRepository,
        installmentsRepository: widget.installmentsRepository,
      );

      _lastGoodStats = stats;
      _lastLoadFailed = false;
      if (mounted) {
        // Publicar el snapshot: sobrevive a la navegación y alimenta el
        // cache-first de la próxima entrada.
        _store.save(stats);
      }
      return stats;
    } catch (_) {
      // Nunca mostrar ceros silenciosos: conservar el ultimo estado valido.
      _lastLoadFailed = true;
      return _lastGoodStats ?? _store.stats ?? const DashboardStats.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Panel Principal',
      child: FutureBuilder<DashboardStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          final fallback = _lastGoodStats ?? _store.stats;
          // NO bloquear con spinner si ya hay snapshot (memoria o disco): se
          // pinta lo que tenemos y el refresco sigue en background.
          // Sólo la primera ejecución absoluta muestra skeleton, y es un
          // skeleton corto con la ESTRUCTURA del panel, nunca pantalla vacía.
          if (snapshot.connectionState != ConnectionState.done &&
              fallback == null) {
            return const _DashboardSkeleton();
          }

          final stats =
              snapshot.data ?? fallback ?? const DashboardStats.empty();
          final dataAlerts = _buildDataAlerts(stats);
          if (_lastLoadFailed) {
            dataAlerts.insert(
              0,
              'No pudimos actualizar los indicadores. Mostrando los últimos datos guardados.',
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isDesktop = width >= 1200;
              final isMedium = width >= 860;
              final isMobile = width < 600;

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

              if (isMobile) {
                return ListView(
                  children: [
                    if (dataAlerts.isNotEmpty) ...[
                      _DashboardDataAlert(messages: dataAlerts),
                      const SizedBox(height: 12),
                    ],
                    _MobileFinancialSummary(stats: stats),
                    const SizedBox(height: 12),
                    _MobileOperationsSummary(stats: stats),
                    const SizedBox(height: 12),
                    _CollectionPriorityCard(stats: stats),
                    const SizedBox(height: 12),
                    _InventoryCard(stats: stats, compact: true),
                  ],
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

class _MobileFinancialSummary extends StatelessWidget {
  const _MobileFinancialSummary({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return _MobileDashboardSection(
      title: 'Resumen financiero',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 340;
          final gap = 10.0;
          final itemWidth = twoColumns
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(
                width: itemWidth,
                child: _CompactKpiCard(
                  label: 'Cobrado',
                  value: _formatCurrency(stats.collectedAmount),
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: const Color(0xFF2E7D5B),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _CompactKpiCard(
                  label: 'Pendiente',
                  value: _formatCurrency(stats.portfolioPendingAmount),
                  icon: Icons.receipt_long_outlined,
                  accentColor: const Color(0xFFB66A12),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: _CompactKpiCard(
                  label: 'Vendido',
                  value: _formatCurrency(stats.soldAmount),
                  icon: Icons.trending_up,
                  accentColor: const Color(0xFF204A71),
                  horizontal: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MobileOperationsSummary extends StatelessWidget {
  const _MobileOperationsSummary({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return _MobileDashboardSection(
      title: 'Operación',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 340;
          final gap = 10.0;
          final itemWidth = twoColumns
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(
                width: itemWidth,
                child: _CompactKpiCard(
                  label: 'Clientes',
                  value: stats.totalClients.toString(),
                  icon: Icons.people_outline,
                  accentColor: const Color(0xFF173450),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _CompactKpiCard(
                  label: 'Solares',
                  value: stats.totalLots.toString(),
                  icon: Icons.map_outlined,
                  accentColor: const Color(0xFF204A71),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MobileDashboardSection extends StatelessWidget {
  const _MobileDashboardSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: const Color(0xFF173450),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _CompactKpiCard extends StatelessWidget {
  const _CompactKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.horizontal = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: accentColor, size: 18),
    );
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF667085),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal ? 14 : 12,
          vertical: 12,
        ),
        child: horizontal
            ? Row(
                children: [
                  iconBox,
                  const SizedBox(width: 12),
                  Expanded(child: labels),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [iconBox, const SizedBox(height: 9), labels],
              ),
      ),
    );
  }
}

List<String> _buildDataAlerts(DashboardStats stats) {
  final alerts = <String>[];

  if (stats.totalClients > 0 && stats.totalLots == 0) {
    alerts.add(
      'Hay clientes en la base local, pero no hay solares sincronizados. El resumen está leyendo SQLite local; esto suele indicar que el scope products no llegó o que el backend no devolvió productos con payload válido de solar.',
    );
  }

  return alerts;
}

/// Skeleton del Resumen: muestra la ESTRUCTURA del panel mientras se calcula la
/// primera vez (sólo cuando no hay snapshot en memoria ni en disco).
///
/// Nunca es pantalla blanca ni spinner a pantalla completa: el operador ve de
/// inmediato la forma del panel y las tarjetas se rellenan solas.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= 1200;
        final columns = isDesktop ? 3 : (width >= 860 ? 2 : 1);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SkeletonBox(height: 18, widthFactor: 0.35),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: List<Widget>.generate(
                  columns * 2,
                  (_) => SizedBox(
                    width: (width - 16 * (columns - 1) - 8) / columns,
                    child: const _SkeletonBox(height: 104),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SkeletonBox(height: 150),
              const SizedBox(height: 16),
              const _SkeletonBox(height: 150),
            ],
          ),
        );
      },
    );
  }
}

/// Bloque gris del skeleton. Estático a propósito: nada de animaciones ni
/// timers que puedan quedar corriendo.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.widthFactor});

  final double height;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF1F7),
        borderRadius: BorderRadius.circular(12),
      ),
    );
    final factor = widthFactor;
    if (factor == null) {
      return box;
    }
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: factor,
      child: box,
    );
  }
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

  final DashboardStats stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        label: 'Cobrado',
        value: _formatCurrency(stats.collectedAmount),
        icon: Icons.account_balance_wallet_outlined,
        accentColor: const Color(0xFF2E7D5B),
        valueFontSize: _summaryMoneyFontSize,
      ),
      _StatCard(
        label: 'Pendiente',
        value: _formatCurrency(stats.portfolioPendingAmount),
        icon: Icons.receipt_long_outlined,
        accentColor: const Color(0xFFB66A12),
        valueFontSize: _summaryMoneyFontSize,
      ),
      _StatCard(
        label: 'Vendido',
        value: _formatCurrency(stats.soldAmount),
        icon: Icons.trending_up,
        accentColor: const Color(0xFF204A71),
        valueFontSize: _summaryMoneyFontSize,
      ),
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

  final DashboardStats stats;
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
                  valueFontSize: _heroMoneyFontSize,
                ),
                _HeroMetric(
                  label: 'Cobrado registrado',
                  value: _formatCurrency(stats.collectedAmount),
                  valueFontSize: _heroMoneyFontSize,
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

  final DashboardStats stats;
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

  final DashboardStats stats;
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

  final DashboardStats stats;
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                segment.value.toString(),
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF1D3550),
                  fontWeight: FontWeight.w700,
                ),
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
    this.valueFontSize,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final double? valueFontSize;

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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
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

  final DashboardStats stats;

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
              widthFactor: 1,
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
  const _HeroMetric({
    required this.label,
    required this.value,
    this.valueFontSize,
  });

  final String label;
  final String value;
  final double? valueFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: valueFontSize ?? 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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

/// Tamaño ligeramente reducido para los montos de las tarjetas del resumen
/// (`headlineSmall` = 24). Mantiene jerarquía y legibilidad.
const double _summaryMoneyFontSize = 21;

/// Tamaño ligeramente reducido para los montos del panel ejecutivo (18 -> 16).
const double _heroMoneyFontSize = 16;

/// Monto monetario del resumen.
///
/// Delega en el helper central para no repetir `toStringAsFixed(2)` y
/// garantizar separador de miles + dos decimales: `RD$ 1,000.00`.
String _formatCurrency(double value) => MoneyMetricText.format(value);
