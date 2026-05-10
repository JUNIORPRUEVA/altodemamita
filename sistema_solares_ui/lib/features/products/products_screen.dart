import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
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
    final refreshTick = context.select<RealtimeController, int>((realtime) => realtime.refreshTick);
    final currency = AppNumberFormats.currency;

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
        final compact = MediaQuery.sizeOf(context).width < 760;
        return DesktopPageScaffold(
          title: 'Solares',
          subtitle: compact
              ? null
              : 'Inventario disponible para consulta y verificacion.',
          toolbar: DesktopFieldToolbar(
            child: compact
                ? _CompactProductsToolbar(
                    controller: _searchController,
                    includeInactive: _includeInactive,
                    includeDeleted: _includeDeleted,
                    onSubmitted: _reload,
                    onSearch: _reload,
                    onToggleInactive: (value) {
                      _includeInactive = value;
                      _reload();
                    },
                    onToggleDeleted: (value) {
                      _includeDeleted = value;
                      _reload();
                    },
                  )
                : Column(
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
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Revisa disponibilidad, estado y valores del inventario.',
                        style: TextStyle(
                          color: Color(0xFF66718A),
                          height: 1.45,
                        ),
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
                    if (_includeInactive)
                      const DesktopTag(
                        label: 'Inactivos',
                        background: Color(0xFFF6EFE3),
                        foreground: Color(0xFF8C5A2C),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: data.items.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.domain_disabled_outlined,
                        title: 'No hay solares para estos filtros',
                        message:
                            'Ajusta la busqueda o habilita mas estados para revisar el inventario sincronizado.',
                      )
                    : DesktopModuleList(
                        children: data.items.map((item) {
                          final code = item['code']?.toString() ?? '-';
                          final name = item['name']?.toString() ?? 'Sin nombre';
                          final stock = _readNum(
                            item['stock'],
                          ).toStringAsFixed(0);
                          final subtitleText = compact
                              ? '${currency.format(_readNum(item['price']))}  •  Stock $stock'
                              : 'Contado ${currency.format(_readNum(item['price']))}  •  Financiado ${currency.format(_readNum(item['financingPrice']))}  •  Stock $stock';
                          return DesktopListRow(
                            height: compact ? 72 : 82,
                            leading: Container(
                              width: compact ? 30 : 44,
                              height: compact ? 30 : 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF0F7),
                                borderRadius: BorderRadius.circular(
                                  compact ? 10 : 14,
                                ),
                              ),
                              child: Icon(
                                Icons.map_outlined,
                                color: Color(0xFF2C4766),
                                size: compact ? 16 : 20,
                              ),
                            ),
                            title: Text(
                              '$code  •  $name',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 12.4 : null,
                              ),
                              maxLines: compact ? 1 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitleText,
                              style: TextStyle(
                                color: const Color(0xFF6E7791),
                                fontSize: compact ? 10.8 : null,
                                height: compact ? 1.1 : null,
                              ),
                              maxLines: 1,
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

class _CompactProductsToolbar extends StatelessWidget {
  const _CompactProductsToolbar({
    required this.controller,
    required this.includeInactive,
    required this.includeDeleted,
    required this.onSubmitted,
    required this.onSearch,
    required this.onToggleInactive,
    required this.onToggleDeleted,
  });

  final TextEditingController controller;
  final bool includeInactive;
  final bool includeDeleted;
  final VoidCallback onSearch;
  final VoidCallback onSubmitted;
  final ValueChanged<bool> onToggleInactive;
  final ValueChanged<bool> onToggleDeleted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DesktopSearchField(
            controller: controller,
            hintText: 'Codigo, nombre o descripcion',
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CompactProductsFilterChip(
                  label: 'Inactivos',
                  selected: includeInactive,
                  onSelected: onToggleInactive,
                ),
                const SizedBox(width: 6),
                _CompactProductsFilterChip(
                  label: 'Eliminados',
                  selected: includeDeleted,
                  onSelected: onToggleDeleted,
                ),
                const SizedBox(width: 6),
                DesktopToolbarIconAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Buscar',
                  tone: DesktopToolbarActionTone.filled,
                  onPressed: onSearch,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactProductsFilterChip extends StatelessWidget {
  const _CompactProductsFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: onSelected,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        color: selected ? const Color(0xFF173450) : const Color(0xFF5F6C80),
      ),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      side: const BorderSide(color: Color(0xFFDCE4EE)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFEAF0F7),
      showCheckmark: false,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive, required this.isDeleted});

  final bool isActive;
  final bool isDeleted;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
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
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10.5 : 12,
        ),
      ),
    );
  }
}


