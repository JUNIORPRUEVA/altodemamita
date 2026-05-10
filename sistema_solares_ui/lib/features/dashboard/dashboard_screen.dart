import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/dashboard/dashboard_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<DashboardSnapshot>? _future;
  int _lastTick = -1;

  void _reload() {
    setState(() => _future = null);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.select<RealtimeController, int>((realtime) => realtime.refreshTick);
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = DashboardService(context.read<ApiClient>()).fetchSnapshot();
    }

    return FutureBuilder<DashboardSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final data = snapshot.data!;
        final currency = AppNumberFormats.currency;
        final compact = MediaQuery.sizeOf(context).width < 760;
        final totalPortfolio = _asNum(data.summary['totalPortfolio']);
        final totalCollected = _asNum(data.summary['totalCollected']);
        final outstanding = _asNum(data.summary['outstanding']);
        final products = _asInt(data.summary['products']);
        final clients = _asInt(data.summary['clients']);
        final activeSales = _asInt(data.summary['activeSales']);
        final overdueInstallments = _asInt(data.summary['overdueInstallments']);

        return DesktopPageScaffold(
          title: 'Panel principal',
          subtitle: compact
              ? null
              : 'Vista operativa del inventario, las ventas y la cobranza sincronizada.',
          child: ListView(
            children: [
              DesktopInfoStrip(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    DesktopStackedStat(
                      label: 'Clientes registrados',
                      value: '$clients',
                    ),
                    DesktopStackedStat(
                      label: 'Solares sincronizados',
                      value: '$products',
                    ),
                    DesktopStackedStat(
                      label: 'Ventas activas',
                      value: '$activeSales',
                    ),
                    DesktopStackedStat(
                      label: 'Cuotas vencidas',
                      value: '$overdueInstallments',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1100;
                  final medium = constraints.maxWidth >= 860;
                  final metrics = DesktopMetricStrip(
                    children: [
                      DesktopMetricCard(
                        title: 'Clientes',
                        value: '$clients',
                        color: const Color(0xFF223048),
                      ),
                      DesktopMetricCard(
                        title: 'Ventas activas',
                        value: '$activeSales',
                        color: const Color(0xFF2F6F5C),
                      ),
                      DesktopMetricCard(
                        title: 'Cartera total',
                        value: currency.format(totalPortfolio),
                        color: const Color(0xFFC78442),
                      ),
                      DesktopMetricCard(
                        title: 'Cobrado',
                        value: currency.format(totalCollected),
                        color: const Color(0xFF59728D),
                      ),
                      DesktopMetricCard(
                        title: 'Saldo pendiente',
                        value: currency.format(outstanding),
                        color: const Color(0xFFB05233),
                      ),
                      DesktopMetricCard(
                        title: 'Cuotas vencidas',
                        value: '$overdueInstallments',
                        color: const Color(0xFF7F5807),
                      ),
                    ],
                  );

                  final collectionsCard = _DashboardFocusCard(
                    title: 'Seguimiento de cobros',
                    icon: Icons.payments_outlined,
                    accentColor: const Color(0xFF0D2844),
                    items: [
                      _FocusItem(
                        label: 'Pendiente',
                        value: currency.format(outstanding),
                      ),
                      _FocusItem(
                        label: 'Cobrado',
                        value: currency.format(totalCollected),
                      ),
                      _FocusItem(
                        label: 'Vencidas',
                        value: '$overdueInstallments',
                      ),
                    ],
                  );

                  final inventoryCard = _DashboardFocusCard(
                    title: 'Inventario y actividad',
                    icon: Icons.inventory_2_outlined,
                    accentColor: const Color(0xFF173450),
                    items: [
                      _FocusItem(label: 'Solares', value: '$products'),
                      _FocusItem(label: 'Clientes', value: '$clients'),
                      _FocusItem(
                        label: 'Ventas activas',
                        value: '$activeSales',
                      ),
                    ],
                  );

                  final overview = _DashboardOverviewCard(
                    totalPortfolio: currency.format(totalPortfolio),
                    totalCollected: currency.format(totalCollected),
                    outstanding: currency.format(outstanding),
                  );

                  final tables = Column(
                    children: [
                      if (compact) ...[
                        _RecentSalesTable(
                          rows: data.recentSales,
                          compact: true,
                        ),
                        const SizedBox(height: 16),
                        _RecentPaymentsTable(
                          rows: data.recentPayments,
                          compact: true,
                        ),
                      ] else if (constraints.maxWidth < 1100) ...[
                        _RecentSalesTable(rows: data.recentSales),
                        const SizedBox(height: 16),
                        _RecentPaymentsTable(rows: data.recentPayments),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _RecentSalesTable(rows: data.recentSales),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _RecentPaymentsTable(
                                rows: data.recentPayments,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            children: [
                              metrics,
                              const SizedBox(height: 16),
                              tables,
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              overview,
                              const SizedBox(height: 16),
                              collectionsCard,
                              const SizedBox(height: 16),
                              inventoryCard,
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
                        metrics,
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: collectionsCard),
                            const SizedBox(width: 16),
                            Expanded(child: inventoryCard),
                          ],
                        ),
                        const SizedBox(height: 16),
                        tables,
                      ],
                    );
                  }

                  return Column(
                    children: [
                      overview,
                      const SizedBox(height: 16),
                      metrics,
                      const SizedBox(height: 16),
                      collectionsCard,
                      const SizedBox(height: 16),
                      inventoryCard,
                      const SizedBox(height: 16),
                      tables,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
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

class _DashboardOverviewCard extends StatelessWidget {
  const _DashboardOverviewCard({
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: Colors.white,
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
                        'Vista rapida del inventario, la cartera y la cobranza sincronizada.',
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
        color: Colors.white.withValues(alpha: 0.1),
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

class _DashboardFocusCard extends StatelessWidget {
  const _DashboardFocusCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final List<_FocusItem> items;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map(
                  (item) => Container(
                    constraints: const BoxConstraints(minWidth: 130),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F5EE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: Color(0xFF6B7682),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.value,
                          style: const TextStyle(
                            color: Color(0xFF1D3550),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FocusItem {
  const _FocusItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _RecentSalesTable extends StatelessWidget {
  const _RecentSalesTable({required this.rows, this.compact = false});

  final List<Map<String, dynamic>> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currency = AppNumberFormats.currency;
    if (compact) {
      return DesktopDataListSection(
        title: 'Ventas recientes',
        children: rows.isEmpty
            ? const [
                DesktopEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sin ventas recientes',
                  message:
                      'Todavia no hay ventas sincronizadas para mostrar en esta vista.',
                ),
              ]
            : rows.map((row) {
                return DesktopListRow(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: Color(0xFF223048),
                    ),
                  ),
                  title: Text(
                    row['client']?['firstName']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${row['product']?['name']?.toString() ?? '-'}  •  ${row['status']?.toString() ?? '-'}',
                    style: const TextStyle(color: Color(0xFF6E7791)),
                  ),
                  trailing: DesktopTag(
                    label: currency.format(row['totalAmount'] ?? 0),
                    background: const Color(0xFFF6EFE3),
                    foreground: const Color(0xFF8C5A2C),
                  ),
                );
              }).toList(),
      );
    }

    return DesktopTableCard(
      title: 'Ventas recientes',
      child: rows.isEmpty
          ? const DesktopEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sin ventas recientes',
              message:
                  'Todavia no hay ventas sincronizadas para mostrar en esta vista.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Cliente')),
                  DataColumn(label: Text('Solar')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Monto')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              row['client']?['firstName']?.toString() ?? '-',
                            ),
                          ),
                          DataCell(
                            Text(row['product']?['name']?.toString() ?? '-'),
                          ),
                          DataCell(Text(row['status']?.toString() ?? '-')),
                          DataCell(
                            Text(currency.format(row['totalAmount'] ?? 0)),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}

class _RecentPaymentsTable extends StatelessWidget {
  const _RecentPaymentsTable({required this.rows, this.compact = false});

  final List<Map<String, dynamic>> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currency = AppNumberFormats.currency;
    if (compact) {
      return DesktopDataListSection(
        title: 'Pagos reportados',
        children: rows.isEmpty
            ? const [
                DesktopEmptyState(
                  icon: Icons.payments_outlined,
                  title: 'Sin pagos recientes',
                  message:
                      'No se han recibido pagos recientes dentro del rango sincronizado.',
                ),
              ]
            : rows.map((row) {
                return DesktopListRow(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F6F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: Color(0xFF2F6F5C),
                    ),
                  ),
                  title: Text(
                    row['sale']?['client']?['firstName']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${row['method']?.toString() ?? '-'}  •  ${row['paymentDate']?.toString().split('T').first ?? '-'}',
                    style: const TextStyle(color: Color(0xFF6E7791)),
                  ),
                  trailing: DesktopTag(
                    label: currency.format(row['amount'] ?? 0),
                    background: const Color(0xFFE8F6F0),
                    foreground: const Color(0xFF2F6F5C),
                  ),
                );
              }).toList(),
      );
    }

    return DesktopTableCard(
      title: 'Pagos reportados',
      child: rows.isEmpty
          ? const DesktopEmptyState(
              icon: Icons.payments_outlined,
              title: 'Sin pagos recientes',
              message:
                  'No se han recibido pagos recientes dentro del rango sincronizado.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Cliente')),
                  DataColumn(label: Text('Metodo')),
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Monto')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              row['sale']?['client']?['firstName']
                                      ?.toString() ??
                                  '-',
                            ),
                          ),
                          DataCell(Text(row['method']?.toString() ?? '-')),
                          DataCell(
                            Text(
                              row['paymentDate']?.toString().split('T').first ??
                                  '-',
                            ),
                          ),
                          DataCell(Text(currency.format(row['amount'] ?? 0))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}


