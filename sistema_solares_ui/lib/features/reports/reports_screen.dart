import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/reports/reports_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 30;
  Future<ReportsBundle>? _future;
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
      _future = ReportsService(context.read<ApiClient>()).fetchBundle(days: _days);
    }

    return FutureBuilder<ReportsBundle>(
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
        final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
        final compact = MediaQuery.sizeOf(context).width < 760;
        return DesktopPageScaffold(
          title: 'Reportes',
          subtitle: 'Resumen operativo por periodo.',
          toolbar: DesktopFieldToolbar(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                const Text(
                  'Rango:',
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
          child: ListView(
            children: [
              _ReportTable(
                title: 'Ventas',
                compact: compact,
                columns: const ['Cliente', 'Solar', 'Estado', 'Total'],
                rows: data.sales.map((item) {
                  return [
                    item['client']?['firstName']?.toString() ?? '-',
                    item['product']?['name']?.toString() ?? '-',
                    item['status']?.toString() ?? '-',
                    currency.format(item['totalAmount'] ?? 0),
                  ];
                }).toList(),
                emptyTitle: 'Sin ventas en el periodo',
                emptyMessage: 'Amplia el rango o espera nueva sincronizacion para ver ventas recientes.',
              ),
              const SizedBox(height: 16),
              _ReportTable(
                title: 'Pagos',
                compact: compact,
                columns: const ['Cliente', 'Metodo', 'Fecha', 'Monto'],
                rows: data.payments.map((item) {
                  return [
                    item['sale']?['client']?['firstName']?.toString() ?? '-',
                    item['method']?.toString() ?? '-',
                    item['paymentDate']?.toString().split('T').first ?? '-',
                    currency.format(item['amount'] ?? 0),
                  ];
                }).toList(),
                emptyTitle: 'Sin pagos en el periodo',
                emptyMessage: 'No hay pagos sincronizados dentro del rango seleccionado.',
              ),
              const SizedBox(height: 16),
              _ReportTable(
                title: 'Morosidad',
                compact: compact,
                columns: const ['Cliente', 'Solar', 'Vencimiento', 'Saldo'],
                rows: data.delinquency.map((item) {
                  return [
                    item['sale']?['client']?['firstName']?.toString() ?? '-',
                    item['sale']?['product']?['name']?.toString() ?? '-',
                    item['dueDate']?.toString().split('T').first ?? '-',
                    currency.format(item['amountDue'] ?? 0),
                  ];
                }).toList(),
                emptyTitle: 'Sin cuotas vencidas',
                emptyMessage: 'La cartera no reporta morosidad para este corte.',
              ),
            ],
          ),
        );
      },
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
                final details = row.length > 2 ? row.sublist(1, row.length - 1).join('  •  ') : '';
                return DesktopListRow(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.description_outlined, color: Color(0xFF223048)),
                  ),
                  title: Text(row.first, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    details,
                    style: const TextStyle(color: Color(0xFF6E7791)),
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
    );
  }
}