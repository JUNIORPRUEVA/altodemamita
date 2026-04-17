import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/config/app_config.dart';
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
          subtitle: 'Estado general, roles y permisos del sistema.',
          child: ListView(
            children: [
              DesktopInfoStrip(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado general del sistema',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _InfoTile(
                          title: 'Sistema inicializado',
                          value: data.initialized ? 'Si' : 'No',
                        ),
                        _InfoTile(
                          title: 'API base',
                          value: AppConfig.apiBaseUrl,
                        ),
                        _InfoTile(
                          title: 'Realtime',
                          value: realtime.isConnected ? 'Conectado' : 'Desconectado',
                        ),
                        _InfoTile(
                          title: 'Usuario actual',
                          value: auth.user?.fullName ?? '-',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DesktopPlainSection(
                title: 'Roles disponibles',
                child: data.roles.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.badge_outlined,
                        title: 'No hay roles configurados',
                        message: 'El backend no devolvio roles para esta instalacion.',
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: data.roles
                            .map(
                              (role) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F4FA),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('${role.name} (${role.code})'),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),
                          DesktopPlainSection(
                title: 'Permisos vigentes',
                child: data.permissions.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.verified_user_outlined,
                        title: 'No hay permisos vigentes',
                        message: 'No se encontraron permisos asignados para la configuracion actual.',
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: data.permissions
                            .map(
                              (permission) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6EFE3),
                                  borderRadius: BorderRadius.circular(999),
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

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DesktopStackedStat(
      label: title,
      value: value,
    );
  }
}