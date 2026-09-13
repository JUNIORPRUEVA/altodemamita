import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../domain/lot.dart';

/// Lista + detalle de SOLARES en el layout compacto (patrón Ventas).
class LotsMobileView extends StatelessWidget {
  const LotsMobileView({
    super.key,
    required this.lots,
    required this.query,
    required this.isLoading,
    required this.isRefreshing,
    required this.refreshFailed,
    required this.searchFailed,
    required this.hasVisibleData,
    required this.loadErrorTitle,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
    required this.onSearch,
    required this.onClearSearch,
    required this.onRetry,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    this.onToggleOnlyAvailable,
    this.onlyAvailable = false,
  });

  final List<Lot> lots;
  final String query;
  final bool isLoading;
  final bool isRefreshing;
  final bool refreshFailed;
  final bool searchFailed;
  final bool hasVisibleData;
  final String? loadErrorTitle;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onRetry;
  final VoidCallback onCreate;
  final ValueChanged<Lot> onEdit;
  final ValueChanged<Lot> onDelete;
  final VoidCallback? onToggleOnlyAvailable;
  final bool onlyAvailable;

  @override
  Widget build(BuildContext context) {
    return MobileModuleListView<Lot>(
      searchHint: 'Buscar solares…',
      items: lots,
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      refreshFailed: refreshFailed,
      searchFailed: searchFailed,
      hasVisibleData: hasVisibleData,
      query: query,
      loadErrorTitle: loadErrorTitle,
      onSearch: onSearch,
      onClearSearch: onClearSearch,
      onRetry: onRetry,
      emptyTitle: 'Todavía no hay solares',
      emptyMessage:
          'Agrega solares al inventario para asociarlos a ventas y pagos.',
      emptyIcon: Icons.map_outlined,
      emptyActionLabel: canCreate ? 'Agregar primer solar' : null,
      onEmptyAction: canCreate ? onCreate : null,
      searchEmptyMessage: 'No se encontraron solares para tu búsqueda.',
      fabTooltip: 'Nuevo solar',
      fabIcon: Icons.add_location_alt_outlined,
      onFabPressed: canCreate ? onCreate : null,
      itemBuilder: (context, lot) => MobileEntityRow(
        title: 'Solar ${lot.displayCode}',
        subtitle: '${lot.area.toStringAsFixed(2)} m² · '
            '${MobileUi.money(lot.totalPrice)}',
        meta: 'Precio por m²: ${MobileUi.money(lot.pricePerSquareMeter)}',
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lotStatusColor(lot.status).withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.map_outlined,
            size: 20,
            color: lotStatusColor(lot.status),
          ),
        ),
        onTap: () => _openDetail(context, lot),
        menu: (canUpdate || canDelete)
            ? MobileRowMenu<_LotAction>(
                onSelected: (action) {
                  switch (action) {
                    case _LotAction.edit:
                      onEdit(lot);
                    case _LotAction.delete:
                      onDelete(lot);
                  }
                },
                itemBuilder: (context) => [
                  if (canUpdate)
                    const PopupMenuItem(
                      value: _LotAction.edit,
                      child: Text('Editar'),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: _LotAction.delete,
                      child: Text('Eliminar'),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, Lot lot) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LotDetailPage(
          lot: lot,
          canUpdate: canUpdate,
          canDelete: canDelete,
          onEdit: () async => onEdit(lot),
          onDelete: () async => onDelete(lot),
        ),
      ),
    );
  }
}

enum _LotAction { edit, delete }

/// Detalle de solar a pantalla completa (sin identificadores técnicos).
class LotDetailPage extends StatelessWidget {
  const LotDetailPage({
    super.key,
    required this.lot,
    this.canUpdate = false,
    this.canDelete = false,
    this.onEdit,
    this.onDelete,
  });

  final Lot lot;
  final bool canUpdate;
  final bool canDelete;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return MobileDetailScaffold(
      title: 'Detalle de solar',
      menu: (canUpdate || canDelete)
          ? PopupMenuButton<_LotDetailAction>(
              tooltip: 'Acciones',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: MobileUi.textPrimary,
              ),
              onSelected: (action) async {
                switch (action) {
                  case _LotDetailAction.edit:
                    await onEdit?.call();
                  case _LotDetailAction.delete:
                    await onDelete?.call();
                    if (context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                }
              },
              itemBuilder: (context) => [
                if (canUpdate && onEdit != null)
                  const PopupMenuItem(
                    value: _LotDetailAction.edit,
                    child: Text('Editar solar'),
                  ),
                if (canDelete && onDelete != null)
                  const PopupMenuItem(
                    value: _LotDetailAction.delete,
                    child: Text('Eliminar solar'),
                  ),
              ],
            )
          : null,
      children: [
        MobileDetailIdentityCard(
          title: 'Solar ${lot.displayCode}',
          subtitle: '${lot.area.toStringAsFixed(2)} m²',
          chip: MobileStatusChip(
            label: lotStatusLabel(lot.status),
            color: lotStatusColor(lot.status),
          ),
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Datos del solar',
          rows: [
            MobileInfoItem('Manzana', lot.blockNumber),
            MobileInfoItem('Solar', lot.lotNumber),
            MobileInfoItem('Área', '${lot.area.toStringAsFixed(2)} m²'),
            MobileInfoItem(
              'Precio por m²',
              MobileUi.money(lot.pricePerSquareMeter),
            ),
          ],
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Resumen',
          rows: [
            MobileInfoItem('Precio total', MobileUi.money(lot.totalPrice)),
            MobileInfoItem('Estado', lotStatusLabel(lot.status)),
            MobileInfoItem('Registrado', MobileUi.date(lot.createdAt)),
          ],
        ),
        if (canUpdate || canDelete) ...[
          const SizedBox(height: 18),
          MobileSection(
            title: 'Acciones',
            rows: const [],
            footer: Column(
              children: [
                if (canUpdate && onEdit != null)
                  MobileDetailActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Editar solar',
                    onTap: () => onEdit!.call(),
                  ),
                if (canDelete && onDelete != null)
                  MobileDetailActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Eliminar solar',
                    color: MobileUi.danger,
                    onTap: () => onDelete!.call(),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

enum _LotDetailAction { edit, delete }

String lotStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'disponible':
      return 'Disponible';
    case 'reservado':
      return 'Reservado';
    case 'vendido':
      return 'Vendido';
    default:
      return status;
  }
}

Color lotStatusColor(String status) {
  switch (status.trim().toLowerCase()) {
    case 'disponible':
      return MobileUi.success;
    case 'reservado':
      return MobileUi.warning;
    case 'vendido':
      return MobileUi.info;
    default:
      return MobileUi.textSecondary;
  }
}
