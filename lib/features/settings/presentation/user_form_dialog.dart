import 'package:flutter/material.dart';

import '../domain/settings_user.dart';

class UserFormDialog extends StatefulWidget {
  const UserFormDialog({super.key, this.initialUser});

  final SettingsUser? initialUser;

  static Future<SettingsUser?> show(
    BuildContext context, {
    SettingsUser? initialUser,
  }) {
    return showDialog<SettingsUser>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UserFormDialog(initialUser: initialUser),
    );
  }

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreController;
  late final TextEditingController _emailController;
  late final TextEditingController _telefonoController;

  late String _selectedRol;
  late bool _activo;

  bool get _isEditing => widget.initialUser != null;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: widget.initialUser?.nombre ?? '',
    );
    _emailController = TextEditingController(
      text: widget.initialUser?.email ?? '',
    );
    _telefonoController = TextEditingController(
      text: widget.initialUser?.telefono ?? '',
    );
    _selectedRol = widget.initialUser?.rol ?? 'operador';
    _activo = widget.initialUser?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.manage_accounts_outlined),
      title: Text(_isEditing ? 'Editar usuario' : 'Nuevo usuario'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crea o actualiza usuarios internos con su rol operativo dentro del sistema.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombreController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefonoController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedRol,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: SettingsUser.roles
                      .map((rol) => DropdownMenuItem(
                            value: rol,
                            child: Text(rol),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedRol = value;
                      });
                    }
                  },
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    title: const Text('Activo'),
                    contentPadding: EdgeInsets.zero,
                    value: _activo,
                    onChanged: (value) {
                      setState(() {
                        _activo = value;
                      });
                    },
                  ),
                ],
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
          onPressed: _save,
          child: Text(_isEditing ? 'Guardar cambios' : 'Crear usuario'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final baseUser = widget.initialUser ?? SettingsUser.empty();
    final user = baseUser.copyWith(
      nombre: _nombreController.text.trim(),
      email: _emailController.text.trim(),
      telefono: _telefonoController.text.trim(),
      rol: _selectedRol,
      activo: _activo,
      fechaActualizacion: DateTime.now(),
    );

    Navigator.of(context).pop(user);
  }
}
