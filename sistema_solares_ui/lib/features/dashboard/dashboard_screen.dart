import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/dashboard/dashboard_service.dart';

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
          return _ErrorState(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = null),
          );
        }

        final data = snapshot.data!;
        final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');

        return ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vista ejecutiva',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Este panel muestra supervision y metricas en tiempo real. Las operaciones financieras estan deshabilitadas en la PWA.',
                      style: TextStyle(color: Color(0xFF5F6570), height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _MetricCard(
                          title: 'Clientes',
                          value: '${data.summary['clients'] ?? 0}',
                          color: const Color(0xFF1F2A37),
                        ),
                        _MetricCard(
                          title: 'Ventas activas',
                          value: '${data.summary['activeSales'] ?? 0}',
                          color: const Color(0xFF266A54),
                        ),
                        _MetricCard(
                          title: 'Cartera total',
                          value: currency.format(data.summary['totalPortfolio'] ?? 0),
                          color: const Color(0xFFC96F3B),
                        ),
                        _MetricCard(
                          title: 'Cobrado',
                          value: currency.format(data.summary['totalCollected'] ?? 0),
                          color: const Color(0xFF5C6B8A),
                        ),
                        _MetricCard(
                          title: 'Saldo pendiente',
                          value: currency.format(data.summary['outstanding'] ?? 0),
                          color: const Color(0xFFA53F2B),
                        ),
                        _MetricCard(
                          title: 'Cuotas vencidas',
                          value: '${data.summary['overdueInstallments'] ?? 0}',
                          color: const Color(0xFF7A4F01),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1100;
                if (stacked) {
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
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSalesTable extends StatelessWidget {
  const _RecentSalesTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ventas recientes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Cliente')),
                  DataColumn(label: Text('Producto')),
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
          ],
        ),
      ),
    );
  }
}

class _RecentPaymentsTable extends StatelessWidget {
  const _RecentPaymentsTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pagos reportados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
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
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Color(0xFFA53F2B)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}