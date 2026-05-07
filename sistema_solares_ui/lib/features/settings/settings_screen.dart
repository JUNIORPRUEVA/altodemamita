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
  late final SettingsService _settingsService;
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  Future<SettingsOverview>? _future;
  int _lastTick = -1;
  bool _isActivatingDevice = false;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService(context.read<ApiClient>());
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = null);
  }

  Future<void> _activateDevice() async {
    if (_isActivatingDevice) {
      return;
    }

    final normalizedId = _deviceIdController.text.trim();
    if (normalizedId.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Pega el ID de la PC que deseas autorizar.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activar nueva PC'),
        content: const Text(
          'Esta accion revocara automaticamente la PC activa anterior y dejara solo este ID autorizado para escritura.\n\n¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activar esta PC'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isActivatingDevice = true;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _settingsService.activateDeviceById(
        deviceId: normalizedId,
        deviceName: _deviceNameController.text,
      );
      if (!mounted) {
        return;
      }
      _deviceIdController.clear();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'PC autorizada correctamente. En la app desktop presiona "Actualizar estado" para activar la sincronizacion.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error is ApiException && error.statusCode != null
          ? '(${error.statusCode}) $error'
          : '$error';
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo activar el dispositivo: $detail')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isActivatingDevice = false;
        });
      }
    }
  }

  Future<void> _openMobileSection({
    required String title,
    required Widget child,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _SettingsSectionPage(title: title, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = _settingsService.fetchOverview();
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
        final compact = MediaQuery.sizeOf(context).width < 760;
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

        AuthorizedDeviceRecord? activeDevice;
        for (final device in data.devices) {
          if (device.isActive) {
            activeDevice = device;
            break;
          }
        }

        final deviceControlCard = _SettingsCard(
          title: 'PC autorizada para sincronizacion',
          icon: Icons.computer_rounded,
          accentColor: const Color(0xFF6E4B21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (activeDevice != null) ...[
                _InfoTile(
                  title: 'PC activa',
                  value: activeDevice.deviceName?.trim().isNotEmpty == true
                      ? activeDevice.deviceName!
                      : 'Sin nombre',
                ),
                const SizedBox(height: 4),
                SelectableText(
                  activeDevice.deviceId,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF415365),
                  ),
                ),
              ] else
                const _InfoTile(title: 'PC activa', value: 'Ninguna'),
              const SizedBox(height: 12),
              TextField(
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: 'Pegar ID de la nueva PC',
                  hintText: 'Ej: 8f7c... (32 caracteres hex)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de PC (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isActivatingDevice ? null : _activateDevice,
                icon: _isActivatingDevice
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_rounded),
                label: Text(
                  _isActivatingDevice ? 'Activando...' : 'Activar esta PC',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '1. En la app desktop, ve a Configuracion y copia el ID.\n'
                '2. Pegalo arriba y presiona "Activar esta PC".\n'
                '3. Vuelve a la app desktop y presiona "Actualizar estado".',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Color(0xFF687487),
                ),
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
                            border: Border.all(color: const Color(0xFFE4EAF2)),
                          ),
                          child: Text('${role.name} (${role.code})'),
                        ),
                      )
                      .toList(),
                ),
        );

        final permissionsCard = _SettingsCard(
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
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFE4EAF2)),
                          ),
                          child: Text(permission),
                        ),
                      )
                      .toList(),
                ),
        );

        if (compact) {
          return DesktopPageScaffold(
            title: 'Configuracion',
            showMobileTitle: false,
            child: ListView(
              children: [
                _MobileSettingsGroupLabel(label: 'Sesion y panel'),
                _MobileSettingsNavTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Cuenta y sesion',
                  subtitle: auth.user?.fullName ?? '-',
                  trailingLabel: currentRole,
                  onTap: () => _openMobileSection(
                    title: 'Cuenta y sesion',
                    child: _MobileSettingsDetailSection(
                      children: [
                        _MobileSettingsFactRow(
                          label: 'Nombre',
                          value: auth.user?.fullName ?? '-',
                        ),
                        _MobileSettingsFactRow(
                          label: 'Correo',
                          value: auth.user?.email ?? '-',
                        ),
                        _MobileSettingsFactRow(
                          label: 'Usuario',
                          value: auth.user?.username ?? '-',
                        ),
                        _MobileSettingsFactRow(
                          label: 'Perfil',
                          value: currentRole,
                        ),
                        _MobileSettingsFactRow(
                          label: 'Conexion realtime',
                          value: realtime.isConnected
                              ? 'Activa'
                              : 'Sin conexion',
                          highlight: realtime.isConnected,
                        ),
                      ],
                    ),
                  ),
                ),
                _MobileSettingsNavTile(
                  icon: Icons.tune_rounded,
                  title: 'Estado del panel',
                  subtitle: data.initialized
                      ? 'Panel listo para operar'
                      : 'Panel pendiente',
                  trailingLabel: realtime.isConnected ? 'Activo' : 'Offline',
                  onTap: () => _openMobileSection(
                    title: 'Estado del panel',
                    child: _MobileSettingsDetailSection(
                      children: [
                        _MobileSettingsFactRow(
                          label: 'Panel',
                          value: data.initialized ? 'Listo' : 'Pendiente',
                        ),
                        _MobileSettingsFactRow(
                          label: 'Roles disponibles',
                          value: '${data.roles.length}',
                        ),
                        _MobileSettingsFactRow(
                          label: 'Permisos cargados',
                          value: '${data.permissions.length}',
                        ),
                        _MobileSettingsFactRow(
                          label: 'Realtime',
                          value: realtime.isConnected
                              ? 'Activo'
                              : 'Sin conexion',
                          highlight: realtime.isConnected,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _MobileSettingsGroupLabel(label: 'Accesos'),
                _MobileSettingsNavTile(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Usuarios y permisos',
                  subtitle: canManageUsers
                      ? 'Gestion y acceso administrativo'
                      : 'Vista de solo consulta',
                  trailingLabel: canManageUsers ? 'Abrir' : 'Lectura',
                  onTap: () => _openMobileSection(
                    title: 'Usuarios y permisos',
                    child: _MobileSettingsDetailSection(
                      children: [
                        _MobileSettingsFactRow(
                          label: 'Acceso a usuarios',
                          value: canManageUsers
                              ? 'Disponible para este perfil'
                              : 'Solo administradores',
                        ),
                        _MobileSettingsInlineWrap(
                          label: 'Roles visibles',
                          children: data.roles
                              .take(6)
                              .map(
                                (role) => _MobileSettingsChip(label: role.name),
                              )
                              .toList(),
                        ),
                        if (canManageUsers)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: FilledButton.icon(
                              onPressed: () => context.go('/users'),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Abrir gestion de usuarios'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _MobileSettingsNavTile(
                  icon: Icons.computer_rounded,
                  title: 'PC autorizada',
                  subtitle: activeDevice == null
                      ? 'No hay PC activa'
                      : (activeDevice.deviceName?.isNotEmpty == true
                            ? activeDevice.deviceName!
                            : activeDevice.deviceId),
                  trailingLabel: 'Gestionar',
                  onTap: () => _openMobileSection(
                    title: 'PC autorizada',
                    child: _MobileSettingsDetailSection(
                      children: [
                        _MobileSettingsFactRow(
                          label: 'PC activa',
                          value: activeDevice == null
                              ? 'Ninguna'
                              : (activeDevice.deviceName?.isNotEmpty == true
                                    ? activeDevice.deviceName!
                                    : activeDevice.deviceId),
                        ),
                        TextField(
                          controller: _deviceIdController,
                          decoration: const InputDecoration(
                            labelText: 'Pegar ID de nueva PC',
                          ),
                        ),
                        TextField(
                          controller: _deviceNameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de PC (opcional)',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _isActivatingDevice
                              ? null
                              : _activateDevice,
                          icon: _isActivatingDevice
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified_rounded),
                          label: Text(
                            _isActivatingDevice
                                ? 'Activando...'
                                : 'Activar esta PC',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _MobileSettingsNavTile(
                  icon: Icons.badge_outlined,
                  title: 'Roles disponibles',
                  subtitle: '${data.roles.length} roles cargados',
                  trailingLabel: 'Ver',
                  onTap: () => _openMobileSection(
                    title: 'Roles disponibles',
                    child: _MobileSettingsDetailSection(
                      children: [
                        if (data.roles.isEmpty)
                          const _MobileSettingsEmptyMessage(
                            message:
                                'No hay roles configurados para esta instalacion.',
                          )
                        else
                          _MobileSettingsInlineWrap(
                            label: 'Listado',
                            children: data.roles
                                .map(
                                  (role) => _MobileSettingsChip(
                                    label: '${role.name} (${role.code})',
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                _MobileSettingsNavTile(
                  icon: Icons.lock_open_outlined,
                  title: 'Permisos vigentes',
                  subtitle: '${data.permissions.length} permisos activos',
                  trailingLabel: 'Ver',
                  onTap: () => _openMobileSection(
                    title: 'Permisos vigentes',
                    child: _MobileSettingsDetailSection(
                      children: [
                        if (data.permissions.isEmpty)
                          const _MobileSettingsEmptyMessage(
                            message:
                                'No se encontraron permisos asignados para la configuracion actual.',
                          )
                        else
                          _MobileSettingsInlineWrap(
                            label: 'Permisos',
                            children: data.permissions
                                .map(
                                  (permission) =>
                                      _MobileSettingsChip(label: permission),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

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

                  if (twoColumns) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              accountCard,
                              const SizedBox(height: 16),
                              permissionsCard,
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
                              deviceControlCard,
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
                      deviceControlCard,
                      const SizedBox(height: 16),
                      rolesCard,
                      const SizedBox(height: 16),
                      permissionsCard,
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

class _SettingsSectionPage extends StatelessWidget {
  const _SettingsSectionPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF173450),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
          children: [child],
        ),
      ),
    );
  }
}

class _MobileSettingsGroupLabel extends StatelessWidget {
  const _MobileSettingsGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Color(0xFF6E7A8E),
        ),
      ),
    );
  }
}

class _MobileSettingsNavTile extends StatelessWidget {
  const _MobileSettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF173450)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF12263D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Color(0xFF6E7A8E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailingLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8C5A2C),
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Color(0xFF9AA6B8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSettingsDetailSection extends StatelessWidget {
  const _MobileSettingsDetailSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
        ],
      ],
    );
  }
}

class _MobileSettingsFactRow extends StatelessWidget {
  const _MobileSettingsFactRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7B8798),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.4,
              color: highlight
                  ? const Color(0xFF2F6F5C)
                  : const Color(0xFF12263D),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileSettingsInlineWrap extends StatelessWidget {
  const _MobileSettingsInlineWrap({
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF7B8798),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}

class _MobileSettingsChip extends StatelessWidget {
  const _MobileSettingsChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF173450),
        ),
      ),
    );
  }
}

class _MobileSettingsEmptyMessage extends StatelessWidget {
  const _MobileSettingsEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(
        fontSize: 12.5,
        height: 1.45,
        color: Color(0xFF6E7A8E),
      ),
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
