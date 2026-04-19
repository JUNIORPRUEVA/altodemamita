import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/settings/settings_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<SettingsOverview>? _future;
  int _lastTick = -1;

  void _reload() {
    setState(() => _future = null);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = SettingsService(context.read<ApiClient>()).fetchOverview();
    }

    return FutureBuilder<SettingsOverview>(
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
        final auth = context.watch<AuthController>();
        final realtime = context.watch<RealtimeController>();
        final canManageUsers = auth.canManageUsers;
        final currentRole = auth.user?.panelRole == PanelRole.admin
            ? 'Administrador'
            : 'Consulta';

        final accountCard = _SettingsCard(
          title: 'Usuario y sesion',
          icon: Icons.verified_user_outlined,
          accentColor: const Color(0xFF173450),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _InfoTile(title: 'Nombre', value: auth.user?.fullName ?? '-'),
                  _InfoTile(title: 'Correo', value: auth.user?.email ?? '-'),
                  _InfoTile(
                    title: 'Usuario',
                    value: auth.user?.username ?? '-',
                  ),
                  _InfoTile(title: 'Perfil', value: currentRole),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE6EBF3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: realtime.isConnected
                            ? const Color(0xFFEAF8F0)
                            : const Color(0xFFF3F5F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        realtime.isConnected
                            ? Icons.wifi_tethering_rounded
                            : Icons.wifi_off_rounded,
                        size: 18,
                        color: realtime.isConnected
                            ? const Color(0xFF2BB673)
                            : const Color(0xFF6B7682),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estado de la sesion',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF12263D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            realtime.isConnected
                                ? 'La conexion en tiempo real esta activa y el panel esta recibiendo actualizaciones.'
                                : 'La sesion sigue disponible, pero ahora mismo no hay conexion realtime con el backend.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Color(0xFF687487),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        final controlCard = _SettingsCard(
          title: 'Control del panel',
          icon: Icons.tune_rounded,
          accentColor: const Color(0xFF2F6F5C),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SettingsMetricTile(
                    label: 'Panel',
                    value: data.initialized ? 'Listo' : 'Pendiente',
                  ),
                  _SettingsMetricTile(
                    label: 'Roles',
                    value: '${data.roles.length}',
                  ),
                  _SettingsMetricTile(
                    label: 'Permisos',
                    value: '${data.permissions.length}',
                  ),
                  _SettingsMetricTile(
                    label: 'Realtime',
                    value: realtime.isConnected ? 'Activo' : 'Sin conexion',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Configuracion concentra el estado del panel, el acceso actual y la administracion de usuarios en una sola vista.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Color(0xFF687487),
                ),
              ),
            ],
          ),
        );

        final usersCard = _SettingsCard(
          title: 'Usuarios y permisos',
          icon: Icons.manage_accounts_outlined,
          accentColor: const Color(0xFFC78442),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'La gestion de usuarios ahora vive dentro del espacio de Configuracion. Desde aqui centralizas accesos, roles y visibilidad operativa del panel.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Color(0xFF687487),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: data.roles
                    .take(6)
                    .map(
                      (role) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6EFE3),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE8E0D1)),
                        ),
                        child: Text(
                          role.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6E4B21),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (canManageUsers)
                    FilledButton.icon(
                      onPressed: () => context.go('/users'),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Abrir gestion de usuarios'),
                    )
                  else
                    const Expanded(
                      child: Text(
                        'La gestion detallada de usuarios esta disponible para perfiles administrativos.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Color(0xFF687487),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

        return DesktopPageScaffold(
          title: 'Configuracion',
          subtitle:
              'Accesos, sesion y ajustes del panel organizados en un solo lugar.',
          child: ListView(
            children: [
              _SettingsHero(
                initialized: data.initialized,
                currentUser: auth.user?.fullName ?? '-',
                currentRole: currentRole,
                currentEmail: auth.user?.email ?? '-',
                isRealtimeConnected: realtime.isConnected,
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 960;
                  final rolesCard = _SettingsCard(
                    title: 'Roles disponibles',
                    icon: Icons.badge_outlined,
                    accentColor: const Color(0xFF8C5A2C),
                    child: data.roles.isEmpty
                        ? const DesktopEmptyState(
                            icon: Icons.badge_outlined,
                            title: 'No hay roles configurados',
                            message:
                                'El backend no devolvio roles para esta instalacion.',
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: data.roles
                                .map(
                                  (role) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F4FA),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFFE4EAF2),
                                      ),
                                    ),
                                    child: Text('${role.name} (${role.code})'),
                                  ),
                                )
                                .toList(),
                          ),
                  );

                  if (twoColumns) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              accountCard,
                              const SizedBox(height: 16),
                              _SettingsCard(
                                title: 'Permisos vigentes',
                                icon: Icons.lock_open_outlined,
                                accentColor: const Color(0xFF2F6F5C),
                                child: data.permissions.isEmpty
                                    ? const DesktopEmptyState(
                                        icon: Icons.verified_user_outlined,
                                        title: 'No hay permisos vigentes',
                                        message:
                                            'No se encontraron permisos asignados para la configuracion actual.',
                                      )
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: data.permissions
                                            .map(
                                              (permission) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF1F5FA,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFE4EAF2,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(permission),
                                              ),
                                            )
                                            .toList(),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              controlCard,
                              const SizedBox(height: 16),
                              usersCard,
                              const SizedBox(height: 16),
                              rolesCard,
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      accountCard,
                      const SizedBox(height: 16),
                      controlCard,
                      const SizedBox(height: 16),
                      usersCard,
                      const SizedBox(height: 16),
                      rolesCard,
                      const SizedBox(height: 16),
                      _SettingsCard(
                        title: 'Permisos vigentes',
                        icon: Icons.lock_open_outlined,
                        accentColor: const Color(0xFF2F6F5C),
                        child: data.permissions.isEmpty
                            ? const DesktopEmptyState(
                                icon: Icons.verified_user_outlined,
                                title: 'No hay permisos vigentes',
                                message:
                                    'No se encontraron permisos asignados para la configuracion actual.',
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: data.permissions
                                    .map(
                                      (permission) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5FA),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE4EAF2),
                                          ),
                                        ),
                                        child: Text(permission),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({
    required this.initialized,
    required this.currentUser,
    required this.currentRole,
    required this.currentEmail,
    required this.isRealtimeConnected,
  });

  final bool initialized;
  final String currentUser;
  final String currentRole;
  final String currentEmail;
  final bool isRealtimeConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102B47), Color(0xFF1A4868), Color(0xFF295A47)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x214F7EA5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1210263D),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 780;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configuracion del panel',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Una vista ordenada para revisar sesion, accesos y administracion del entorno sin sobrecargar la interfaz.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  height: 1.45,
                                  fontSize: 12.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _HeroTag(
                            label: initialized ? 'Panel listo' : 'Pendiente',
                          ),
                          _HeroTag(label: currentRole),
                          _HeroTag(
                            label: isRealtimeConnected
                                ? 'Realtime activo'
                                : 'Realtime desconectado',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _HeroIdentityCard(
                        currentUser: currentUser,
                        currentEmail: currentEmail,
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _HeroTag(
                              label: initialized ? 'Panel listo' : 'Pendiente',
                            ),
                            _HeroTag(label: currentRole),
                            _HeroTag(
                              label: isRealtimeConnected
                                  ? 'Realtime activo'
                                  : 'Realtime desconectado',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 280,
                        child: _HeroIdentityCard(
                          currentUser: currentUser,
                          currentEmail: currentEmail,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      radius: 24,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DesktopStackedStat(label: title, value: value);
  }
}

class _HeroIdentityCard extends StatelessWidget {
  const _HeroIdentityCard({
    required this.currentUser,
    required this.currentEmail,
  });

  final String currentUser;
  final String currentEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentUser,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  currentEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMetricTile extends StatelessWidget {
  const _SettingsMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7682),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF12263D),
            ),
          ),
        ],
      ),
    );
  }
}
