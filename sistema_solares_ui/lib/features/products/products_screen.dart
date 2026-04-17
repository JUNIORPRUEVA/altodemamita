import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/products/products_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  Future<ProductsPage>? _future;
  int _lastTick = -1;
  bool _includeInactive = true;
  bool _includeDeleted = false;

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
      _future = ProductsService(context.read<ApiClient>()).fetch(
        search: _searchController.text,
        includeInactive: _includeInactive,
        includeDeleted: _includeDeleted,
      );
    }

    return FutureBuilder<ProductsPage>(
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
        return DesktopPageScaffold(
          title: 'Solares',
          subtitle: 'Inventario disponible para consulta y verificacion.',
          toolbar: DesktopFieldToolbar(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesktopToolbar(
                  searchField: DesktopSearchField(
                    controller: _searchController,
                    hintText: 'Buscar por codigo, nombre o descripcion',
                    onSubmitted: (_) => _reload(),
                  ),
                  actions: [
                    FilterChip(
                      selected: _includeInactive,
                      label: const Text('Incluir inactivos'),
                      onSelected: (value) {
                        _includeInactive = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      selected: _includeDeleted,
                      label: const Text('Incluir eliminados'),
                      onSelected: (value) {
                        _includeDeleted = value;
                        _reload();
                      },
                    ),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Buscar'),
                    ),
                  ],
                  compactActions: [
                    FilterChip(
                      selected: _includeInactive,
                      label: const Text('Inactivos'),
                      onSelected: (value) {
                        _includeInactive = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      selected: _includeDeleted,
                      label: const Text('Eliminados'),
                      onSelected: (value) {
                        _includeDeleted = value;
                        _reload();
                      },
                    ),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Buscar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Revisa disponibilidad, estado y valores del inventario.',
                  style: TextStyle(color: Color(0xFF66718A), height: 1.45),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                child: Text(
                  'Total visibles: ${data.total}',
                  style: const TextStyle(
                    color: Color(0xFF536079),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: data.items.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.domain_disabled_outlined,
                        title: 'No hay solares para estos filtros',
                        message: 'Ajusta la busqueda o habilita mas estados para revisar el inventario sincronizado.',
                      )
                    : DesktopModuleList(
                        children: data.items.map((item) {
                          final code = item['code']?.toString() ?? '-';
                          final name = item['name']?.toString() ?? 'Sin nombre';
                          final stock = _readNum(item['stock']).toStringAsFixed(0);
                          return DesktopListRow(
                            height: 82,
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF0F7),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.map_outlined, color: Color(0xFF2C4766)),
                            ),
                            title: Text(
                              '$code  •  $name',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Contado ${currency.format(_readNum(item['price']))}  •  Financiado ${currency.format(_readNum(item['financingPrice']))}  •  Stock $stock',
                              style: const TextStyle(color: Color(0xFF6E7791)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _StatusBadge(
                              isActive: item['isActive'] == true,
                              isDeleted: item['deletedAt'] != null,
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

  double _readNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive, required this.isDeleted});

  final bool isActive;
  final bool isDeleted;

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final Color textColor;
    late final String label;

    if (isDeleted) {
      background = const Color(0xFFFBE6E0);
      textColor = const Color(0xFFB05233);
      label = 'Eliminado';
    } else if (isActive) {
      background = const Color(0xFFE7F5EF);
      textColor = const Color(0xFF2F6F5C);
      label = 'Activo';
    } else {
      background = const Color(0xFFFCEEDF);
      textColor = const Color(0xFF9A6408);
      label = 'Inactivo';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}