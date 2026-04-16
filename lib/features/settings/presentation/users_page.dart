import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../data/permission_repository.dart';
import '../data/settings_user_repository.dart';
import '../domain/permission.dart';
import '../domain/settings_user.dart';
import 'user_form_dialog.dart';
import '../../../shared/widgets/base_layout.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<SettingsUser> users = const [];
  Map<int, List<String>> userPermissions = {};
  bool _isLoading = true;

  Future<void> _loadUsers() async {
    final db = await AppDatabase.instance.database;
    final usersRepository = SettingsUserRepository(db);
    final permissionsRepository = PermissionRepository(db);

    final loadedUsers = await usersRepository.getAllUsers();
    final permissionsByUser = <int, List<String>>{};

    for (final user in loadedUsers) {
      final userId = user.id;
      if (userId == null) {
        continue;
      }
      final permissions = await permissionsRepository.getPermissionsByUser(
        userId,
      );
      final tokens = <String>[];
      for (final permission in permissions) {
        for (final action in permission.getActionsList()) {
          tokens.add(_permissionToken(permission.modulo, action));
        }
      }
      permissionsByUser[userId] = tokens;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      users = loadedUsers;
      userPermissions = permissionsByUser;
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Usuarios',
      child: Column(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _UserCard(
                      user: user,
                      onEdit: () => _editUser(user),
                      onToggleStatus: () => _toggleUserStatus(user),
                      onDelete: () => _deleteUser(user),
                      onManagePermissions: () => _managePermissions(user),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            'No hay usuarios registrados',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Crea el primer usuario del sistema',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _createUser,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Crear usuario'),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser() async {
    final user = await UserFormDialog.show(context);
    if (user == null) {
      return;
    }

    final db = await AppDatabase.instance.database;
    final repository = SettingsUserRepository(db);
    await repository.createUser(user.copyWith(fechaCreacion: DateTime.now()));
    await _loadUsers();
  }

  Future<void> _editUser(SettingsUser user) async {
    final updated = await UserFormDialog.show(context, initialUser: user);
    if (updated == null || updated.id == null) {
      return;
    }

    final db = await AppDatabase.instance.database;
    await SettingsUserRepository(db).updateUser(updated);
    await _loadUsers();
  }

  Future<void> _toggleUserStatus(SettingsUser user) async {
    final userId = user.id;
    if (userId == null) {
      return;
    }

    final db = await AppDatabase.instance.database;
    await SettingsUserRepository(db).toggleUserStatus(userId, !user.activo);
    await _loadUsers();
  }

  Future<void> _deleteUser(SettingsUser user) async {
    final userId = user.id;
    if (userId == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
          '¿Eliminar a "${user.nombre}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await AppDatabase.instance.database;
      final usersRepository = SettingsUserRepository(db);
      final permissionsRepository = PermissionRepository(db);

      await permissionsRepository.deletePermissionsForUser(userId);
      await usersRepository.deleteUser(userId);
      await _loadUsers();
    }
  }

  Future<void> _managePermissions(SettingsUser user) async {
    final userId = user.id;
    if (userId == null) {
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => _PermissionsDialog(
        userName: user.nombre,
        userId: userId,
        currentPermissions: userPermissions[userId] ?? const [],
        onSave: (permissions) {
          _savePermissions(userId, permissions);
        },
      ),
    );
  }

  Future<void> _savePermissions(int userId, List<String> permissions) async {
    final db = await AppDatabase.instance.database;
    final permissionsRepository = PermissionRepository(db);

    await permissionsRepository.deletePermissionsForUser(userId);

    final actionsByModule = <String, List<String>>{};
    for (final token in permissions) {
      final separator = token.indexOf('_');
      if (separator <= 0 || separator >= token.length - 1) {
        continue;
      }
      final module = token.substring(0, separator);
      final action = token.substring(separator + 1);
      actionsByModule.putIfAbsent(module, () => <String>[]).add(action);
    }

    for (final entry in actionsByModule.entries) {
      await permissionsRepository.savePermission(
        Permission(
          usuarioId: userId,
          modulo: entry.key,
          acciones: jsonEncode(entry.value.toSet().toList()),
          fechaCreacion: DateTime.now(),
        ),
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    await _loadUsers();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permisos guardados correctamente.')),
    );
  }

  String _permissionToken(String module, String action) => '${module}_$action';
}

/// Tarjeta para mostrar un usuario
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
    required this.onManagePermissions,
  });

  final SettingsUser user;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;
  final VoidCallback onManagePermissions;

  @override
  Widget build(BuildContext context) {
    final isActive = user.activo;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Nombre y Estado
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    user.nombre.isEmpty ? '?' : user.nombre[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nombre,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        user.rol,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(isActive ? 'Activo' : 'Inactivo'),
                  backgroundColor: isActive
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isActive ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Información
            Row(
              children: [
                Icon(Icons.email_outlined, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  (user.email ?? '').isEmpty ? 'Sin correo electrónico' : user.email!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  (user.telefono ?? '').isEmpty
                      ? 'Sin telefono'
                      : user.telefono!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Botones de acción
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onManagePermissions,
                  icon: const Icon(Icons.security_outlined),
                  label: const Text('Permisos'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                ),
                IconButton(
                  onPressed: onToggleStatus,
                  icon: Icon(
                    isActive ? Icons.lock_outline : Icons.lock_open_outlined,
                  ),
                  tooltip: isActive ? 'Bloquear' : 'Desbloquear',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo para gestionar permisos de un usuario
class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({
    required this.userName,
    required this.userId,
    required this.currentPermissions,
    required this.onSave,
  });

  final String userName;
  final int userId;
  final List<String> currentPermissions;
  final Function(List<String>) onSave;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late List<String> _selectedPermissions;

  final modules = Permission.availableModules;

  final actions = Permission.availableActions;

  @override
  void initState() {
    super.initState();
    _selectedPermissions = List.from(widget.currentPermissions);
  }

  String _permissionKey(String module, String action) => '${module}_$action';

  bool _hasPermission(String module, String action) {
    return _selectedPermissions.contains(_permissionKey(module, action));
  }

  void _togglePermission(String module, String action) {
    final key = _permissionKey(module, action);
    setState(() {
      if (_selectedPermissions.contains(key)) {
        _selectedPermissions.remove(key);
      } else {
        _selectedPermissions.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Permisos para ${widget.userName}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final module in modules)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.toUpperCase(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final action in actions)
                              FilterChip(
                                label: Text(action),
                                selected: _hasPermission(module, action),
                                onSelected: (_) =>
                                    _togglePermission(module, action),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => widget.onSave(_selectedPermissions),
          child: const Text('Guardar permisos'),
        ),
      ],
    );
  }
}
