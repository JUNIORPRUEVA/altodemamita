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
  final Set<String> _deletingSaleIds = <String>{};

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
    final refreshTick = context.select<RealtimeController, int>((realtime) => realtime.refreshTick);
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
              ? null
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
                    if (compact)
                      const DesktopTag(
                        label: 'Toca una venta para ver cuotas y pagos',
                        background: Color(0xFFEAF0F7),
                        foreground: Color(0xFF21486A),
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
                          final hasReadableContract =
                              contract != null &&
                              contract.trim().isNotEmpty &&
                              !_looksLikeId(contract);
                          final subtitleParts = <String>[
                            if (hasReadableContract) contract.trim(),
                            product,
                            _formatDate(item['saleDate']),
                          ];

                          return DesktopListRow(
                            height: compact ? 76 : 82,
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
                                fontSize: compact ? 12.6 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitleParts.join(compact ? '  •  ' : '  •  '),
                              style: TextStyle(
                                color: const Color(0xFF6E7791),
                                fontSize: compact ? 10.8 : null,
                                height: compact ? 1.1 : null,
                              ),
                              maxLines: 1,
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
                                IconButton(
                                  tooltip: 'Eliminar de nube (forzado)',
                                  onPressed: _deletingSaleIds.contains(
                                    item['id']?.toString() ?? '',
                                  )
                                      ? null
                                      : () => _forceDeleteSale(item),
                                  icon: _deletingSaleIds.contains(
                                    item['id']?.toString() ?? '',
                                  )
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.delete_forever_rounded,
                                          color: Color(0xFFB05233),
                                        ),
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

  Future<String?> _askAdminPassword() async {
    final controller = TextEditingController();
    var obscure = true;
    final password = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Contrasena de administrador'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Contrasena',
              suffixIcon: IconButton(
                onPressed: () => setDialogState(() => obscure = !obscure),
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return password?.trim();
  }

  Future<void> _forceDeleteSale(Map<String, dynamic> item) async {
    final saleId = item['id']?.toString().trim() ?? '';
    if (saleId.isEmpty || _deletingSaleIds.contains(saleId)) {
      return;
    }

    final contract = item['contractNumber']?.toString().trim();
    final client = _fullName(item['client']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar venta de la nube'),
        content: Text(
          'Se eliminara COMPLETAMENTE esta venta en la nube.\n\nCliente: $client\nContrato: ${contract?.isNotEmpty == true ? contract : 'Sin contrato'}\n\nEsta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final password = await _askAdminPassword();
    if (password == null || password.isEmpty || !mounted) {
      return;
    }

    setState(() => _deletingSaleIds.add(saleId));
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      await SalesService(
        context.read<ApiClient>(),
      ).forceDeleteFromCloud(saleId: saleId, adminPassword: password);
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Venta eliminada completamente de la nube.'),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la venta: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingSaleIds.remove(saleId));
      }
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

  // Treat UUIDs and similar internal identifiers as not human-readable so they
  // don't pollute the sales list subtitle.
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  bool _looksLikeId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (_uuidPattern.hasMatch(trimmed)) return true;
    // Long opaque tokens (24+ chars without spaces and mostly hex/digits) also
    // look like internal IDs and should be hidden from the listing subtitle.
    if (trimmed.length >= 24 &&
        !trimmed.contains(' ') &&
        RegExp(r'^[0-9a-f-]+$', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    return false;
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


