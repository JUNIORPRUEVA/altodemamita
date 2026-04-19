import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/sales/sales_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _searchController = TextEditingController();
  Future<SalesPageData>? _future;
  int _lastTick = -1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = null);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');

    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = SalesService(
        context.read<ApiClient>(),
      ).fetch(search: _searchController.text);
    }

    return FutureBuilder<SalesPageData>(
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
        final compact = MediaQuery.sizeOf(context).width < 760;
        final statusCounts = _statusCounts(data.items);
        final visibleRevenue = data.items.fold<double>(
          0,
          (total, item) => total + _asNum(item['totalAmount']),
        );
        return DesktopPageScaffold(
          title: 'Ventas',
          subtitle: 'Consulta de ventas y detalle de operaciones registradas.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar por cliente, contrato, solar o estado',
                onSubmitted: (_) => _reload(),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _reload();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpiar'),
                ),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
              compactActions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _reload();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpiar'),
                ),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopInfoStrip(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DesktopTag(
                      label: 'Total visibles: ${data.total}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: 'Pag. ${data.page}/${data.totalPages}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: 'Activas ${statusCounts.active}',
                      background: const Color(0xFFEAF0F7),
                    ),
                    DesktopTag(
                      label: 'Completadas ${statusCounts.completed}',
                      background: const Color(0xFFE7F5EF),
                      foreground: const Color(0xFF2F6F5C),
                    ),
                    DesktopTag(
                      label: 'Canceladas ${statusCounts.cancelled}',
                      background: const Color(0xFFFBE6E0),
                      foreground: const Color(0xFFB05233),
                    ),
                    DesktopTag(
                      label: currency.format(visibleRevenue),
                      background: const Color(0xFFF6EFE3),
                      foreground: const Color(0xFF8C5A2C),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: data.items.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.point_of_sale_outlined,
                        title: 'No hay ventas para este filtro',
                        message:
                            'Prueba otra busqueda o espera a la siguiente sincronizacion del backend.',
                      )
                    : DesktopModuleList(
                        children: data.items.map((item) {
                          final status = item['status']?.toString() ?? '-';
                          final client = _fullName(item['client']);
                          final product =
                              _readNested(item, ['product', 'name']) ??
                              'Sin solar';
                          final contract = item['contractNumber']?.toString();
                          final subtitleParts = <String>[
                            if (contract != null && contract.trim().isNotEmpty)
                              contract,
                            product,
                            _formatDate(item['saleDate']),
                          ];

                          return DesktopListRow(
                            height: compact ? 108 : 88,
                            onTap: () =>
                                _openDetail(item['id']?.toString() ?? ''),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F4FA),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.point_of_sale_outlined,
                                color: Color(0xFF223048),
                              ),
                            ),
                            title: Text(
                              client,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitleParts.join(compact ? '\n' : '  •  '),
                              style: const TextStyle(color: Color(0xFF6E7791)),
                              maxLines: compact ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _StatusTag(status: status),
                                DesktopTag(
                                  label: currency.format(
                                    _asNum(item['totalAmount']),
                                  ),
                                  background: const Color(0xFFF6EFE3),
                                  foreground: const Color(0xFF8C5A2C),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDetail(String id) async {
    if (id.trim().isEmpty) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final detail = await SalesService(
        context.read<ApiClient>(),
      ).fetchDetail(id);
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => _SaleDetailDialog(detail: detail),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _fullName(Object? value) {
    final map = _asMap(value);
    final firstName = map['firstName']?.toString() ?? '';
    final lastName = map['lastName']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? 'Sin cliente' : fullName;
  }

  String? _readNested(Object? value, List<String> keys) {
    Object? current = value;
    for (final key in keys) {
      if (current is! Map) {
        return null;
      }
      current = current[key];
    }
    return current?.toString();
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  double _asNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return 'Sin fecha';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return DateFormat('dd/MM/yyyy').format(parsed.toLocal());
  }

  _SalesStatusCounts _statusCounts(List<Map<String, dynamic>> items) {
    var active = 0;
    var completed = 0;
    var cancelled = 0;

    for (final item in items) {
      switch ((item['status']?.toString() ?? '').trim().toLowerCase()) {
        case 'completed':
          completed++;
          break;
        case 'cancelled':
          cancelled++;
          break;
        default:
          active++;
      }
    }

    return _SalesStatusCounts(
      active: active,
      completed: completed,
      cancelled: cancelled,
    );
  }
}

class _SalesStatusCounts {
  const _SalesStatusCounts({
    required this.active,
    required this.completed,
    required this.cancelled,
  });

  final int active;
  final int completed;
  final int cancelled;
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    late final Color background;
    late final Color foreground;
    late final String label;

    switch (normalized) {
      case 'completed':
        background = const Color(0xFFE7F5EF);
        foreground = const Color(0xFF2F6F5C);
        label = 'Completada';
        break;
      case 'cancelled':
        background = const Color(0xFFFBE6E0);
        foreground = const Color(0xFFB05233);
        label = 'Cancelada';
        break;
      default:
        background = const Color(0xFFEAF0F7);
        foreground = const Color(0xFF223048);
        label = 'Activa';
        break;
    }

    return DesktopTag(
      label: label,
      background: background,
      foreground: foreground,
    );
  }
}

class _SaleDetailDialog extends StatelessWidget {
  const _SaleDetailDialog({required this.detail});

  final Map<String, dynamic> detail;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final installments =
        (detail['installments'] as List<dynamic>? ?? const <dynamic>[])
            .map(_asMap)
            .toList();
    final payments = (detail['payments'] as List<dynamic>? ?? const <dynamic>[])
        .map(_asMap)
        .toList();

    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 10 : 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? 420 : 860,
          maxHeight: compact ? MediaQuery.sizeOf(context).height - 20 : 760,
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detalle de venta',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        DesktopStackedStat(
                          label: 'Cliente',
                          value: _fullName(detail['client']),
                        ),
                        DesktopStackedStat(
                          label: 'Solar',
                          value:
                              _readNested(detail, ['product', 'name']) ??
                              'Sin solar',
                        ),
                        DesktopStackedStat(
                          label: 'Contrato',
                          value: detail['contractNumber']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Estado',
                          value: detail['status']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Total',
                          value: currency.format(_asNum(detail['totalAmount'])),
                        ),
                        DesktopStackedStat(
                          label: 'Saldo',
                          value: currency.format(
                            _asNum(detail['outstandingBalance']),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    DesktopPlainSection(
                      title: 'Resumen financiero',
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          DesktopStackedStat(
                            label: 'Inicial',
                            value: currency.format(
                              _asNum(detail['downPayment']),
                            ),
                          ),
                          DesktopStackedStat(
                            label: 'Monto financiado',
                            value: currency.format(
                              _asNum(detail['financedAmount']),
                            ),
                          ),
                          DesktopStackedStat(
                            label: 'Pagado',
                            value: currency.format(
                              _asNum(detail['paidAmount']),
                            ),
                          ),
                          DesktopStackedStat(
                            label: 'Plazo',
                            value: '${detail['termMonths'] ?? 0} meses',
                          ),
                          DesktopStackedStat(
                            label: 'Interes',
                            value: '${detail['interestRate'] ?? 0} %',
                          ),
                          DesktopStackedStat(
                            label: 'Responsable',
                            value:
                                _readNested(detail, ['user', 'fullName']) ??
                                '-',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    DesktopPlainSection(
                      title: 'Cuotas',
                      child: installments.isEmpty
                          ? const DesktopEmptyState(
                              icon: Icons.event_note_outlined,
                              title: 'Sin cuotas registradas',
                              message:
                                  'Esta venta no tiene cuotas generadas en el backend.',
                            )
                          : Column(
                              children: installments.map((installment) {
                                return DesktopCompactSurface(
                                  child: ListTile(
                                    dense: true,
                                    isThreeLine: compact,
                                    title: Text(
                                      'Cuota ${installment['installmentNumber'] ?? '-'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      compact
                                          ? 'Vence ${_formatDate(installment['dueDate'])}\nPagado ${currency.format(_asNum(installment['paidAmount']))}'
                                          : 'Vence ${_formatDate(installment['dueDate'])}  •  Pagado ${currency.format(_asNum(installment['paidAmount']))}',
                                    ),
                                    trailing: Text(
                                      currency.format(
                                        _asNum(installment['amount']),
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 18),
                    DesktopPlainSection(
                      title: 'Pagos',
                      child: payments.isEmpty
                          ? const DesktopEmptyState(
                              icon: Icons.payments_outlined,
                              title: 'Sin pagos registrados',
                              message:
                                  'Esta venta aun no tiene pagos aplicados.',
                            )
                          : Column(
                              children: payments.map((payment) {
                                return DesktopCompactSurface(
                                  child: ListTile(
                                    dense: true,
                                    isThreeLine: compact,
                                    title: Text(
                                      payment['method']?.toString() ?? 'Pago',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _formatDate(payment['paymentDate']),
                                    ),
                                    trailing: Text(
                                      currency.format(
                                        _asNum(payment['amount']),
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    return (value as Map<dynamic, dynamic>).map(
      (key, val) => MapEntry(key.toString(), val),
    );
  }

  static String _fullName(Object? value) {
    final map = value is Map<String, dynamic>
        ? value
        : value is Map
        ? value.map((key, val) => MapEntry(key.toString(), val))
        : const <String, dynamic>{};
    final firstName = map['firstName']?.toString() ?? '';
    final lastName = map['lastName']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? 'Sin cliente' : fullName;
  }

  static String? _readNested(Map<String, dynamic> value, List<String> keys) {
    Object? current = value;
    for (final key in keys) {
      if (current is! Map) {
        return null;
      }
      current = current[key];
    }
    return current?.toString();
  }

  static double _asNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return 'Sin fecha';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return DateFormat('dd/MM/yyyy').format(parsed.toLocal());
  }
}
