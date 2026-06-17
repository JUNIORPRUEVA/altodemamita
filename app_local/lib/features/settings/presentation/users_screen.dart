import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../features/auth/data/auth_service.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/domain/user_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../shared/widgets/base_layout.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final AuthService _authService;

  List<UserModel> _users = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _authService = context.read<AuthProvider>().authService;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final users = await _authService.fetchUsers();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = FriendlyErrorMessages.moduleLoad(
          'usuarios',
          error,
        ).message;
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _canManageUsers(AuthProvider auth) {
    return auth.hasScopedAccess(
      scope: AdminOverrideScope.settingsUsers,
      module: PermissionCatalog.settings,
      action: PermissionAction.update,
    );
  }

  Future<bool> _ensureAuthorized() async {
    final auth = context.read<AuthProvider>();
    if (_canManageUsers(auth)) {
      return true;
    }

    return requestAdminOverride(
      context,
      scope: AdminOverrideScope.settingsUsers,
      title: 'Autorización administrativa requerida',
      message:
          'Necesitas la clave de un administrador para gestionar usuarios y permisos.',
    );
  }

  Future<void> _openEditor({UserModel? user}) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final result = await showDialog<_UserFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserEditorDialog(
        initialUser: user,
        lockSecurityFields: user != null && currentUserId == user.id,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    try {
      if (user == null) {
        await _authService.createUser(
          nombre: result.nombre,
          email: result.email,
          password: result.password,
          role: result.role,
          permissions: result.permissions,
          active: result.active,
        );
      } else {
        await _authService.updateUser(
          user: user,
          nombre: result.nombre,
          email: result.email,
          role: result.role,
          active: result.active,
          permissions: result.permissions,
          newPassword: result.password.isEmpty ? null : result.password,
        );
      }
      await _loadUsers();
      if (!mounted) {
        return;
      }
      await context.read<AuthProvider>().refreshCurrentUser();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            user == null
                ? 'Usuario creado correctamente.'
                : 'Usuario actualizado correctamente.',
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openRecoveryCodeDialog() async {
    if (!await _ensureAuthorized()) {
      return;
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoveryCodeDialog(authService: _authService),
    );
  }

  Future<void> _toggleActive(UserModel user, bool active) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    if (currentUserId == user.id) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No puedes cambiar el estado de tu propia sesion.'),
        ),
      );
      return;
    }

    try {
      await _authService.setUserActive(user: user, active: active);
      await _loadUsers();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    if (currentUserId == user.id) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No puedes eliminar tu propio usuario.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar usuario'),
          content: Text('Se eliminara el usuario ${user.nombre}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _authService.deleteUser(user.id!);
      await _loadUsers();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Usuario eliminado correctamente.')),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isReadOnly = context.watch<SystemConfigService>().isReadOnly;
    final currentUserId = auth.currentUser?.id;

    return BaseLayout(
      title: 'Usuarios',
      child: Column(
        children: [
          _buildHeader(isReadOnly: isReadOnly),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? _buildErrorState()
                : _users.isEmpty
                ? _buildEmptyState(isReadOnly: isReadOnly)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return _UserCard(
                        user: user,
                        readOnly: isReadOnly,
                        isCurrentUser: currentUserId == user.id,
                        onEdit: () => _openEditor(user: user),
                        onDelete: () => _deleteUser(user),
                        onToggleActive: (value) => _toggleActive(user, value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isReadOnly}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Administracion de usuarios y permisos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF132238),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Controla accesos por modulo y accion desde una sola vista.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7494)),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: isReadOnly ? null : () => _openEditor(),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Crear usuario'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: isReadOnly ? null : _openRecoveryCodeDialog,
            icon: const Icon(Icons.key_outlined),
            label: const Text('Clave de recuperacion'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFF8F2436)),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'No se pudieron cargar los usuarios.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadUsers,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool isReadOnly}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.manage_accounts_outlined,
                size: 36,
                color: Color(0xFF3B5BDB),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No hay usuarios configurados todavia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF132238),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Crea el primer usuario operativo y define exactamente a que modulos puede acceder.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7494)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isReadOnly ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Crear usuario'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog({required this.authService});

  final AuthService authService;

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  String? _recoveryCode;
  String? _generatedAt;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _loadRecoveryCode();
  }

  Future<void> _loadRecoveryCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final recoveryCode = await widget.authService
          .getOrCreateAdminRecoveryCode();
      final generatedAt = await widget.authService
          .getAdminRecoveryCodeGeneratedAt();
      if (!mounted) {
        return;
      }
      setState(() {
        _recoveryCode = recoveryCode;
        _generatedAt = generatedAt;
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'No se pudo cargar la clave de recuperacion.';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _regenerateRecoveryCode() async {
    setState(() {
      _isRegenerating = true;
      _errorMessage = null;
    });

    try {
      final recoveryCode = await widget.authService
          .regenerateAdminRecoveryCode();
      final generatedAt = await widget.authService
          .getAdminRecoveryCodeGeneratedAt();
      if (!mounted) {
        return;
      }
      setState(() {
        _recoveryCode = recoveryCode;
        _generatedAt = generatedAt;
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'No se pudo regenerar la clave de recuperacion.';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRegenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clave de recuperacion del administrador'),
      content: SizedBox(
        width: 520,
        child: _isLoading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Guarda esta clave en un lugar seguro. Sirve para recuperar el correo y la contrasena del administrador principal desde la pantalla de login.',
                  ),
                  const SizedBox(height: 14),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFF8F2436)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFDCE5F0)),
                    ),
                    child: SelectableText(
                      _recoveryCode ?? 'No disponible',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if ((_generatedAt ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Generada: ${_generatedAt!}',
                      style: const TextStyle(color: Color(0xFF6B7494)),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isRegenerating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton.tonalIcon(
          onPressed: _isLoading || _isRegenerating
              ? null
              : _regenerateRecoveryCode,
          icon: const Icon(Icons.refresh),
          label: Text(_isRegenerating ? 'Regenerando...' : 'Generar nueva'),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.readOnly,
    required this.isCurrentUser,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final UserModel user;
  final bool readOnly;
  final bool isCurrentUser;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final enabledModules = user.isAdmin
        ? PermissionCatalog.modules.length
        : user.permissions.where((permission) => permission.read).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.nombre.isEmpty ? '?' : user.nombre[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16324F),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.nombre,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF132238),
                              ),
                            ),
                          ),
                          _Tag(
                            label: user.role.label,
                            backgroundColor: user.isAdmin
                                ? const Color(0xFFE8F3EC)
                                : const Color(0xFFEAF0F8),
                            foregroundColor: user.isAdmin
                                ? const Color(0xFF2B6B4A)
                                : const Color(0xFF16324F),
                          ),
                          const SizedBox(width: 8),
                          _Tag(
                            label: user.activo ? 'Activo' : 'Inactivo',
                            backgroundColor: user.activo
                                ? const Color(0xFFF0F8F3)
                                : const Color(0xFFF5F7FA),
                            foregroundColor: user.activo
                                ? const Color(0xFF2B6B4A)
                                : const Color(0xFF6B7494),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7494),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user.isAdmin
                            ? 'Acceso total a todos los modulos y acciones.'
                            : '$enabledModules modulos con permiso de lectura habilitado(s).',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4F5C73),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.isAdmin
                  ? const [
                      _Tag(
                        label: 'Todos los permisos',
                        backgroundColor: Color(0xFFE8F3EC),
                        foregroundColor: Color(0xFF2B6B4A),
                      ),
                    ]
                  : user.permissions
                        .where((permission) => permission.read)
                        .map(
                          (permission) => _Tag(
                            label: _permissionSummary(permission),
                            backgroundColor: const Color(0xFFF5F7FA),
                            foregroundColor: const Color(0xFF16324F),
                          ),
                        )
                        .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: user.activo,
                  onChanged: isCurrentUser || readOnly ? null : onToggleActive,
                ),
                Text(
                  user.activo ? 'Cuenta habilitada' : 'Cuenta bloqueada',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4F5C73),
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: readOnly ? null : onEdit,
                  child: const Text('Editar'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: isCurrentUser || readOnly ? null : onDelete,
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _permissionSummary(PermissionModel permission) {
    final moduleLabel = PermissionCatalog.byKey(permission.module).label;
    final actions = <String>[];
    if (permission.create) {
      actions.add('crear');
    }
    if (permission.update) {
      actions.add('editar');
    }
    if (permission.delete) {
      actions.add('eliminar');
    }
    if (actions.isEmpty) {
      return '$moduleLabel: ver';
    }
    return '$moduleLabel: ${actions.join(', ')}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _UserEditorDialog extends StatefulWidget {
  const _UserEditorDialog({this.initialUser, this.lockSecurityFields = false});

  final UserModel? initialUser;
  final bool lockSecurityFields;

  @override
  State<_UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<_UserEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late UserRole _selectedRole;
  late bool _active;
  late List<PermissionModel> _permissions;

  bool get _isEditing => widget.initialUser != null;

  @override
  void initState() {
    super.initState();
    final initialUser = widget.initialUser;
    _nameController = TextEditingController(text: initialUser?.nombre ?? '');
    _emailController = TextEditingController(text: initialUser?.email ?? '');
    _passwordController = TextEditingController();
    _selectedRole = initialUser?.role ?? UserRole.user;
    _active = initialUser?.activo ?? true;
    _permissions = PermissionCatalog.modules
        .map(
          (module) =>
              initialUser?.permissionFor(module.key) ??
              PermissionModel.empty(module.key),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar usuario' : 'Crear usuario'),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Obligatorio';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Correo electronico',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          if (trimmed.isEmpty || !trimmed.contains('@')) {
                            return 'Correo invalido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: _isEditing
                              ? 'Nueva contrasena (opcional)'
                              : 'Contrasena',
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        validator: (value) {
                          if (!_isEditing && (value ?? '').trim().length < 8) {
                            return 'Minimo 8 caracteres';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<UserRole>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Rol',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                        items: UserRole.values
                            .map(
                              (role) => DropdownMenuItem<UserRole>(
                                value: role,
                                child: Text(role.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: widget.lockSecurityFields
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _selectedRole = value;
                                });
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usuario activo'),
                  subtitle: const Text(
                    'Puede iniciar sesion y operar el sistema',
                  ),
                  value: _active,
                  onChanged: widget.lockSecurityFields
                      ? null
                      : (value) {
                          setState(() {
                            _active = value;
                          });
                        },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _selectedRole == UserRole.admin
                        ? const Color(0xFFE8F3EC)
                        : const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.lockSecurityFields
                        ? 'Tu sesion actual no puede rebajarse ni desactivarse desde este formulario.'
                        : _selectedRole == UserRole.admin
                        ? 'El rol administrador recibe acceso total automaticamente y puede gestionar usuarios.'
                        : 'Selecciona los permisos por modulo y accion. Solo se mostraran modulos con permiso de ver.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF435066),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Permisos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _buildPermissionMatrix(),
              ],
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
          onPressed: _submit,
          child: Text(_isEditing ? 'Guardar cambios' : 'Crear usuario'),
        ),
      ],
    );
  }

  Widget _buildPermissionMatrix() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFD),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Modulo')),
                Expanded(child: Center(child: Text('Ver'))),
                Expanded(child: Center(child: Text('Crear'))),
                Expanded(child: Center(child: Text('Editar'))),
                Expanded(child: Center(child: Text('Eliminar'))),
              ],
            ),
          ),
          for (var index = 0; index < PermissionCatalog.modules.length; index++)
            _PermissionRow(
              module: PermissionCatalog.modules[index],
              permission: _permissions[index],
              enabled: _selectedRole != UserRole.admin,
              onChanged: (permission) {
                setState(() {
                  _permissions = _permissions
                      .asMap()
                      .entries
                      .map(
                        (entry) =>
                            entry.key == index ? permission : entry.value,
                      )
                      .toList(growable: false);
                });
              },
            ),
        ],
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _UserFormResult(
        nombre: _nameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        role: _selectedRole,
        active: _active,
        permissions: _selectedRole == UserRole.admin
            ? PermissionCatalog.modules
                  .map((module) => PermissionModel.full(module.key))
                  .toList(growable: false)
            : _permissions,
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.module,
    required this.permission,
    required this.enabled,
    required this.onChanged,
  });

  final PermissionModuleDefinition module;
  final PermissionModel permission;
  final bool enabled;
  final ValueChanged<PermissionModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEFF3F8))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF132238),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  module.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7494),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Checkbox(
                value: enabled ? permission.read : true,
                onChanged: enabled
                    ? (value) =>
                          onChanged(permission.copyWith(read: value ?? false))
                    : null,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Checkbox(
                value: enabled ? permission.create : true,
                onChanged: enabled
                    ? (value) =>
                          onChanged(permission.copyWith(create: value ?? false))
                    : null,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Checkbox(
                value: enabled ? permission.update : true,
                onChanged: enabled
                    ? (value) =>
                          onChanged(permission.copyWith(update: value ?? false))
                    : null,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Checkbox(
                value: enabled ? permission.delete : true,
                onChanged: enabled
                    ? (value) =>
                          onChanged(permission.copyWith(delete: value ?? false))
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserFormResult {
  const _UserFormResult({
    required this.nombre,
    required this.email,
    required this.password,
    required this.role,
    required this.active,
    required this.permissions,
  });

  final String nombre;
  final String email;
  final String password;
  final UserRole role;
  final bool active;
  final List<PermissionModel> permissions;
}
