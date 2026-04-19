import 'package:flutter/material.dart';
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

        return DesktopPageScaffold(
          title: 'Configuracion',
          subtitle: 'Resumen operativo del panel y estado actual de acceso.',
          child: ListView(
            children: [
              _SettingsHero(
                initialized: data.initialized,
                currentUser: auth.user?.fullName ?? '-',
                currentRole: auth.user?.panelRole == PanelRole.admin
                    ? 'Administrador'
                    : 'Consulta',
                isRealtimeConnected: realtime.isConnected,
              ),
              const SizedBox(height: 16),
              DesktopMetricStrip(
                children: [
                  DesktopMetricCard(
                    title: 'Roles registrados',
                    value: '${data.roles.length}',
                    color: const Color(0xFF223048),
                  ),
                  DesktopMetricCard(
                    title: 'Permisos vigentes',
                    value: '${data.permissions.length}',
                    color: const Color(0xFF2F6F5C),
                  ),
                  DesktopMetricCard(
                    title: 'Panel listo',
                    value: data.initialized ? 'Si' : 'No',
                    color: const Color(0xFFC78442),
                  ),
                  DesktopMetricCard(
                    title: 'Realtime',
                    value: realtime.isConnected ? 'En linea' : 'Sin conexion',
                    color: realtime.isConnected
                        ? const Color(0xFF59728D)
                        : const Color(0xFFB05233),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 960;
                  final sessionCard = _SettingsCard(
                    title: 'Sesion actual',
                    icon: Icons.verified_user_outlined,
                    accentColor: const Color(0xFF173450),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _InfoTile(
                          title: 'Nombre',
                          value: auth.user?.fullName ?? '-',
                        ),
                        _InfoTile(
                          title: 'Correo',
                          value: auth.user?.email ?? '-',
                        ),
                        _InfoTile(
                          title: 'Usuario',
                          value: auth.user?.username ?? '-',
                        ),
                        _InfoTile(
                          title: 'Conexion realtime',
                          value: realtime.isConnected
                              ? 'En linea'
                              : 'Sin conexion',
                        ),
                      ],
                    ),
                  );
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
                        Expanded(child: sessionCard),
                        const SizedBox(width: 16),
                        Expanded(child: rolesCard),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      sessionCard,
                      const SizedBox(height: 16),
                      rolesCard,
                    ],
                  );
                },
              ),
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
                                  color: const Color(0xFFF6EFE3),
                                  borderRadius: BorderRadius.circular(999),
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
    required this.isRealtimeConnected,
  });

  final bool initialized;
  final String currentUser;
  final String currentRole;
  final bool isRealtimeConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2844), Color(0xFF071829)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado general del panel',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Resumen rapido del acceso, la inicializacion y la conectividad del entorno actual.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.74),
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroTag(label: initialized ? 'Panel listo' : 'Pendiente'),
                _HeroTag(label: currentRole),
                _HeroTag(
                  label: isRealtimeConnected
                      ? 'Realtime activo'
                      : 'Realtime desconectado',
                ),
                _HeroTag(label: currentUser),
              ],
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
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
      radius: 20,
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
