import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../../auth/domain/user_model.dart';

/// Lista + detalle de USUARIOS en el layout compacto (patrón Ventas).
class UsersMobileView extends StatelessWidget {
  const UsersMobileView({
    super.key,
    required this.users,
    required this.isReadOnly,
    required this.canManage,
    required this.currentUserId,
    required this.onRetry,
    required this.onCreate,
    required this.onRecoveryCode,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final List<UserModel> users;
  final bool isReadOnly;
  final bool canManage;
  final int? currentUserId;
  final VoidCallback onRetry;
  final VoidCallback onCreate;
  final VoidCallback onRecoveryCode;
  final ValueChanged<UserModel> onEdit;
  final void Function(UserModel user, bool active) onToggleActive;
  final ValueChanged<UserModel> onDelete;

  bool get _canAct => canManage && !isReadOnly;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Scaffold(
        backgroundColor: MobileUi.background,
        body: MobileEmptyState(
          title: 'Todavía no hay usuarios',
          message: 'Crea el primer usuario para dar acceso al sistema.',
          icon: Icons.people_outline,
          actionLabel: _canAct ? 'Nuevo usuario' : null,
          onAction: _canAct ? onCreate : null,
        ),
      );
    }

    return Scaffold(
      backgroundColor: MobileUi.background,
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          MobileUi.listPadding,
          10,
          MobileUi.listPadding,
          88,
        ),
        itemCount: users.length + (_canAct ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: MobileUi.rowGap),
        itemBuilder: (context, index) {
          if (index >= users.length) {
            // Acceso secundario: código de recuperación.
            return MobileEntityRow(
              title: 'Código de recuperación',
              subtitle: 'Genera un código nuevo para restablecer accesos',
              leading: const Icon(
                Icons.key_outlined,
                color: MobileUi.primary,
              ),
              onTap: onRecoveryCode,
            );
          }
          final user = users[index];
          return MobileEntityRow(
            title: user.nombre.trim().isEmpty
                ? 'Usuario sin nombre'
                : user.nombre,
            subtitle: user.email,
            meta: user.isAdmin
                ? 'Administrador · acceso total'
                : '${user.permissions.where((permission) => permission.read).length} '
                      'módulos habilitados',
            leading: MobileInitialAvatar(
              name: user.nombre,
              color: user.activo ? MobileUi.primary : MobileUi.textMuted,
            ),
            trailing: SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MobileStatusChip(
                    label: user.role.label,
                    color: user.isAdmin
                        ? MobileUi.primary
                        : MobileUi.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  MobileStatusChip(
                    label: user.activo ? 'Activo' : 'Inactivo',
                    color: user.activo
                        ? MobileUi.success
                        : MobileUi.danger,
                  ),
                ],
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UserDetailPage(
                  user: user,
                  isCurrentUser: currentUserId == user.id,
                  canManage: _canAct && currentUserId != user.id,
                  onEdit: () async => onEdit(user),
                  onToggleActive: () async => onToggleActive(user, !user.activo),
                  onDelete: () async => onDelete(user),
                ),
              ),
            ),
            menu: _canAct && currentUserId != user.id
                ? MobileRowMenu<_UserAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _UserAction.edit:
                          onEdit(user);
                        case _UserAction.toggleActive:
                          onToggleActive(user, !user.activo);
                        case _UserAction.delete:
                          onDelete(user);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _UserAction.edit,
                        child: Text('Editar'),
                      ),
                      PopupMenuItem(
                        value: _UserAction.toggleActive,
                        child: Text(
                          user.activo ? 'Desactivar' : 'Activar',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _UserAction.delete,
                        child: Text('Eliminar'),
                      ),
                    ],
                  )
                : null,
          );
        },
      ),
      floatingActionButton: _canAct
          ? FloatingActionButton(
              tooltip: 'Nuevo usuario',
              onPressed: onCreate,
              child: const Icon(Icons.person_add_alt_1_outlined),
            )
          : null,
    );
  }
}

enum _UserAction { edit, toggleActive, delete }

/// Detalle de usuario a pantalla completa (sin identificadores técnicos).
class UserDetailPage extends StatelessWidget {
  const UserDetailPage({
    super.key,
    required this.user,
    this.isCurrentUser = false,
    this.canManage = false,
    this.onEdit,
    this.onToggleActive,
    this.onDelete,
  });

  final UserModel user;
  final bool isCurrentUser;
  final bool canManage;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onToggleActive;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = user.nombre.trim().isEmpty
        ? 'Usuario sin nombre'
        : user.nombre.trim();
    final phone = (user.telefono ?? '').trim();
    final enabledModules = user.permissions
        .where((permission) => permission.read)
        .length;

    return MobileDetailScaffold(
      title: 'Detalle de usuario',
      menu: canManage
          ? PopupMenuButton<_UserDetailAction>(
              tooltip: 'Acciones',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: MobileUi.textPrimary,
              ),
              onSelected: (action) async {
                switch (action) {
                  case _UserDetailAction.edit:
                    await onEdit?.call();
                  case _UserDetailAction.toggleActive:
                    await onToggleActive?.call();
                  case _UserDetailAction.delete:
                    await onDelete?.call();
                    if (context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _UserDetailAction.edit,
                  child: Text('Editar usuario'),
                ),
                PopupMenuItem(
                  value: _UserDetailAction.toggleActive,
                  child: Text(
                    user.activo ? 'Desactivar usuario' : 'Activar usuario',
                  ),
                ),
                const PopupMenuItem(
                  value: _UserDetailAction.delete,
                  child: Text('Eliminar usuario'),
                ),
              ],
            )
          : null,
      children: [
        MobileDetailIdentityCard(
          title: name,
          subtitle: user.email,
          chip: MobileStatusChip(
            label: user.activo ? 'Activo' : 'Inactivo',
            color: user.activo ? MobileUi.success : MobileUi.danger,
          ),
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Datos del usuario',
          rows: [
            MobileInfoItem('Nombre', name),
            MobileInfoItem('Correo', user.email),
            MobileInfoItem('Rol', user.role.label),
            MobileInfoItem(
              'Estado',
              user.activo ? 'Cuenta activa' : 'Cuenta inactiva',
            ),
            MobileInfoItem(
              'Teléfono',
              phone.isEmpty ? 'No registrado' : phone,
            ),
          ],
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Accesos',
          rows: [
            MobileInfoItem(
              'Nivel',
              user.isAdmin ? 'Administrador' : 'Usuario',
            ),
            MobileInfoItem(
              'Módulos habilitados',
              user.isAdmin ? 'Todos' : '$enabledModules',
            ),
            MobileInfoItem(
              'Último cambio de contraseña',
              user.passwordUpdatedAt == null
                  ? 'No disponible'
                  : MobileUi.date(user.passwordUpdatedAt!),
            ),
          ],
        ),
        if (isCurrentUser) ...[
          const SizedBox(height: 18),
          MobileSection(
            title: 'Sesión',
            rows: const [],
            footer: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                'Esta es la cuenta con la que estás trabajando ahora.',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF667085)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _UserDetailAction { edit, toggleActive, delete }
