import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/reports/reports_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 30;
  Future<ReportsBundle>? _future;
  int _lastTick = -1;

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = ReportsService(context.read<ApiClient>()).fetchBundle(days: _days);
    }

    return FutureBuilder<ReportsBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }

        final data = snapshot.data!;
        return ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reportes operativos',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Solo consulta. Las acciones de crear, editar o eliminar movimientos financieros no existen en este panel.',
                      style: TextStyle(color: Color(0xFF5F6570)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      children: [7, 30, 90]
                          .map(
                            (days) => ChoiceChip(
                              label: Text('Ultimos $days dias'),
                              selected: _days == days,
                              onSelected: (_) {
                                setState(() {
                                  _days = days;
                                  _future = null;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ReportTable(
              title: 'Ventas',
              columns: const ['Cliente', 'Producto', 'Estado', 'Total'],
              rows: data.sales.map((item) {
                return [
                  item['client']?['firstName']?.toString() ?? '-',
                  item['product']?['name']?.toString() ?? '-',
                  item['status']?.toString() ?? '-',
                  NumberFormat.currency(locale: 'es_DO', symbol: r'$')
                      .format(item['totalAmount'] ?? 0),
                ];
              }).toList(),
            ),
            const SizedBox(height: 16),
            _ReportTable(
              title: 'Pagos',
              columns: const ['Cliente', 'Metodo', 'Fecha', 'Monto'],
              rows: data.payments.map((item) {
                return [
                  item['sale']?['client']?['firstName']?.toString() ?? '-',
                  item['method']?.toString() ?? '-',
                  item['paymentDate']?.toString().split('T').first ?? '-',
                  NumberFormat.currency(locale: 'es_DO', symbol: r'$')
                      .format(item['amount'] ?? 0),
                ];
              }).toList(),
            ),
            const SizedBox(height: 16),
            _ReportTable(
              title: 'Morosidad',
              columns: const ['Cliente', 'Producto', 'Vencimiento', 'Saldo'],
              rows: data.delinquency.map((item) {
                return [
                  item['sale']?['client']?['firstName']?.toString() ?? '-',
                  item['sale']?['product']?['name']?.toString() ?? '-',
                  item['dueDate']?.toString().split('T').first ?? '-',
                  NumberFormat.currency(locale: 'es_DO', symbol: r'$')
                      .format(item['amountDue'] ?? 0),
                ];
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.title,
    required this.columns,
    required this.rows,
  });

  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: columns.map((label) => DataColumn(label: Text(label))).toList(),
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: row.map((cell) => DataCell(Text(cell))).toList(),
                      ),
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