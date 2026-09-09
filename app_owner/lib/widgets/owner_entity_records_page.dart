import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/responsive.dart';
import '../app/safe_area_padding.dart';
import '../core/utils.dart';
import '../features/sales/sale_detail_page.dart';
import 'animated_list_item.dart';
import 'desktop_detail_pane.dart';
import 'owner_desktop_page_frame.dart';

enum OwnerEntityKind { client, lot, seller }

class OwnerEntityRecordsPage extends StatefulWidget {
  const OwnerEntityRecordsPage({
    super.key,
    required this.kind,
    required this.items,
    this.searchQueryNotifier,
    this.filterNotifier,
    this.allSales = const [],
    this.allLots = const [],
    this.allClients = const [],
    this.allSellers = const [],
  });

  final OwnerEntityKind kind;
  final List<Map<String, dynamic>> items;
  final ValueNotifier<String>? searchQueryNotifier;
  final ValueNotifier<String>? filterNotifier;
  final List<Map<String, dynamic>> allSales;
  final List<Map<String, dynamic>> allLots;
  final List<Map<String, dynamic>> allClients;
  final List<Map<String, dynamic>> allSellers;

  @override
  State<OwnerEntityRecordsPage> createState() => _OwnerEntityRecordsPageState();
}

class _OwnerEntityRecordsPageState extends State<OwnerEntityRecordsPage> {
  String _query = '';
  String _filter = 'Todos';

  @override
  void initState() {
    super.initState();
    widget.searchQueryNotifier?.addListener(_onQueryChanged);
    widget.filterNotifier?.addListener(_onFilterChanged);
    _query = widget.searchQueryNotifier?.value ?? '';
    _filter = widget.filterNotifier?.value ?? _defaultFilter;
  }

  @override
  void dispose() {
    widget.searchQueryNotifier?.removeListener(_onQueryChanged);
    widget.filterNotifier?.removeListener(_onFilterChanged);
    super.dispose();
  }

  String get _defaultFilter => switch (widget.kind) {
    OwnerEntityKind.client => 'Todos',
    OwnerEntityKind.lot => 'Todos',
    OwnerEntityKind.seller => 'Todos',
  };

  void _onQueryChanged() {
    setState(() => _query = widget.searchQueryNotifier?.value ?? '');
  }

  void _onFilterChanged() {
    setState(() => _filter = widget.filterNotifier?.value ?? _defaultFilter);
  }

  List<Map<String, dynamic>> get _filteredItems {
    final query = _query.trim().toLowerCase();
    return widget.items
        .where((item) {
          if (query.isNotEmpty &&
              !item.toString().toLowerCase().contains(query)) {
            return false;
          }

          return switch (widget.kind) {
            OwnerEntityKind.client => _matchesClientFilter(item),
            OwnerEntityKind.lot => _matchesLotFilter(item),
            OwnerEntityKind.seller => _matchesSellerFilter(item),
          };
        })
        .toList(growable: false);
  }

  bool _matchesClientFilter(Map<String, dynamic> item) {
    if (_filter == 'Todos') return true;
    final sales = _relatedSalesForClient(item);
    if (_filter == 'Con ventas') return sales.isNotEmpty;
    if (_filter == 'Sin ventas') return sales.isEmpty;
    if (_filter == 'Con deuda') {
      return sales.any((sale) => _asNum(sale['balance']) > 0);
    }
    return true;
  }

  bool _matchesLotFilter(Map<String, dynamic> item) {
    if (_filter == 'Todos') return true;
    final status = text(item['status'], '').toLowerCase();
    if (_filter == 'Disponibles') {
      return status.contains('dispon') || status.contains('available');
    }
    if (_filter == 'Vendidos') {
      return status.contains('vend') || status.contains('sold');
    }
    if (_filter == 'Apartados') {
      return status.contains('apart') || status.contains('reserv');
    }
    return true;
  }

  bool _matchesSellerFilter(Map<String, dynamic> item) {
    if (_filter == 'Todos') return true;
    final sales = _relatedSalesForSeller(item);
    if (_filter == 'Con ventas') return sales.isNotEmpty;
    if (_filter == 'Sin ventas') return sales.isEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    return OwnerDesktopPageFrame(
      maxWidth: 1120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: Responsive.isDesktop(context) ? 20 : 16,
                bottom: mobileSafeBottomPadding(context),
              ),
              itemCount: items.isEmpty ? 2 : items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _EntityListHeader(
                    filter: _filter,
                    defaultFilter: _defaultFilter,
                    count: items.length,
                    countLabel: _countLabel(items.length),
                    onClearFilter: () {
                      setState(() => _filter = _defaultFilter);
                      widget.filterNotifier?.value = _defaultFilter;
                    },
                  );
                }

                if (items.isEmpty) {
                  return _EmptyEntityState(
                    hasFilter: _query.isNotEmpty || _filter != _defaultFilter,
                    onClear: () {
                      setState(() {
                        _query = '';
                        _filter = _defaultFilter;
                      });
                      widget.searchQueryNotifier?.value = '';
                      widget.filterNotifier?.value = _defaultFilter;
                    },
                  );
                }

                final itemIndex = index - 1;
                final item = items[itemIndex];
                return AnimatedListItem(
                  index: itemIndex,
                  child: _EntityCard(
                    title: _title(item),
                    subtitle: _subtitle(item),
                    meta: _meta(item),
                    icon: _icon,
                    accent: _accent(item),
                    onTap: () => _openDetail(context, item),
                    actions: _actionsFor(context, item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _countLabel(int count) {
    return switch (widget.kind) {
      OwnerEntityKind.client => count == 1 ? 'cliente' : 'clientes',
      OwnerEntityKind.lot => count == 1 ? 'solar' : 'solares',
      OwnerEntityKind.seller => count == 1 ? 'vendedor' : 'vendedores',
    };
  }

  IconData get _icon => switch (widget.kind) {
    OwnerEntityKind.client => Icons.person_outline_rounded,
    OwnerEntityKind.lot => Icons.map_outlined,
    OwnerEntityKind.seller => Icons.badge_outlined,
  };

  String _title(Map<String, dynamic> item) => switch (widget.kind) {
    OwnerEntityKind.client => text(item['name'], 'Cliente sin nombre'),
    OwnerEntityKind.lot => 'Solar ${text(item['number'], '-')}',
    OwnerEntityKind.seller => text(item['name'], 'Vendedor sin nombre'),
  };

  String _subtitle(Map<String, dynamic> item) => switch (widget.kind) {
    OwnerEntityKind.client => text(item['document'], 'Documento no indicado'),
    OwnerEntityKind.lot => 'Manzana ${text(item['block'], '-')}',
    OwnerEntityKind.seller => text(item['document'], 'Documento no indicado'),
  };

  String _meta(Map<String, dynamic> item) {
    return switch (widget.kind) {
      OwnerEntityKind.client =>
        '${_relatedSalesForClient(item).length} ventas · ${_relatedLotsForClient(item).length} solares',
      OwnerEntityKind.lot =>
        '${text(item['status'], 'Sin estado')} · ${money(item['price'])}',
      OwnerEntityKind.seller =>
        '${_relatedSalesForSeller(item).length} ventas asignadas',
    };
  }

  Color _accent(Map<String, dynamic> item) {
    if (widget.kind != OwnerEntityKind.lot) return AppColors.primary;
    final status = text(item['status'], '').toLowerCase();
    if (status.contains('dispon') || status.contains('available')) {
      return AppColors.accentGreen;
    }
    if (status.contains('apart') || status.contains('reserv')) {
      return AppColors.accentAmber;
    }
    if (status.contains('vend') || status.contains('sold')) {
      return AppColors.primary;
    }
    return AppColors.textSecondary;
  }

  List<_EntityAction> _actionsFor(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    return switch (widget.kind) {
      OwnerEntityKind.client => [
        _EntityAction(
          label: 'Ver ventas',
          icon: Icons.point_of_sale_outlined,
          enabled: _relatedSalesForClient(item).isNotEmpty,
          onTap: () => _openSalesList(
            context,
            title: 'Ventas del cliente',
            sales: _relatedSalesForClient(item),
          ),
        ),
        _EntityAction(
          label: 'Ver solares',
          icon: Icons.map_outlined,
          enabled: _relatedLotsForClient(item).isNotEmpty,
          onTap: () => _openRelatedList(
            context,
            title: 'Solares asignados',
            children: _relatedLotsForClient(item)
                .map(
                  (lot) => _ReferenceTile(
                    icon: Icons.map_outlined,
                    title: 'Solar ${text(lot['number'], '-')}',
                    subtitle: 'Manzana ${text(lot['block'], '-')}',
                    trailing: text(lot['status'], '-'),
                  ),
                )
                .toList(),
          ),
        ),
      ],
      OwnerEntityKind.lot => [
        _EntityAction(
          label: 'Ver venta',
          icon: Icons.point_of_sale_outlined,
          enabled: _relatedSalesForLot(item).isNotEmpty,
          onTap: () => _openSalesList(
            context,
            title: 'Venta del solar',
            sales: _relatedSalesForLot(item),
          ),
        ),
        _EntityAction(
          label: 'Ver cliente',
          icon: Icons.person_outline_rounded,
          enabled: _relatedClientsForLot(item).isNotEmpty,
          onTap: () => _openRelatedList(
            context,
            title: 'Cliente asignado',
            children: _relatedClientsForLot(item)
                .map(
                  (client) => _ReferenceTile(
                    icon: Icons.person_outline_rounded,
                    title: text(client['name'], 'Cliente'),
                    subtitle: text(client['document'], '-'),
                    trailing: text(client['phone'], ''),
                  ),
                )
                .toList(),
          ),
        ),
      ],
      OwnerEntityKind.seller => [
        _EntityAction(
          label: 'Ver ventas',
          icon: Icons.point_of_sale_outlined,
          enabled: _relatedSalesForSeller(item).isNotEmpty,
          onTap: () => _openSalesList(
            context,
            title: 'Ventas del vendedor',
            sales: _relatedSalesForSeller(item),
          ),
        ),
        _EntityAction(
          label: 'Ver clientes',
          icon: Icons.people_alt_outlined,
          enabled: _relatedClientsForSeller(item).isNotEmpty,
          onTap: () => _openRelatedList(
            context,
            title: 'Clientes vinculados',
            children: _relatedClientsForSeller(item)
                .map(
                  (client) => _ReferenceTile(
                    icon: Icons.person_outline_rounded,
                    title: text(client['name'], 'Cliente'),
                    subtitle: text(client['document'], '-'),
                    trailing: text(client['phone'], ''),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    };
  }

  void _openDetail(BuildContext context, Map<String, dynamic> item) {
    if (DesktopDetailScope.openIfAvailable(
      context,
      () => _EntityDetailPage(
        appBarTitle: _detailTitle,
        title: _title(item),
        subtitle: _subtitle(item),
        icon: _icon,
        accent: _accent(item),
        fields: _fields(item),
        references: _detailReferences(context, item),
      ),
    )) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EntityDetailPage(
          appBarTitle: _detailTitle,
          title: _title(item),
          subtitle: _subtitle(item),
          icon: _icon,
          accent: _accent(item),
          fields: _fields(item),
          references: _detailReferences(context, item),
        ),
      ),
    );
  }

  String get _detailTitle => switch (widget.kind) {
    OwnerEntityKind.client => 'Detalle de cliente',
    OwnerEntityKind.lot => 'Detalle de solar',
    OwnerEntityKind.seller => 'Detalle de vendedor',
  };

  List<RecordField> _fields(Map<String, dynamic> item) {
    return switch (widget.kind) {
      OwnerEntityKind.client => [
        RecordField('Teléfono', text(item['phone'], '-')),
        RecordField('Dirección', text(item['address'], '-')),
        RecordField('Actualizado', dateText(item['updatedAt'])),
      ],
      OwnerEntityKind.lot => [
        RecordField('Área', money(item['area'])),
        RecordField('Precio/m2', money(item['price'])),
        RecordField('Actualizado', dateText(item['updatedAt'])),
      ],
      OwnerEntityKind.seller => [
        RecordField('Teléfono', text(item['phone'], '-')),
        RecordField('Actualizado', dateText(item['updatedAt'])),
      ],
    };
  }

  List<_ReferenceSection> _detailReferences(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    return _actionsFor(context, item)
        .where((action) => action.enabled)
        .map(
          (action) => _ReferenceSection(
            title: action.label,
            icon: action.icon,
            onTap: action.onTap,
          ),
        )
        .toList();
  }

  void _openSalesList(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> sales,
  }) {
    _openRelatedList(
      context,
      title: title,
      children: sales
          .map(
            (sale) => _ReferenceTile(
              icon: Icons.point_of_sale_outlined,
              title: text(sale['client'], 'Venta'),
              subtitle: 'Solar ${text(sale['lot'], '-')}',
              trailing: money(sale['balance']),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SaleDetailPage(
                    sale: sale,
                    allClients: widget.allClients,
                    allSellers: widget.allSellers,
                    allLots: widget.allLots,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  void _openRelatedList(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReferenceListPage(title: title, children: children),
      ),
    );
  }

  List<Map<String, dynamic>> _relatedSalesForClient(Map<String, dynamic> item) {
    final ids = _ids(item);
    final name = text(item['name'], '').toLowerCase();
    final document = text(item['document'], '').toLowerCase();
    return widget.allSales
        .where((sale) {
          return ids.any((id) => _saleClientIds(sale).contains(id)) ||
              (name.isNotEmpty &&
                  text(sale['client'], '').toLowerCase() == name) ||
              (document.isNotEmpty &&
                  text(
                        sale['cedula'] ?? sale['clientDocument'],
                        '',
                      ).toLowerCase() ==
                      document);
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _relatedLotsForClient(Map<String, dynamic> item) {
    final sales = _relatedSalesForClient(item);
    final lotKeys = sales
        .map((sale) => text(sale['lot'], '').toLowerCase())
        .toSet();
    final lotIds = sales
        .expand((sale) => [sale['lotSyncId'], sale['lotId'], sale['solarId']])
        .whereType<Object>()
        .map((id) => id.toString())
        .toSet();
    return widget.allLots
        .where((lot) {
          return _ids(lot).any(lotIds.contains) ||
              lotKeys.contains(text(lot['number'], '').toLowerCase()) ||
              lotKeys.contains(
                'solar ${text(lot['number'], '').toLowerCase()}',
              );
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _relatedSalesForLot(Map<String, dynamic> item) {
    final ids = _ids(item);
    final number = text(item['number'], '').toLowerCase();
    return widget.allSales
        .where((sale) {
          final lot = text(sale['lot'] ?? sale['solar'], '').toLowerCase();
          return ids.any((id) => _saleLotIds(sale).contains(id)) ||
              (number.isNotEmpty && (lot == number || lot == 'solar $number'));
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _relatedClientsForLot(Map<String, dynamic> item) {
    final sales = _relatedSalesForLot(item);
    final clientIds = sales.expand(_saleClientIds).toSet();
    final names = sales
        .map((sale) => text(sale['client'], '').toLowerCase())
        .toSet();
    return widget.allClients
        .where((client) {
          return _ids(client).any(clientIds.contains) ||
              names.contains(text(client['name'], '').toLowerCase());
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _relatedSalesForSeller(Map<String, dynamic> item) {
    final ids = _ids(item);
    final name = text(item['name'], '').toLowerCase();
    return widget.allSales
        .where((sale) {
          return ids.any((id) => _saleSellerIds(sale).contains(id)) ||
              (name.isNotEmpty &&
                  text(sale['seller'], '').toLowerCase() == name);
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _relatedClientsForSeller(
    Map<String, dynamic> item,
  ) {
    final sales = _relatedSalesForSeller(item);
    final clientIds = sales.expand(_saleClientIds).toSet();
    final names = sales
        .map((sale) => text(sale['client'], '').toLowerCase())
        .toSet();
    return widget.allClients
        .where((client) {
          return _ids(client).any(clientIds.contains) ||
              names.contains(text(client['name'], '').toLowerCase());
        })
        .toList(growable: false);
  }

  Set<String> _ids(Map<String, dynamic> item) {
    return [
      item['syncId'],
      item['id'],
      item['localId'],
      item['clientSyncId'],
      item['sellerSyncId'],
      item['lotSyncId'],
    ].whereType<Object>().map((id) => id.toString()).toSet();
  }

  Set<String> _saleClientIds(Map<String, dynamic> sale) {
    return [
      sale['clientSyncId'],
      sale['clientId'],
      sale['customerId'],
    ].whereType<Object>().map((id) => id.toString()).toSet();
  }

  Set<String> _saleLotIds(Map<String, dynamic> sale) {
    return [
      sale['lotSyncId'],
      sale['lotId'],
      sale['solarId'],
    ].whereType<Object>().map((id) => id.toString()).toSet();
  }

  Set<String> _saleSellerIds(Map<String, dynamic> sale) {
    return [
      sale['sellerSyncId'],
      sale['sellerId'],
      sale['vendorId'],
    ].whereType<Object>().map((id) => id.toString()).toSet();
  }

  num _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _EntityListHeader extends StatelessWidget {
  const _EntityListHeader({
    required this.filter,
    required this.defaultFilter,
    required this.count,
    required this.countLabel,
    required this.onClearFilter,
  });

  final String filter;
  final String defaultFilter;
  final int count;
  final String countLabel;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter != defaultFilter) ...[
          _ActiveFilterChip(label: filter, onClear: onClearFilter),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '$count $countLabel',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onClear,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntityCard extends StatelessWidget {
  const _EntityCard({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.accent,
    required this.actions,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final Color accent;
  final List<_EntityAction> actions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final radius = isDesktop ? 14.0 : 18.0;

    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 18 : 15,
              isDesktop ? 16 : 14,
              isDesktop ? 14 : 12,
              isDesktop ? 16 : 14,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: isDesktop ? 0.025 : 0.035,
                  ),
                  blurRadius: isDesktop ? 8 : 12,
                  offset: Offset(0, isDesktop ? 3 : 5),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.2,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.3,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.3,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_EntityAction>(
                  tooltip: 'Acciones',
                  padding: EdgeInsets.zero,
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  onSelected: (action) => action.onTap(),
                  itemBuilder: (_) => actions
                      .map(
                        (action) => PopupMenuItem<_EntityAction>(
                          value: action,
                          enabled: action.enabled,
                          child: Row(
                            children: [
                              Icon(
                                action.icon,
                                size: 18,
                                color: action.enabled
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                action.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: action.enabled
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntityAction {
  const _EntityAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
}

class _EntityDetailPage extends StatelessWidget {
  const _EntityDetailPage({
    required this.appBarTitle,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.fields,
    required this.references,
  });

  final String appBarTitle;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<RecordField> fields;
  final List<_ReferenceSection> references;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          appBarTitle,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _EntityTopIdentity(
              title: title,
              subtitle: subtitle,
              icon: icon,
              accent: accent,
              onTitleTap: () => _showFullTitle(context),
            ),
            const SizedBox(height: 18),
            if (fields.isNotEmpty)
              _DetailBlock(title: 'Información', fields: fields),
            if (references.isNotEmpty) ...[
              const SizedBox(height: 18),
              _ReferenceBlock(references: references),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullTitle(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nombre completo'),
          content: SelectableText(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}

class _EntityTopIdentity extends StatelessWidget {
  const _EntityTopIdentity({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTitleTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: accent, size: 24),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTitleTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 18,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: AppColors.primary.withValues(alpha: 0.65),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.fields});

  final String title;
  final List<RecordField> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title, icon: Icons.info_outline_rounded),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: fields
                .map(
                  (field) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 124,
                          child: Text(
                            field.label,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            field.value,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.2,
                              height: 1.28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ReferenceBlock extends StatelessWidget {
  const _ReferenceBlock({required this.references});

  final List<_ReferenceSection> references;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Referencias', icon: Icons.link_rounded),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: references
                .map(
                  (ref) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(ref.icon, color: AppColors.primary, size: 19),
                    title: Text(
                      ref.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: ref.onTap,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ReferenceSection {
  const _ReferenceSection({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

class _ReferenceListPage extends StatelessWidget {
  const _ReferenceListPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(padding: safeScrollPadding(context), children: children),
    );
  }
}

class _ReferenceTile extends StatelessWidget {
  const _ReferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing = '',
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: trailing.isEmpty
            ? const Icon(Icons.chevron_right_rounded)
            : Text(
                trailing,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _EmptyEntityState extends StatelessWidget {
  const _EmptyEntityState({required this.hasFilter, required this.onClear});

  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 44,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            const Text(
              'No se encontraron registros',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: onClear,
                child: const Text('Limpiar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
