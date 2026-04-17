import 'package:flutter/material.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
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
        final auth = context.watch<AuthController>();
        final realtime = context.watch<RealtimeController>();
        final currentUser = auth.user;
        final activeCount = data.users.where((user) => user.isActive).length;
        final onlineCount = data.users.where((user) => user.isOnline).length;
        final adminCount = data.users
            .where((user) => user.roles.any((role) => _looksAdministrativeRole(role.code)))
            .length;
        final currentSessionUser = currentUser == null
            ? null
            : data.users.where((user) => user.id == currentUser.id).firstOrNull;

        return DesktopPageScaffold(
          title: 'Usuarios',
          subtitle: 'Accesos, roles, estado y detalle operativo de usuarios.',
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
          child: ListView(
            children: [
              DesktopInfoStrip(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resumen de accesos',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Vista ordenada para revisar usuarios registrados, su nivel de acceso y el estado de la sesion actual conectada al panel.',
                      style: TextStyle(color: Color(0xFF657089), height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _SummaryTile(
                          title: 'Usuarios visibles',
                          value: '${data.users.length}',
                          color: const Color(0xFF173450),
                        ),
                        _SummaryTile(
                          title: 'Usuarios activos',
                          value: '$activeCount',
                          color: const Color(0xFF2F6F5C),
                        ),
                        _SummaryTile(
                          title: 'Perfiles admin',
                          value: '$adminCount',
                          color: const Color(0xFFC07A2B),
                        ),
                        _SummaryTile(
                          title: 'Usuarios en linea',
                          value: '$onlineCount',
                          color: onlineCount > 0
                              ? const Color(0xFF2BB673)
                              : const Color(0xFF6B7682),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (currentSessionUser != null) ...[
                _CurrentSessionCard(
                  user: currentSessionUser,
                  realtime: realtime,
                  onViewDetails: () => _openUserDetails(context, currentSessionUser, true, realtime),
                ),
                const SizedBox(height: 16),
              ],
              if (data.users.isEmpty)
                const DesktopEmptyState(
                  icon: Icons.manage_accounts_outlined,
                  title: 'No hay usuarios visibles',
                  message: 'Prueba otro filtro o verifica que el backend este devolviendo el listado esperado.',
                )
              else if (compact)
                DesktopDataListSection(
                  title: 'Usuarios registrados',
                  children: data.users.map((user) {
                    final isCurrentUser = currentUser?.id == user.id;
                    return DesktopListRow(
                      height: 108,
                      leading: _UserAvatar(label: _initialFor(user.fullName)),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.fullName,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (user.isOnline)
                            _PresenceBadge(
                              label: _presenceLabel(user, isCurrentUser),
                              color: const Color(0xFF2BB673),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${user.username}  •  ${user.email}',
                        style: const TextStyle(color: Color(0xFF6E7791)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StatusBadge(isActive: user.isActive),
                          if (user.roles.isNotEmpty)
                            DesktopTag(
                              label: user.roles.first.name,
                              background: const Color(0xFFF1F4FA),
                            ),
                          OutlinedButton(
                            onPressed: () => _openUserDetails(context, user, isCurrentUser, realtime),
                            child: const Text('Ver detalle'),
                          ),
                        ],
                      ),
                      onTap: () => _openUserDetails(context, user, isCurrentUser, realtime),
                    );
                  }).toList(),
                )
              else
                DesktopTableCard(
                  title: 'Usuarios registrados',
                  trailing: Text(
                    'Selecciona un usuario para ver detalle',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Usuario')),
                        DataColumn(label: Text('Acceso principal')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Sesion')),
                        DataColumn(label: Text('Detalle')),
                      ],
                      rows: data.users.map((user) {
                        final isCurrentUser = currentUser?.id == user.id;
                        return DataRow(
                          onSelectChanged: (_) => _openUserDetails(context, user, isCurrentUser, realtime),
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
                                child: Row(
                                  children: [
                                    _UserAvatar(label: _initialFor(user.fullName), radius: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.fullName,
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${user.username} • ${user.email}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF6E7791),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: user.roles
                                      .map(
                                        (role) => DesktopTag(
                                          label: role.name,
                                          background: const Color(0xFFF1F4FA),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                            DataCell(_StatusBadge(isActive: user.isActive)),
                            DataCell(
                              user.isOnline
                                  ? _PresenceBadge(
                                      label: _presenceLabel(user, isCurrentUser),
                                      color: Color(0xFF2BB673),
                                    )
                                  : Text(
                                      isCurrentUser ? 'Sesion sin conexion' : 'Fuera de linea',
                                      style: const TextStyle(color: Color(0xFF6E7791)),
                                    ),
                            ),
                            DataCell(
                              OutlinedButton(
                                onPressed: () => _openUserDetails(context, user, isCurrentUser, realtime),
                                child: const Text('Ver detalle'),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUserDetails(
    BuildContext context,
    UserRecord user,
    bool isCurrentUser,
    RealtimeController realtime,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _UserAvatar(label: _initialFor(user.fullName), radius: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${user.username}',
                            style: const TextStyle(color: Color(0xFF6E7791)),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatusBadge(isActive: user.isActive),
                              if (user.isOnline)
                                _PresenceBadge(
                                  label: _presenceLabel(user, isCurrentUser),
                                  color: const Color(0xFF2BB673),
                                )
                              else if (isCurrentUser)
                                const _PresenceBadge(
                                  label: 'Sesion actual sin conexion',
                                  color: Color(0xFF6B7682),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _DetailTile(label: 'Correo', value: user.email),
                    _DetailTile(label: 'Usuario', value: user.username),
                    _DetailTile(label: 'ID', value: user.id),
                    _DetailTile(
                      label: 'Presencia',
                      value: user.isOnline
                          ? _presenceLabel(user, isCurrentUser)
                          : (isCurrentUser ? 'Sesion sin conexion' : 'Fuera de linea'),
                    ),
                    _DetailTile(
                      label: 'Conexiones activas',
                      value: '${user.connectionCount}',
                    ),
                    _DetailTile(
                      label: 'Cliente conectado',
                      value: user.clientTypes.isEmpty ? '-' : user.clientTypes.join(', '),
                    ),
                    _DetailTile(
                      label: 'Conectado desde',
                      value: _formatPresenceDate(user.connectedAt),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Roles asignados',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (user.roles.isEmpty)
                  const Text(
                    'Este usuario no tiene roles visibles en la respuesta actual.',
                    style: TextStyle(color: Color(0xFF6E7791)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: user.roles
                        .map(
                          (role) => DesktopTag(
                            label: '${role.name} (${role.code})',
                            background: const Color(0xFFF1F4FA),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFBFC),
                    border: Border.all(color: const Color(0xFFE4EAF2)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isCurrentUser
                        ? 'Esta es la sesion autenticada actualmente en el panel. El indicador de linea depende de la conexion realtime activa del navegador.'
                        : 'La presencia ahora se basa en conexiones realtime activas reportadas por el backend. Si el usuario no tiene sockets activos, se muestra como fuera de linea.',
                    style: const TextStyle(color: Color(0xFF536079), height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _looksAdministrativeRole(String code) {
  final normalized = code.toUpperCase();
  return normalized.contains('ADMIN') || normalized.contains('SUPER');
}

String _initialFor(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'U' : trimmed.characters.first.toUpperCase();
}

String _presenceLabel(UserRecord user, bool isCurrentUser) {
  final clientTypeLabel = user.clientTypes.isEmpty ? 'sesion' : user.clientTypes.join('/');
  if (isCurrentUser) {
    return 'Tu sesion en linea';
  }
  if (user.connectionCount > 1) {
    return 'En linea (${user.connectionCount} conexiones)';
  }
  return 'En linea por $clientTypeLabel';
}

String _formatPresenceDate(DateTime? value) {
  if (value == null) {
    return '-';
  }

  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Color(0xFF6A7684))),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _CurrentSessionCard extends StatelessWidget {
  const _CurrentSessionCard({
    required this.user,
    required this.realtime,
    required this.onViewDetails,
  });

  final UserRecord user;
  final RealtimeController realtime;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Sesion actual conectada',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton(
                onPressed: onViewDetails,
                child: const Text('Ver detalle'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UserAvatar(label: _initialFor(user.fullName), radius: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${user.username} • ${user.email}',
                      style: const TextStyle(color: Color(0xFF6E7791)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusBadge(isActive: user.isActive),
                        _PresenceBadge(
                          label: user.isOnline
                              ? _presenceLabel(user, true)
                              : 'Sin conexion realtime',
                          color: user.isOnline
                              ? const Color(0xFF2BB673)
                              : const Color(0xFF6B7682),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.label, this.radius = 22});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFEFF3FB),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFF223048),
          fontWeight: FontWeight.w800,
          fontSize: radius >= 24 ? 20 : 16,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return DesktopTag(
      label: isActive ? 'Activo' : 'Inactivo',
      background: isActive ? const Color(0xFFE7F5EF) : const Color(0xFFFCEEDF),
      foreground: isActive ? const Color(0xFF2F6F5C) : const Color(0xFF9A6408),
    );
  }
}

class _PresenceBadge extends StatelessWidget {
  const _PresenceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0D2640)),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 320),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF6A7684))),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
