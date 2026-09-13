import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../domain/client.dart';

/// Lista + detalle de CLIENTES en el layout compacto (patrón Ventas).
class ClientsMobileView extends StatelessWidget {
  const ClientsMobileView({
    super.key,
    required this.clients,
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

  final List<Client> clients;
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
  final ValueChanged<Client> onEdit;
  final ValueChanged<Client> onDelete;

  @override
  Widget build(BuildContext context) {
    return MobileModuleListView<Client>(
      searchHint: 'Buscar clientes…',
      items: clients,
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
      emptyTitle: 'Todavía no hay clientes',
      emptyMessage:
          'Crea el primer cliente para usarlo en ventas, pagos y reportes.',
      emptyIcon: Icons.people_outline,
      emptyActionLabel: canCreate ? 'Crear primer cliente' : null,
      onEmptyAction: canCreate ? onCreate : null,
      searchEmptyMessage: 'No se encontraron clientes para tu búsqueda.',
      fabTooltip: 'Nuevo cliente',
      fabIcon: Icons.person_add_alt_1_outlined,
      onFabPressed: canCreate ? onCreate : null,
      itemBuilder: (context, client) => MobileEntityRow(
        title: client.fullName.trim().isEmpty
            ? 'Cliente sin nombre'
            : client.fullName,
        subtitle: client.documentId,
        meta: (client.phone ?? '').trim(),
        leading: MobileInitialAvatar(name: client.fullName),
        onTap: () => _openDetail(context, client),
        menu: (canUpdate || canDelete)
            ? MobileRowMenu<_ClientAction>(
                onSelected: (action) {
                  switch (action) {
                    case _ClientAction.edit:
                      onEdit(client);
                    case _ClientAction.delete:
                      onDelete(client);
                  }
                },
                itemBuilder: (context) => [
                  if (canUpdate)
                    const PopupMenuItem(
                      value: _ClientAction.edit,
                      child: Text('Editar'),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: _ClientAction.delete,
                      child: Text('Eliminar'),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, Client client) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientDetailPage(
          client: client,
          canUpdate: canUpdate,
          canDelete: canDelete,
          onEdit: () async => onEdit(client),
          onDelete: () async => onDelete(client),
        ),
      ),
    );
  }
}

enum _ClientAction { edit, delete }

/// Detalle de cliente a pantalla completa (sin identificadores técnicos).
class ClientDetailPage extends StatelessWidget {
  const ClientDetailPage({
    super.key,
    required this.client,
    this.canUpdate = false,
    this.canDelete = false,
    this.onEdit,
    this.onDelete,
  });

  final Client client;
  final bool canUpdate;
  final bool canDelete;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = client.fullName.trim().isEmpty
        ? 'Cliente sin nombre'
        : client.fullName.trim();
    final address = (client.address ?? '').trim();
    final phone = (client.phone ?? '').trim();

    return MobileDetailScaffold(
      title: 'Detalle de cliente',
      menu: (canUpdate || canDelete)
          ? PopupMenuButton<_DetailAction>(
              tooltip: 'Acciones',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: MobileUi.textPrimary,
              ),
              onSelected: (action) async {
                switch (action) {
                  case _DetailAction.edit:
                    await onEdit?.call();
                  case _DetailAction.delete:
                    await onDelete?.call();
                    if (context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                }
              },
              itemBuilder: (context) => [
                if (canUpdate && onEdit != null)
                  const PopupMenuItem(
                    value: _DetailAction.edit,
                    child: Text('Editar cliente'),
                  ),
                if (canDelete && onDelete != null)
                  const PopupMenuItem(
                    value: _DetailAction.delete,
                    child: Text('Eliminar cliente'),
                  ),
              ],
            )
          : null,
      children: [
        MobileDetailIdentityCard(
          title: name,
          subtitle: client.documentId,
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Datos del cliente',
          rows: [
            MobileInfoItem('Nombre', name),
            MobileInfoItem(
              'Documento',
              client.documentId.trim().isEmpty
                  ? 'No registrado'
                  : client.documentId,
            ),
            MobileInfoItem(
              'Teléfono',
              phone.isEmpty ? 'No registrado' : phone,
            ),
            MobileInfoItem(
              'Dirección',
              address.isEmpty ? 'No registrada' : address,
            ),
          ],
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Registro',
          rows: [
            MobileInfoItem(
              'Cliente desde',
              MobileUi.date(client.createdAt),
            ),
            MobileInfoItem(
              'Última actualización',
              MobileUi.date(client.updatedAt),
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
                    label: 'Editar cliente',
                    onTap: () => onEdit!.call(),
                  ),
                if (canDelete && onDelete != null)
                  MobileDetailActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Eliminar cliente',
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

enum _DetailAction { edit, delete }
