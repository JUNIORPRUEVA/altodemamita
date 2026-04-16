import 'package:flutter/material.dart';
import '../../../shared/widgets/base_layout.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  int? _selectedUserId;
  List<Map<String, dynamic>> users = [];
  Map<String, List<String>> permissions = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Permisos',
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccionar usuario',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedUserId,
                    hint: const Text('Seleccionar usuario'),
                    items: users
                        .map(
                          (u) => DropdownMenuItem<int>(
                            value: u['id'] as int,
                            child: Text(u['nombre']),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedUserId = value;
                      });
                    },
                  ),
                  if (_selectedUserId != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Módulos y permisos',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _buildModulesList(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildModulesList() {
    final modules = [
      'clientes',
      'solares',
      'ventas',
      'cuotas',
      'pagos',
      'búsqueda',
      'configuración',
      'backup',
    ];
    final actions = [
      'ver',
      'crear',
      'editar',
      'eliminar',
      'imprimir',
      'registrar_pagos',
    ];

    return Column(
      children: modules.map((module) {
        return Card(
          child: ExpansionTile(
            title: Text(module.toUpperCase()),
            children: actions.map((action) {
              return CheckboxListTile(
                title: Text(action),
                value: false, // TODO: Obtener del repositorio
                onChanged: (value) {
                  // TODO: Guardar permiso
                },
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  void _loadUsers() {
    // TODO: Cargar usuarios desde repositorio
    setState(() {
      _isLoading = false;
    });
  }
}
