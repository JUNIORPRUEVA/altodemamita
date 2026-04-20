import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/features/sales/sale_detail_dialog.dart';
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
    final currency = AppNumberFormats.currency;

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
          subtitle: compact
              ? 'Vista limpia de ventas activas y monto visible.'
              : 'Consulta de ventas y detalle de operaciones registradas.',
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
                DesktopToolbarIconAction(
                  icon: Icons.cleaning_services_outlined,
                  tooltip: 'Limpiar',
                  onPressed: () {
                    _searchController.clear();
                    _reload();
                  },
                ),
                DesktopToolbarIconAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Buscar',
                  tone: DesktopToolbarActionTone.filled,
                  onPressed: _reload,
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
                      label: compact
                          ? '${data.total} visibles'
                          : 'Total visibles: ${data.total}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: compact
                          ? 'Activas ${statusCounts.active}'
                          : 'Activas ${statusCounts.active}',
                      background: const Color(0xFFEAF0F7),
                    ),
                    if (!compact)
                      DesktopTag(
                        label: 'Completadas ${statusCounts.completed}',
                        background: const Color(0xFFE7F5EF),
                        foreground: const Color(0xFF2F6F5C),
                      ),
                    if (!compact)
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
                    if (!compact)
                      DesktopTag(
                        label: 'Pag. ${data.page}/${data.totalPages}',
                        background: const Color(0xFFF1F4FA),
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
                            if (compact &&
                                contract != null &&
                                contract.trim().isNotEmpty)
                              contract,
                            if (!compact &&
                                contract != null &&
                                contract.trim().isNotEmpty)
                              contract,
                            product,
                            _formatDate(item['saleDate']),
                          ];

                          return DesktopListRow(
                            height: compact ? 84 : 82,
                            onTap: () =>
                                _openDetail(item['id']?.toString() ?? ''),
                            leading: Container(
                              width: compact ? 36 : 42,
                              height: compact ? 36 : 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F4FA),
                                borderRadius: BorderRadius.circular(
                                  compact ? 12 : 14,
                                ),
                              ),
                              child: Icon(
                                Icons.point_of_sale_outlined,
                                color: Color(0xFF223048),
                                size: compact ? 18 : 20,
                              ),
                            ),
                            title: Text(
                              client,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 13.5 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitleParts.join(compact ? '\n' : '  •  '),
                              style: TextStyle(
                                color: const Color(0xFF6E7791),
                                fontSize: compact ? 11.5 : null,
                                height: compact ? 1.25 : null,
                              ),
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!compact) _StatusTag(status: status),
                                DesktopTag(
                                  label: currency.format(
                                    _asNum(item['totalAmount']),
                                  ),
                                  background: const Color(0xFFF6EFE3),
                                  foreground: const Color(0xFF8C5A2C),
                                ),
                                if (compact) _StatusTag(status: status),
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
        builder: (context) => SaleDetailDialog(detail: detail),
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
