import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/users/users_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _searchController = TextEditingController();
  Future<UsersSnapshot>? _future;
  int _lastTick = -1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = UsersService(context.read<ApiClient>()).fetchSnapshot(
        search: _searchController.text,
      );
    }

    return FutureBuilder<UsersSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }

        final data = snapshot.data!;

        return ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Usuarios en solo lectura',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'El panel web solo consulta usuarios y roles asignados. Las acciones de crear, editar o eliminar no estan disponibles aqui.',
                      style: TextStyle(color: Color(0xFF5F6570)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Buscar usuario',
                            ),
                            onSubmitted: (_) => setState(() => _future = null),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => setState(() => _future = null),
                          child: const Text('Buscar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Correo')),
                      DataColumn(label: Text('Usuario')),
                      DataColumn(label: Text('Roles')),
                      DataColumn(label: Text('Estado')),
                    ],
                    rows: data.users
                        .map(
                          (user) => DataRow(cells: [
                            DataCell(Text(user.fullName)),
                            DataCell(Text(user.email)),
                            DataCell(Text(user.username)),
                            DataCell(
                              Wrap(
                                spacing: 6,
                                children: user.roles
                                    .map((role) => Chip(label: Text(role.name)))
                                    .toList(),
                              ),
                            ),
                            DataCell(
                              Text(user.isActive ? 'Activo' : 'Inactivo'),
                            ),
                          ]),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
