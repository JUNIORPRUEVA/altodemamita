import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/sellers/sellers_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key});

  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen> {
  final _searchController = TextEditingController();
  Future<SellersPageData>? _future;
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
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = SellersService(
        context.read<ApiClient>(),
      ).fetch(search: _searchController.text);
    }

    return FutureBuilder<SellersPageData>(
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
        return DesktopPageScaffold(
          title: 'Vendedores',
          subtitle: compact
              ? 'Directorio compacto de vendedores.'
              : 'Consulta la tabla de vendedores y sus ventas asociadas desde la nube.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar por nombre, cedula o telefono',
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
                  children: [
                    DesktopTag(
                      label: compact
                          ? '${data.total} visibles'
                          : 'Total visibles: ${data.total}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    if (!compact)
                      DesktopTag(
                        label: 'Pag. ${data.page}/${data.totalPages}',
                        background: const Color(0xFFEAF0F7),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: data.items.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.badge_outlined,
                        title: 'No hay vendedores para este filtro',
                        message:
                            'Prueba otra busqueda o espera a la siguiente sincronizacion desde el escritorio.',
                      )
                    : DesktopModuleList(
                        children: data.items.map((item) {
                          final name = item['name']?.toString() ?? 'Sin nombre';
                          final document =
                              item['documentId']?.toString() ?? 'Sin cedula';
                          final phone =
                              item['phone']?.toString() ?? 'Sin telefono';
                          final subtitle = compact
                              ? '$document\n$phone'
                              : '$document  •  $phone';
                          return DesktopListRow(
                            height: compact ? 98 : 76,
                            onTap: () =>
                                _openDetail(item['id']?.toString() ?? ''),
                            leading: CircleAvatar(
                              radius: compact ? 18 : 22,
                              backgroundColor: const Color(0xFFEAF0F7),
                              child: Text(
                                name.isEmpty ? 'V' : name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF223048),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitle,
                              style: const TextStyle(color: Color(0xFF6E7791)),
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: compact
                                ? null
                                : const DesktopTag(
                                    label: 'Ver detalle',
                                    background: Color(0xFFF6EFE3),
                                    foreground: Color(0xFF8C5A2C),
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
      final detail = await SellersService(
        context.read<ApiClient>(),
      ).fetchDetail(id);
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => _SellerDetailDialog(detail: detail),
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
}

class _SellerDetailDialog extends StatelessWidget {
  const _SellerDetailDialog({required this.detail});

  final Map<String, dynamic> detail;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final sales = (detail['sales'] as List<dynamic>? ?? const <dynamic>[])
        .map(_asMap)
        .toList();
    final totalSold = sales.fold<double>(
      0,
      (sum, sale) => sum + _asNum(sale['totalAmount']),
    );

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
                      detail['name']?.toString() ?? 'Detalle de vendedor',
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
                          label: 'Cedula',
                          value: detail['documentId']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Telefono',
                          value: detail['phone']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Ventas',
                          value: '${sales.length}',
                        ),
                        DesktopStackedStat(
                          label: 'Monto vendido',
                          value: _currency.format(totalSold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    DesktopPlainSection(
                      title: 'Ventas asociadas',
                      child: sales.isEmpty
                          ? const DesktopEmptyState(
                              icon: Icons.point_of_sale_outlined,
                              title: 'Sin ventas asociadas',
                              message:
                                  'Este vendedor todavia no tiene ventas visibles en la nube.',
                            )
                          : Column(
                              children: sales.map((sale) {
                                final client = _fullName(
                                  _asMap(sale['client']),
                                );
                                final product =
                                    _readNested(sale, ['product', 'name']) ??
                                    'Sin solar';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: DesktopCompactSurface(
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        client,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '$product  •  ${sale['contractNumber'] ?? 'Sin contrato'}\n${_formatDate(sale['saleDate'])}',
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _currency.format(
                                              _asNum(sale['totalAmount']),
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF8C5A2C),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            sale['status']?.toString() ?? '-',
                                            style: const TextStyle(
                                              color: Color(0xFF6E7791),
                                            ),
                                          ),
                                        ],
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
}

final NumberFormat _currency = NumberFormat.currency(
  locale: 'es_DO',
  symbol: 'RD\$ ',
);

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return const <String, dynamic>{};
}

String _fullName(Map<String, dynamic> client) {
  final firstName = client['firstName']?.toString() ?? '';
  final lastName = client['lastName']?.toString() ?? '';
  final fullName = '$firstName $lastName'.trim();
  return fullName.isEmpty ? 'Sin cliente' : fullName;
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
