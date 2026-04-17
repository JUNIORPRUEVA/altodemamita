import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
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
            onRetry: () => setState(() => _future = null),
          );
        }

        final data = snapshot.data!;
        final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
        final compact = MediaQuery.sizeOf(context).width < 760;

        return DesktopPageScaffold(
          title: 'Vista general',
          subtitle: 'Resumen comercial y financiero del sistema.',
          child: ListView(
            children: [
              DesktopInfoStrip(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Panel ejecutivo',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Indicadores comerciales, cartera y actividad reciente en una vista consolidada.',
                      style: TextStyle(color: Color(0xFF657089), height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    DesktopMetricStrip(
                      children: [
                        DesktopMetricCard(
                          title: 'Clientes',
                          value: '${data.summary['clients'] ?? 0}',
                          color: const Color(0xFF223048),
                        ),
                        DesktopMetricCard(
                          title: 'Ventas activas',
                          value: '${data.summary['activeSales'] ?? 0}',
                          color: const Color(0xFF2F6F5C),
                        ),
                        DesktopMetricCard(
                          title: 'Cartera total',
                          value: currency.format(data.summary['totalPortfolio'] ?? 0),
                          color: const Color(0xFFC78442),
                        ),
                        DesktopMetricCard(
                          title: 'Cobrado',
                          value: currency.format(data.summary['totalCollected'] ?? 0),
                          color: const Color(0xFF59728D),
                        ),
                        DesktopMetricCard(
                          title: 'Saldo pendiente',
                          value: currency.format(data.summary['outstanding'] ?? 0),
                          color: const Color(0xFFB05233),
                        ),
                        DesktopMetricCard(
                          title: 'Cuotas vencidas',
                          value: '${data.summary['overdueInstallments'] ?? 0}',
                          color: const Color(0xFF7F5807),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (compact) {
                    return Column(
                      children: [
                        _RecentSalesTable(rows: data.recentSales, compact: true),
                        const SizedBox(height: 16),
                        _RecentPaymentsTable(rows: data.recentPayments, compact: true),
                      ],
                    );
                  }
                  if (constraints.maxWidth < 1100) {
                    return Column(
                      children: [
                        _RecentSalesTable(rows: data.recentSales),
                        const SizedBox(height: 16),
                        _RecentPaymentsTable(rows: data.recentPayments),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _RecentSalesTable(rows: data.recentSales)),
                      const SizedBox(width: 16),
                      Expanded(child: _RecentPaymentsTable(rows: data.recentPayments)),
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
}

class _RecentSalesTable extends StatelessWidget {
  const _RecentSalesTable({required this.rows, this.compact = false});

  final List<Map<String, dynamic>> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
    if (compact) {
      return DesktopDataListSection(
        title: 'Ventas recientes',
        children: rows.isEmpty
            ? const [
                DesktopEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sin ventas recientes',
                  message: 'Todavia no hay ventas sincronizadas para mostrar en esta vista.',
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
                    child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF223048)),
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
              message: 'Todavia no hay ventas sincronizadas para mostrar en esta vista.',
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
                      (row) => DataRow(cells: [
                        DataCell(Text(row['client']?['firstName']?.toString() ?? '-')),
                        DataCell(Text(row['product']?['name']?.toString() ?? '-')),
                        DataCell(Text(row['status']?.toString() ?? '-')),
                        DataCell(Text(currency.format(row['totalAmount'] ?? 0))),
                      ]),
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
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
    if (compact) {
      return DesktopDataListSection(
        title: 'Pagos reportados',
        children: rows.isEmpty
            ? const [
                DesktopEmptyState(
                  icon: Icons.payments_outlined,
                  title: 'Sin pagos recientes',
                  message: 'No se han recibido pagos recientes dentro del rango sincronizado.',
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
                    child: const Icon(Icons.payments_outlined, color: Color(0xFF2F6F5C)),
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
              message: 'No se han recibido pagos recientes dentro del rango sincronizado.',
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
                      (row) => DataRow(cells: [
                        DataCell(
                          Text(row['sale']?['client']?['firstName']?.toString() ?? '-'),
                        ),
                        DataCell(Text(row['method']?.toString() ?? '-')),
                        DataCell(Text(row['paymentDate']?.toString().split('T').first ?? '-')),
                        DataCell(Text(currency.format(row['amount'] ?? 0))),
                      ]),
                    )
                    .toList(),
              ),
            ),
    );
  }
}