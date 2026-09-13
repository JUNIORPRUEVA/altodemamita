import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../domain/seller.dart';

/// Lista + detalle de VENDEDORES en el layout compacto (patrón Ventas).
class SellersMobileView extends StatelessWidget {
  const SellersMobileView({
    super.key,
    required this.sellers,
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
  });

  final List<Seller> sellers;
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
  final ValueChanged<Seller> onEdit;
  final ValueChanged<Seller> onDelete;

  @override
  Widget build(BuildContext context) {
    return MobileModuleListView<Seller>(
      searchHint: 'Buscar vendedores…',
      items: sellers,
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
      emptyTitle: 'Todavía no hay vendedores',
      emptyMessage: 'Registra vendedores para asignarlos a las ventas.',
      emptyIcon: Icons.storefront_outlined,
      emptyActionLabel: canCreate ? 'Nuevo vendedor' : null,
      onEmptyAction: canCreate ? onCreate : null,
      searchEmptyMessage: 'No se encontraron vendedores para tu búsqueda.',
      fabTooltip: 'Nuevo vendedor',
      fabIcon: Icons.person_add_alt_outlined,
      onFabPressed: canCreate ? onCreate : null,
      itemBuilder: (context, seller) => MobileEntityRow(
        title: seller.name.trim().isEmpty
            ? 'Vendedor sin nombre'
            : seller.name,
        subtitle: seller.documentId,
        meta: seller.phone,
        leading: MobileInitialAvatar(
          name: seller.name,
          color: MobileUi.info,
        ),
        onTap: () => _openDetail(context, seller),
        menu: (canUpdate || canDelete)
            ? MobileRowMenu<_SellerAction>(
                onSelected: (action) {
                  switch (action) {
                    case _SellerAction.edit:
                      onEdit(seller);
                    case _SellerAction.delete:
                      onDelete(seller);
                  }
                },
                itemBuilder: (context) => [
                  if (canUpdate)
                    const PopupMenuItem(
                      value: _SellerAction.edit,
                      child: Text('Editar'),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: _SellerAction.delete,
                      child: Text('Eliminar'),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, Seller seller) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SellerDetailPage(
          seller: seller,
          canUpdate: canUpdate,
          canDelete: canDelete,
          onEdit: () async => onEdit(seller),
          onDelete: () async => onDelete(seller),
        ),
      ),
    );
  }
}

enum _SellerAction { edit, delete }

/// Detalle de vendedor a pantalla completa (sin identificadores técnicos).
class SellerDetailPage extends StatelessWidget {
  const SellerDetailPage({
    super.key,
    required this.seller,
    this.canUpdate = false,
    this.canDelete = false,
    this.onEdit,
    this.onDelete,
  });

  final Seller seller;
  final bool canUpdate;
  final bool canDelete;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = seller.name.trim().isEmpty
        ? 'Vendedor sin nombre'
        : seller.name.trim();
    final phone = seller.phone.trim();

    return MobileDetailScaffold(
      title: 'Detalle de vendedor',
      menu: (canUpdate || canDelete)
          ? PopupMenuButton<_SellerDetailAction>(
              tooltip: 'Acciones',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: MobileUi.textPrimary,
              ),
              onSelected: (action) async {
                switch (action) {
                  case _SellerDetailAction.edit:
                    await onEdit?.call();
                  case _SellerDetailAction.delete:
                    await onDelete?.call();
                    if (context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                }
              },
              itemBuilder: (context) => [
                if (canUpdate && onEdit != null)
                  const PopupMenuItem(
                    value: _SellerDetailAction.edit,
                    child: Text('Editar vendedor'),
                  ),
                if (canDelete && onDelete != null)
                  const PopupMenuItem(
                    value: _SellerDetailAction.delete,
                    child: Text('Eliminar vendedor'),
                  ),
              ],
            )
          : null,
      children: [
        MobileDetailIdentityCard(
          title: name,
          subtitle: seller.documentId,
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Datos del vendedor',
          rows: [
            MobileInfoItem('Nombre', name),
            MobileInfoItem(
              'Documento',
              seller.documentId.trim().isEmpty
                  ? 'No registrado'
                  : seller.documentId,
            ),
            MobileInfoItem(
              'Teléfono',
              phone.isEmpty ? 'No registrado' : phone,
            ),
          ],
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Registro',
          rows: [
            MobileInfoItem('Vendedor desde', MobileUi.date(seller.createdAt)),
            MobileInfoItem(
              'Última actualización',
              MobileUi.date(seller.updatedAt),
            ),
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
                    label: 'Editar vendedor',
                    onTap: () => onEdit!.call(),
                  ),
                if (canDelete && onDelete != null)
                  MobileDetailActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Eliminar vendedor',
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

enum _SellerDetailAction { edit, delete }
