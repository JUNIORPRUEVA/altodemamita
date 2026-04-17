import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/users/users_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

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

  void _reload() {
    setState(() => _future = null);
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
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final data = snapshot.data!;
        final compact = MediaQuery.sizeOf(context).width < 760;

        return DesktopPageScaffold(
          title: 'Usuarios',
          subtitle:
              'Supervision de accesos, roles y estado de usuarios con la misma grilla limpia del entorno de escritorio.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar usuario',
                onSubmitted: (_) => _reload(),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar'),
                ),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
              compactActions: [
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
            ),
          ),
          child: data.users.isEmpty
              ? const DesktopEmptyState(
                  icon: Icons.manage_accounts_outlined,
                  title: 'No hay usuarios visibles',
                  message: 'Prueba otro filtro o verifica que el backend este devolviendo el listado esperado.',
                )
              : compact
                  ? DesktopDataListSection(
                      title: 'Usuarios registrados',
                      children: data.users.map((user) {
                        return DesktopListRow(
                          height: 92,
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFFEFF3FB),
                            child: Text(
                              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                color: Color(0xFF223048),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            '${user.username}  •  ${user.email}',
                            style: const TextStyle(color: Color(0xFF6E7791)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...user.roles.map(
                                (role) => DesktopTag(
                                  label: role.name,
                                  background: const Color(0xFFF1F4FA),
                                ),
                              ),
                              DesktopTag(
                                label: user.isActive ? 'Activo' : 'Inactivo',
                                background: user.isActive
                                    ? const Color(0xFFE7F5EF)
                                    : const Color(0xFFFCEEDF),
                                foreground: user.isActive
                                    ? const Color(0xFF2F6F5C)
                                    : const Color(0xFF9A6408),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  : DesktopTableCard(
                  title: 'Usuarios registrados',
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
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 320),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: user.roles
                                        .map(
                                          (role) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F4FA),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(role.name),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: user.isActive
                                        ? const Color(0xFFE7F5EF)
                                        : const Color(0xFFFCEEDF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    user.isActive ? 'Activo' : 'Inactivo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: user.isActive
                                          ? const Color(0xFF2F6F5C)
                                          : const Color(0xFF9A6408),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          )
                          .toList(),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
