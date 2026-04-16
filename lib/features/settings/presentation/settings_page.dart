import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/utils/debug_test_data_service.dart';
import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../backup/data/backup_config_repository.dart';
import '../../backup/presentation/backup_controller.dart';
import '../../backup/presentation/backup_page.dart' as backup_feature;
import '../../backup/services/backup_service.dart';
import '../../backup/services/disk_detection_service.dart';
import '../data/settings_repository.dart';
import 'company_info_page.dart';
import 'documentation_page.dart';
import 'financial_params_page.dart';
import 'printers_page.dart';
import 'users_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.onCompanyInfoChanged});

  final VoidCallback? onCompanyInfoChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final DiskDetectionService _diskDetectionService;
  late final BackupService _backupService;
  late final BackupController _backupController;

  @override
  void initState() {
    super.initState();
    _diskDetectionService = DiskDetectionService();
    _backupService = BackupService(
      appDatabase: AppDatabase.instance,
      configRepository: BackupConfigRepository(),
      diskDetectionService: _diskDetectionService,
    );
    _backupController = BackupController(
      backupService: _backupService,
      diskDetectionService: _diskDetectionService,
    )..initialize(silent: true);
  }

  @override
  void dispose() {
    _backupController.dispose();
    super.dispose();
  }

  bool _hasSettingsAccess(AuthProvider auth, String scope) {
    return auth.hasScopedAccess(
      scope: scope,
      module: PermissionCatalog.settings,
      action: PermissionAction.update,
    );
  }

  Future<bool> _ensureSettingsAccess({
    required String scope,
    required String title,
    required String message,
  }) async {
    final auth = context.read<AuthProvider>();
    if (_hasSettingsAccess(auth, scope)) {
      return true;
    }

    return requestAdminOverride(
      context,
      scope: scope,
      title: title,
      message: message,
    );
  }

  Future<void> _openProtectedSettingsPage({
    required String scope,
    required String title,
    required String message,
    required WidgetBuilder builder,
    Future<void> Function()? onClosed,
  }) async {
    final isReadOnly = context.read<SystemConfigService>().isReadOnly;
    if (!isReadOnly) {
      final allowed = await _ensureSettingsAccess(
        scope: scope,
        title: title,
        message: message,
      );
      if (!allowed || !mounted) {
        return;
      }
    }

    await Navigator.of(context).push(MaterialPageRoute(builder: builder));

    if (!mounted || onClosed == null) {
      return;
    }

    await onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canOpenSettingsTools = auth.canReadModule(PermissionCatalog.settings);

    return BaseLayout(
      title: 'Configuración',
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final cardWidth = compact ? constraints.maxWidth : 220.0;

                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _SettingCard(
                      width: cardWidth,
                      icon: Icons.business,
                      title: 'Empresa',
                      description: 'Información y logo',
                      onTap: () => _openProtectedSettingsPage(
                        scope: AdminOverrideScope.settingsCompany,
                        title: 'Autorización administrativa requerida',
                        message:
                            'Necesitas la clave de un administrador para abrir o modificar la información de la empresa.',
                        builder: (_) => const CompanyInfoPage(),
                        onClosed: () async {
                          widget.onCompanyInfoChanged?.call();
                        },
                      ),
                    ),
                    _SettingCard(
                      width: cardWidth,
                      icon: Icons.print,
                      title: 'Impresoras',
                      description: 'Configurar impresoras',
                      onTap: () => _openProtectedSettingsPage(
                        scope: AdminOverrideScope.settingsPrinters,
                        title: 'Autorización administrativa requerida',
                        message:
                            'Necesitas la clave de un administrador para administrar impresoras.',
                        builder: (_) => const PrintersPage(),
                      ),
                    ),
                    if (auth.isAdmin && canOpenSettingsTools)
                      _SettingCard(
                        width: cardWidth,
                        icon: Icons.people,
                        title: 'Usuarios',
                        description: 'Usuarios y permisos',
                        onTap: () => _openProtectedSettingsPage(
                          scope: AdminOverrideScope.settingsUsers,
                          title: 'Autorización administrativa requerida',
                          message:
                              'Necesitas la clave de un administrador para gestionar usuarios y permisos.',
                          builder: (_) => const UsersScreen(),
                        ),
                      ),
                    _SettingCard(
                      width: cardWidth,
                      icon: Icons.trending_up,
                      title: 'Financiero',
                      description: 'Parámetros y valores',
                      onTap: () => _openProtectedSettingsPage(
                        scope: AdminOverrideScope.settingsFinancial,
                        title: 'Autorización administrativa requerida',
                        message:
                            'Necesitas la clave de un administrador para abrir o modificar los parámetros financieros.',
                        builder: (_) => const FinancialParamsPage(),
                      ),
                    ),
                    _SettingCard(
                      width: cardWidth,
                      icon: Icons.menu_book_rounded,
                      title: 'Documentacion',
                      description: 'Manual y guia del sistema',
                      onTap: () async {
                        if (!mounted) {
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DocumentationPage(),
                          ),
                        );
                      },
                    ),
                    _BackupSettingCard(
                      width: compact ? constraints.maxWidth : 456,
                      controller: _backupController,
                      onTap: () => _openProtectedSettingsPage(
                        scope: AdminOverrideScope.settingsBackup,
                        title: 'Autorización administrativa requerida',
                        message:
                            'Necesitas la clave de un administrador para crear, restaurar o modificar respaldos.',
                        builder: (_) => backup_feature.BackupPage(
                          controller: _backupController,
                          backupService: _backupService,
                          diskDetectionService: _diskDetectionService,
                        ),
                        onClosed: () async {
                          if (!mounted) {
                            return;
                          }
                          await _backupController.initialize(
                            silent: true,
                            forceRefresh: true,
                          );
                        },
                      ),
                    ),
                    if (kDebugMode && canOpenSettingsTools)
                      _SettingCard(
                        width: cardWidth,
                        icon: Icons.bug_report,
                        title: 'Debug',
                        description: 'Datos de prueba',
                        onTap: () => _openProtectedSettingsPage(
                          scope: AdminOverrideScope.settingsDebug,
                          title: 'Autorización administrativa requerida',
                          message:
                              'Necesitas la clave de un administrador para usar las herramientas de datos de prueba.',
                          builder: (_) => const DebugSettingsPage(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          onTap: () {
            unawaited(onTap());
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7494),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupSettingCard extends StatelessWidget {
  const _BackupSettingCard({
    required this.width,
    required this.controller,
    required this.onTap,
  });

  final double width;
  final BackupController controller;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          onTap: () {
            unawaited(onTap());
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final config = controller.config;
                final lastBackup = controller.backupHistory.isNotEmpty
                    ? controller.backupHistory.first
                    : null;
                final systemReady = controller.isBackupSystemHealthy;
                final usesExternalPath = controller.isUsingExternalBackupPath;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.backup,
                            size: 24,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Respaldo',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Estado, ruta activa y últimas copias',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6B7494),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: Color(0xFF98A3B8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (controller.isLoading)
                      const LinearProgressIndicator(minHeight: 3)
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _BackupInfoPill(
                            icon: systemReady
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            label: systemReady
                                ? 'Destino externo listo'
                                : 'Revisar respaldo',
                            background: systemReady
                                ? const Color(0xFFEAF8F0)
                                : const Color(0xFFFFF4E5),
                            foreground: systemReady
                                ? const Color(0xFF1A7F45)
                                : const Color(0xFFB35600),
                          ),
                          _BackupInfoPill(
                            icon: config?.autoBackupEnabled == true
                                ? Icons.sync
                                : Icons.sync_disabled,
                            label: config?.autoBackupEnabled == true
                                ? 'Auto respaldo activo'
                                : 'Auto respaldo apagado',
                            background: const Color(0xFFF1F5FB),
                            foreground: const Color(0xFF365B8C),
                          ),
                          _BackupInfoPill(
                            icon: Icons.history,
                            label: lastBackup == null
                                ? 'Sin historial'
                                : lastBackup.localized,
                            background: const Color(0xFFF6F7FA),
                            foreground: const Color(0xFF556079),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _BackupSummaryLine(
                        label: 'Ruta activa',
                        value: config == null
                            ? 'Cargando configuración...'
                            : usesExternalPath
                            ? config.backupPath
                            : '${config.backupPath} · ruta no permitida en disco del sistema',
                        mono: true,
                      ),
                      _BackupSummaryLine(
                        label: 'Último respaldo',
                        value: lastBackup == null
                            ? 'Todavía no hay copias registradas'
                            : '${lastBackup.formattedDate} · ${lastBackup.formattedSize}',
                      ),
                      _BackupSummaryLine(
                        label: 'Destino sugerido',
                        value: controller.secondaryDrive == null
                            ? 'No se detectó una unidad secundaria'
                            : '${controller.secondaryDrive!.drive} · ${controller.secondaryDrive!.label} · Libre ${controller.secondaryDrive!.formattedFree}',
                      ),
                      if (controller.errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF3C3BF)),
                          ),
                          child: Text(
                            controller.errorMessage!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF9F2D26),
                            ),
                          ),
                        ),
                      ] else if (controller.statusMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F7FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD4E4FA)),
                          ),
                          child: Text(
                            controller.statusMessage!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF2B4F7D),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupInfoPill extends StatelessWidget {
  const _BackupInfoPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupSummaryLine extends StatelessWidget {
  const _BackupSummaryLine({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8893AA),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: const Color(0xFF1A2235),
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class DebugSettingsPage extends StatefulWidget {
  const DebugSettingsPage({super.key});

  @override
  State<DebugSettingsPage> createState() => _DebugSettingsPageState();
}

class _DebugSettingsPageState extends State<DebugSettingsPage> {
  late Future<bool> _testDataEnabledFuture;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _testDataEnabledFuture = _getTestDataEnabled();
  }

  Future<bool> _getTestDataEnabled() async {
    final settingsRepo = SettingsRepository();
    final settings = await settingsRepo.fetchByKeysWithDefaults({
      'debug_test_data_enabled': '0',
    });
    return settings['debug_test_data_enabled']?.value == '1';
  }

  bool _canManageDebug(AuthProvider auth) {
    return auth.hasScopedAccess(
      scope: AdminOverrideScope.settingsDebug,
      module: PermissionCatalog.settings,
      action: PermissionAction.update,
    );
  }

  Future<bool> _ensureAuthorized() async {
    final auth = context.read<AuthProvider>();
    if (_canManageDebug(auth)) {
      return true;
    }

    return requestAdminOverride(
      context,
      scope: AdminOverrideScope.settingsDebug,
      title: 'Autorización administrativa requerida',
      message:
          'Necesitas la clave de un administrador para generar o eliminar datos de prueba.',
    );
  }

  Future<void> _toggleTestData(bool enable) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final db = await AppDatabase.instance.database;
      if (enable) {
        await DebugTestDataService.seedTestData(db);
      } else {
        await DebugTestDataService.clearTestData(db);
      }

      final settingsRepo = SettingsRepository();
      await settingsRepo.upsert('debug_test_data_enabled', enable ? '1' : '0');

      if (!mounted) {
        return;
      }

      setState(() {
        _testDataEnabledFuture = _getTestDataEnabled();
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable
                ? 'Datos de prueba generados correctamente'
                : 'Datos de prueba eliminados',
          ),
          backgroundColor: enable ? Colors.green : Colors.orange,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración Debug'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: Colors.amber[50],
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.amber[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta sección solo está visible en modo debug',
                      style: TextStyle(
                        color: Colors.amber[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Datos de Prueba',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Genera automáticamente 10 clientes, 10 vendedores, 10 solares, 10 ventas y 10 pagos para pruebas.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      FutureBuilder<bool>(
                        future: _testDataEnabledFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          }

                          final enabled = snapshot.data ?? false;

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    enabled
                                        ? 'Datos activos'
                                        : 'Datos inactivos',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    enabled
                                        ? 'Los datos de prueba están visibles'
                                        : 'No hay datos de prueba',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: enabled,
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        _toggleTestData(value);
                                      },
                              ),
                            ],
                          );
                        },
                      ),
                      if (_isLoading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Datos que serán generados',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const _DataInfoTile(
                        icon: Icons.person,
                        label: '10 Clientes',
                        description:
                            'Con nombres dominicanos, cédulas válidas y números de teléfono',
                      ),
                      const _DataInfoTile(
                        icon: Icons.people,
                        label: '10 Vendedores',
                        description: 'Con nombres diversos y datos de contacto',
                      ),
                      const _DataInfoTile(
                        icon: Icons.location_city,
                        label: '10 Solares',
                        description: 'Con precios entre RD\$500k - RD\$1.5M',
                      ),
                      const _DataInfoTile(
                        icon: Icons.receipt_long,
                        label: '10 Ventas',
                        description:
                            'Con diferentes: 5% - 20% inicial, 0.5% - 1.5% interés mensual, 12 - 48 cuotas',
                      ),
                      const _DataInfoTile(
                        icon: Icons.payment,
                        label: '10 Pagos',
                        description:
                            'Con diferentes métodos (efectivo, cheque, transferencia)',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataInfoTile extends StatelessWidget {
  const _DataInfoTile({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
