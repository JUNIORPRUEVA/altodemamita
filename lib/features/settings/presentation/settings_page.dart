import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_flags.dart';
import '../../../core/database/app_database.dart';
import '../../../core/system/system_config_service.dart';
import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../models/sync/sync_runtime_state.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/dangerous_action_confirm_dialog.dart';
import '../../../shared/widgets/device_status_panel.dart';
import '../../../services/sync/sync_conflict_service.dart';
import '../../../services/sync/sync_config_repository.dart';
import '../../../services/sync/emergency_cloud_restore_service.dart';
import '../../backup/data/backup_config_repository.dart';
import '../../backup/presentation/backup_controller.dart';
import '../../backup/presentation/backup_page.dart' as backup_feature;
import '../../backup/services/backup_service.dart';
import '../../backup/services/disk_detection_service.dart';
import '../../../services/sync/sync_queue_service.dart';
import 'company_info_page.dart';
import 'documentation_page.dart';
import 'financial_params_page.dart';
import 'printers_page.dart';
import 'users_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.onCompanyInfoChanged,
    this.onRunSyncRecovery,
    this.onRunPostAuthorizationRecovery,
    this.onResetLocalDeviceIdentity,
    this.onResetBusinessData,
    this.onResetLocalOnly,
    this.onPreviewEmergencyCloudRestore,
    this.onRunEmergencyCloudRestore,
  });

  final VoidCallback? onCompanyInfoChanged;
  final Future<String> Function()? onRunSyncRecovery;
  final Future<String> Function()? onRunPostAuthorizationRecovery;
  final Future<String> Function()? onResetLocalDeviceIdentity;
  final Future<String> Function()? onResetBusinessData;
  final Future<String> Function()? onResetLocalOnly;
  final Future<EmergencyRestorePreview> Function()?
  onPreviewEmergencyCloudRestore;
  final Future<EmergencyRestoreResult> Function({
    required String adminPassword,
    required String confirmationText,
  })?
  onRunEmergencyCloudRestore;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final DiskDetectionService _diskDetectionService;
  late final BackupService _backupService;
  late final BackupController _backupController;
  bool _isRunningSyncRecovery = false;
  bool _isRunningEmergencyRestore = false;

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
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DeviceStatusPanel(
                onRefresh: _refreshDeviceStatus,
                onCopyDeviceId: _copyDeviceId,
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _SyncStatusBanner(),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _SyncTechnicalDiagnosticsPanel(),
            ),
            const SizedBox(height: 8),
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
                    _SettingCard(
                      width: cardWidth,
                      icon: Icons.fingerprint_rounded,
                      title: 'Resetear identificacion de PC',
                      description: 'Generar nuevo ID local para esta PC',
                      onTap: _resetLocalDeviceIdentity,
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
                          onResetBusinessData: widget.onResetBusinessData,
                          onResetLocalOnly: widget.onResetLocalOnly,
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
                    if (auth.isAdmin)
                      _SettingCard(
                        width: compact ? constraints.maxWidth : 456,
                        icon: Icons.cloud_download_rounded,
                        title: 'Restauracion de emergencia',
                        description:
                            'Modo rescate nube -> PC (solo admin, con backup)',
                        onTap: _openEmergencyRestoreDialog,
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

  Future<void> _refreshDeviceStatus() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await SystemConfigService.instance.refresh(throwOnFailure: true);
      if (!mounted) return;
      final systemConfig = SystemConfigService.instance;

      final message = systemConfig.canWrite
          ? 'Estado actualizado. Esta PC esta autorizada para sincronizar.'
          : (systemConfig.deviceWriteReason.isEmpty
                ? 'Esta PC aun no esta autorizada. Copia el ID y registralo en el backend cloud nuevo.'
                : '${systemConfig.deviceWriteReason} Copia el ID y registralo en el backend cloud nuevo.');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: systemConfig.canWrite ? 3 : 6),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el estado de esta PC: $error'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _copyDeviceId() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final deviceId = SystemConfigService.instance.currentDeviceId.trim();
    if (deviceId.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('No se encontro el ID de esta PC.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: deviceId));
    if (!mounted) {
      return;
    }
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'ID de esta PC copiado. Registralo en el backend cloud nuevo cuando este disponible.',
        ),
      ),
    );
  }

  Future<void> _resetLocalDeviceIdentity() async {
    if (_isRunningSyncRecovery) {
      return;
    }

    final callback = widget.onResetLocalDeviceIdentity;
    if (callback == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No hay servicio para resetear el ID de esta PC.'),
        ),
      );
      return;
    }

    final allowed = await _ensureSettingsAccess(
      scope: AdminOverrideScope.settingsSync,
      title: 'Autorizacion administrativa requerida',
      message:
          'Necesitas la clave de un administrador para resetear la identificacion local de esta PC.',
    );
    if (!allowed || !mounted) {
      return;
    }

    final confirmed = await DangerousActionConfirmDialog.show(
      context,
      title: 'Resetear identificacion local de esta PC',
      warning:
          'Esta accion genera un nuevo ID local para esta PC y limpia el estado tecnico de sincronizacion (cursores, bloqueos y reintentos).\n\n'
          'No borra ventas, pagos, clientes ni cuotas.\n'
          'Despues debes copiar el nuevo ID y registrarlo en el backend cloud nuevo.',
      confirmLabel: 'Si, resetear ID local',
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isRunningSyncRecovery = true;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final summary = await callback();
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(SnackBar(content: Text(summary)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo resetear la identificacion de esta PC.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningSyncRecovery = false;
        });
      }
    }
  }

  Future<void> _openEmergencyRestoreDialog() async {
    final previewCallback = widget.onPreviewEmergencyCloudRestore;
    final restoreCallback = widget.onRunEmergencyCloudRestore;
    if (previewCallback == null || restoreCallback == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'No hay servicio de restauracion de emergencia disponible.',
          ),
        ),
      );
      return;
    }

    final allowed = await _ensureSettingsAccess(
      scope: AdminOverrideScope.settingsSync,
      title: 'Autorizacion administrativa requerida',
      message:
          'Necesitas la clave de un administrador para usar restauracion de emergencia desde la nube.',
    );
    if (!allowed || !mounted) {
      return;
    }

    if (_isRunningEmergencyRestore) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !_isRunningEmergencyRestore,
      builder: (dialogContext) {
        final passwordController = TextEditingController();
        final confirmationController = TextEditingController();
        EmergencyRestorePreview? preview;
        bool loadingPreview = false;
        bool runningRestore = false;

        Future<void> runPreview(StateSetter setStateDialog) async {
          setStateDialog(() => loadingPreview = true);
          try {
            final result = await previewCallback();
            setStateDialog(() => preview = result);
          } catch (error) {
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text('No se pudo previsualizar: $error')),
            );
          } finally {
            setStateDialog(() => loadingPreview = false);
          }
        }

        Future<void> runRestore(StateSetter setStateDialog) async {
          final password = passwordController.text.trim();
          final confirmation = confirmationController.text.trim();
          if (password.isEmpty) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Ingresa la contrasena de administrador.'),
              ),
            );
            return;
          }
          if (confirmation.toUpperCase() != 'RESTAURAR') {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Debe escribir RESTAURAR para continuar.'),
              ),
            );
            return;
          }
          if (preview != null && preview!.hasLocalCommercialData) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text(
                  'Esta PC ya tiene datos comerciales locales. Por seguridad, primero haga backup o use una PC limpia.',
                ),
              ),
            );
            return;
          }

          setState(() => _isRunningEmergencyRestore = true);
          setStateDialog(() => runningRestore = true);
          try {
            final result = await restoreCallback(
              adminPassword: password,
              confirmationText: confirmation,
            );
            if (!mounted) {
              return;
            }
            final summary = [
              'Restauracion completada.',
              'Backup: ${result.backupPath}',
              'Clientes=${result.localCountsAfter['clients'] ?? 0}, '
                  'Vendedores=${result.localCountsAfter['sellers'] ?? 0}, '
                  'Solares=${result.localCountsAfter['products'] ?? 0}, '
                  'Ventas=${result.localCountsAfter['sales'] ?? 0}, '
                  'Cuotas=${result.localCountsAfter['installments'] ?? 0}, '
                  'Pagos=${result.localCountsAfter['payments'] ?? 0}.',
            ].join(' ');
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(summary),
                duration: const Duration(seconds: 8),
              ),
            );
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          } catch (error) {
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text('No se pudo restaurar: $error')),
            );
          } finally {
            if (mounted) {
              setState(() => _isRunningEmergencyRestore = false);
            }
            setStateDialog(() => runningRestore = false);
          }
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final local = preview?.localCounts ?? const <String, int>{};
            final cloud = preview?.cloudCounts ?? const <String, int>{};

            Widget summaryLine(String label, int localValue, int cloudValue) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '$label · local=$localValue / nube=$cloudValue',
                  style: const TextStyle(fontSize: 12.5),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Restauracion de emergencia'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Esta accion descargara los datos comerciales desde la nube y los guardara en esta PC. Usala solo si la PC anterior se perdio, se dano o estas recuperando una instalacion nueva.',
                      ),
                      const SizedBox(height: 12),
                      if (preview != null) ...[
                        summaryLine(
                          'Clientes',
                          local['clients'] ?? 0,
                          cloud['clients'] ?? 0,
                        ),
                        summaryLine(
                          'Vendedores',
                          local['sellers'] ?? 0,
                          cloud['sellers'] ?? 0,
                        ),
                        summaryLine(
                          'Solares',
                          local['products'] ?? 0,
                          cloud['products'] ?? 0,
                        ),
                        summaryLine(
                          'Ventas',
                          local['sales'] ?? 0,
                          cloud['sales'] ?? 0,
                        ),
                        summaryLine(
                          'Cuotas',
                          local['installments'] ?? 0,
                          cloud['installments'] ?? 0,
                        ),
                        summaryLine(
                          'Pagos',
                          local['payments'] ?? 0,
                          cloud['payments'] ?? 0,
                        ),
                        if (preview!.hasLocalCommercialData)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Esta PC ya tiene datos comerciales locales. Por seguridad, primero haga backup o use una PC limpia.',
                              style: TextStyle(
                                color: Color(0xFFB42318),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        enabled: !runningRestore,
                        decoration: const InputDecoration(
                          labelText: 'Contrasena de administrador',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmationController,
                        enabled: !runningRestore,
                        decoration: const InputDecoration(
                          labelText: 'Escriba RESTAURAR para confirmar',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: runningRestore
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
                FilledButton.tonal(
                  onPressed: (runningRestore || loadingPreview)
                      ? null
                      : () => runPreview(setStateDialog),
                  child: loadingPreview
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Previsualizar restore'),
                ),
                FilledButton(
                  onPressed: runningRestore
                      ? null
                      : () => runRestore(setStateDialog),
                  child: runningRestore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Restaurar desde nube'),
                ),
              ],
            );
          },
        );
      },
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

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncQueueState>(
      stream: SyncQueueService.instance.stateStream,
      initialData: SyncQueueService.instance.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? SyncQueueService.instance.state;
        final error = state.lastError;
        final pending = state.pendingCount;

        if (error == null && pending == 0) {
          return const SizedBox.shrink();
        }

        final isError = error != null;
        final bgColor = isError
            ? const Color(0xFFFFF2F0)
            : const Color(0xFFFFF9E6);
        final borderColor = isError
            ? const Color(0xFFF4C7C3)
            : const Color(0xFFFFE096);
        final fgColor = isError
            ? const Color(0xFFB42318)
            : const Color(0xFF8B6914);
        final textColor = isError
            ? const Color(0xFF7A271A)
            : const Color(0xFF5C4A00);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isError
                        ? Icons.sync_problem_rounded
                        : Icons.cloud_upload_outlined,
                    size: 15,
                    color: fgColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pending > 0
                          ? '$pending registros pendientes de subir a la nube'
                          : 'Problema de sincronizacion',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: fgColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 5),
                Text(error, style: TextStyle(fontSize: 12, color: textColor)),
              ],
              if (pending > 0 && error == null) ...[
                const SizedBox(height: 4),
                Text(
                  'Los registros se subiran automaticamente cuando la conexion este disponible y la PC este autorizada.',
                  style: TextStyle(fontSize: 11.5, color: textColor),
                ),
              ],
            ],
          ),
        );
      },
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

class _SyncTechnicalDiagnosticsPanel extends StatelessWidget {
  const _SyncTechnicalDiagnosticsPanel();

  int _extractCount(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return 0;
    }
    final raw = rows.first['total'];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<_SyncDiagnosticsSnapshot> _loadSnapshot({
    required SyncQueueState queueState,
  }) async {
    final configRepository = SyncConfigRepository();
    final conflictService = SyncConflictService();
    final settings = await configRepository.loadSettings();
    final db = await AppDatabase.instance.database;

    final runtimeState = await configRepository.loadRuntimeState(
      isSyncing: queueState.isProcessing,
      pendingCount: queueState.pendingCount,
    );
    final unresolvedConflicts = await conflictService.unresolvedConflictCount();

    final usersCount = _extractCount(
      await db.rawQuery(
        'SELECT COUNT(*) AS total FROM usuarios WHERE deleted_at IS NULL',
      ),
    );
    final rolesCount = _extractCount(
      await db.rawQuery(
        'SELECT COUNT(*) AS total FROM roles WHERE deleted_at IS NULL',
      ),
    );
    final permissionsCount = _extractCount(
      await db.rawQuery(
        'SELECT COUNT(*) AS total FROM permisos WHERE deleted_at IS NULL',
      ),
    );

    final validationRows = await db.rawQuery(
      'SELECT valor FROM configuracion WHERE clave = ? LIMIT 1',
      ['auth.last_cloud_validation_at'],
    );
    final validationStatusRows = await db.rawQuery(
      'SELECT valor FROM configuracion WHERE clave = ? LIMIT 1',
      ['auth.last_cloud_validation_status'],
    );
    final installationRows = await db.rawQuery(
      'SELECT valor FROM configuracion WHERE clave = ? LIMIT 1',
      ['sync.device_id_fallback'],
    );

    final lastAuthValidationAt = validationRows.isEmpty
        ? null
        : validationRows.first['valor']?.toString().trim();
    final lastAuthValidationStatus = validationStatusRows.isEmpty
        ? null
        : validationStatusRows.first['valor']?.toString().trim();
    final installationId = installationRows.isEmpty
        ? settings.deviceId
        : (installationRows.first['valor']?.toString().trim().isNotEmpty ??
              false)
        ? installationRows.first['valor']!.toString().trim()
        : settings.deviceId;

    final databasePath = await AppDatabase.instance.databasePath;

    return _SyncDiagnosticsSnapshot(
      buildMode: _resolveBuildModeLabel(),
      productionMode: isProductionMode,
      manualCloudSyncOnly: manualCloudSyncOnly,
      authBootstrapAllowed: allowAuthBootstrap,
      cloudPullAllowed: allowCloudPull,
      apiBaseUrl: settings.normalizedBaseUrl,
      localDatabasePath: databasePath,
      syncWorkerActive: SyncQueueService.instance.isWorkerActive,
      runtimeState: runtimeState,
      usersLocalCount: usersCount,
      rolesLocalCount: rolesCount,
      permissionsLocalCount: permissionsCount,
      lastAuthCloudValidationAt: lastAuthValidationAt,
      lastAuthCloudValidationStatus: lastAuthValidationStatus,
      jwtStatus: _resolveJwtStatus(settings.jwtToken),
      deviceId: settings.deviceId,
      installationId: installationId,
      unresolvedConflictCount: unresolvedConflicts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<SyncQueueState>(
          stream: SyncQueueService.instance.stateStream,
          initialData: SyncQueueService.instance.state,
          builder: (context, queueSnapshot) {
            final queueState =
                queueSnapshot.data ?? SyncQueueService.instance.state;
            return FutureBuilder<_SyncDiagnosticsSnapshot>(
              future: _loadSnapshot(queueState: queueState),
              builder: (context, diagSnapshot) {
                if (!diagSnapshot.hasData) {
                  return const SizedBox(
                    width: double.infinity,
                    child: LinearProgressIndicator(minHeight: 2.5),
                  );
                }

                final data = diagSnapshot.data!;
                final runtime = data.runtimeState;
                final cloudPullBlocked = !allowCloudPull;
                final syncMode = manualCloudSyncOnly
                    ? 'MANUAL_CLOUD_SYNC_ONLY'
                    : cloudPullBlocked
                    ? 'LOCAL_TO_CLOUD_ONLY'
                    : 'BIDIRECTIONAL';
                final lastUploadText = _formatDateTime(runtime.lastSyncAt);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel informativo de sincronizacion (LOCAL -> CLOUD)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SyncDiagLine(label: 'buildMode', value: data.buildMode),
                    _SyncDiagLine(
                      label: 'PRODUCTION_MODE',
                      value: data.productionMode ? 'true' : 'false',
                    ),
                    _SyncDiagLine(
                      label: 'MANUAL_CLOUD_SYNC_ONLY',
                      value: data.manualCloudSyncOnly ? 'true' : 'false',
                    ),
                    _SyncDiagLine(
                      label: 'ALLOW_CLOUD_PULL',
                      value: data.cloudPullAllowed ? 'true' : 'false',
                    ),
                    _SyncDiagLine(
                      label: 'ALLOW_AUTH_BOOTSTRAP',
                      value: data.authBootstrapAllowed ? 'true' : 'false',
                    ),
                    _SyncDiagLine(
                      label: 'Auth bootstrap permitido',
                      value: data.authBootstrapAllowed ? 'Si' : 'No',
                    ),
                    _SyncDiagLine(
                      label: 'Cloud pull permitido',
                      value: data.cloudPullAllowed ? 'Si' : 'No',
                    ),
                    _SyncDiagLine(label: 'API actual', value: data.apiBaseUrl),
                    _SyncDiagLine(
                      label: 'database path local',
                      value: data.localDatabasePath,
                    ),
                    _SyncDiagLine(
                      label: 'sync worker activo',
                      value: data.syncWorkerActive ? 'Si' : 'No',
                    ),
                    _SyncDiagLine(label: 'Modo sync', value: syncMode),
                    _SyncDiagLine(
                      label: 'Cloud pull bloqueado',
                      value: cloudPullBlocked ? 'Si' : 'No',
                    ),
                    _SyncDiagLine(
                      label: 'Usuarios locales',
                      value: data.usersLocalCount.toString(),
                    ),
                    _SyncDiagLine(
                      label: 'Roles locales',
                      value: data.rolesLocalCount.toString(),
                    ),
                    _SyncDiagLine(
                      label: 'Permisos locales',
                      value: data.permissionsLocalCount.toString(),
                    ),
                    _SyncDiagLine(
                      label: 'Ultima validacion cloud auth',
                      value: _resolveAuthValidationLabel(
                        data.lastAuthCloudValidationAt,
                        data.lastAuthCloudValidationStatus,
                      ),
                    ),
                    _SyncDiagLine(
                      label: 'Estado JWT/token',
                      value: data.jwtStatus,
                    ),
                    _SyncDiagLine(label: 'DeviceId', value: data.deviceId),
                    _SyncDiagLine(
                      label: 'InstallationId',
                      value: data.installationId,
                    ),
                    _SyncDiagLine(
                      label: 'Pendientes en cola',
                      value: queueState.pendingCount.toString(),
                    ),
                    _SyncDiagLine(
                      label: 'Estado sync_queue',
                      value: queueState.isProcessing
                          ? 'Procesando'
                          : (queueState.pendingCount > 0
                                ? 'Con pendientes'
                                : 'Sin pendientes'),
                    ),
                    _SyncDiagLine(
                      label: 'Ultimo error',
                      value: (queueState.lastError?.trim().isNotEmpty ?? false)
                          ? queueState.lastError!.trim()
                          : (runtime.lastError?.trim().isNotEmpty ?? false)
                          ? runtime.lastError!.trim()
                          : 'Sin errores',
                    ),
                    _SyncDiagLine(
                      label: 'Ultimo upload/sync registrado',
                      value: lastUploadText,
                    ),
                    _SyncDiagLine(
                      label: 'Estado runtime',
                      value: runtime.status.name,
                    ),
                    _SyncDiagLine(
                      label: 'Conflictos pendientes',
                      value: data.unresolvedConflictCount.toString(),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Sin registro';
    }

    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _resolveAuthValidationLabel(String? at, String? status) {
    final normalizedAt = at?.trim() ?? '';
    final normalizedStatus = status?.trim() ?? '';
    if (normalizedAt.isEmpty && normalizedStatus.isEmpty) {
      return 'Sin validaciones';
    }
    if (normalizedAt.isEmpty) {
      return normalizedStatus;
    }
    if (normalizedStatus.isEmpty) {
      return normalizedAt;
    }
    return '$normalizedStatus ($normalizedAt)';
  }

  String _resolveBuildModeLabel() {
    if (kReleaseMode) {
      return 'release';
    }
    if (kProfileMode) {
      return 'profile';
    }
    return 'debug';
  }

  String _resolveJwtStatus(String jwtToken) {
    final normalized = jwtToken.trim();
    if (normalized.isEmpty) {
      return 'Sin token';
    }

    final parts = normalized.split('.');
    if (parts.length != 3) {
      return 'Presente (formato no JWT)';
    }

    try {
      final payloadRaw = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payload = jsonDecode(payloadRaw);
      if (payload is! Map) {
        return 'Presente';
      }
      final expValue = payload['exp'];
      final expSeconds = expValue is num
          ? expValue.toInt()
          : int.tryParse(expValue?.toString() ?? '');
      if (expSeconds == null) {
        return 'Presente';
      }

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expSeconds * 1000,
        isUtc: true,
      ).toLocal();
      final now = DateTime.now();
      if (expiresAt.isBefore(now)) {
        return 'Expirado (${_formatDateTime(expiresAt)})';
      }
      return 'Vigente (${_formatDateTime(expiresAt)})';
    } catch (_) {
      return 'Presente';
    }
  }
}

class _SyncDiagLine extends StatelessWidget {
  const _SyncDiagLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _SyncDiagnosticsSnapshot {
  const _SyncDiagnosticsSnapshot({
    required this.buildMode,
    required this.productionMode,
    required this.manualCloudSyncOnly,
    required this.authBootstrapAllowed,
    required this.cloudPullAllowed,
    required this.apiBaseUrl,
    required this.localDatabasePath,
    required this.syncWorkerActive,
    required this.runtimeState,
    required this.usersLocalCount,
    required this.rolesLocalCount,
    required this.permissionsLocalCount,
    required this.lastAuthCloudValidationAt,
    required this.lastAuthCloudValidationStatus,
    required this.jwtStatus,
    required this.deviceId,
    required this.installationId,
    required this.unresolvedConflictCount,
  });

  final String buildMode;
  final bool productionMode;
  final bool manualCloudSyncOnly;
  final bool authBootstrapAllowed;
  final bool cloudPullAllowed;
  final String apiBaseUrl;
  final String localDatabasePath;
  final bool syncWorkerActive;
  final SyncRuntimeState runtimeState;
  final int usersLocalCount;
  final int rolesLocalCount;
  final int permissionsLocalCount;
  final String? lastAuthCloudValidationAt;
  final String? lastAuthCloudValidationStatus;
  final String jwtStatus;
  final String deviceId;
  final String installationId;
  final int unresolvedConflictCount;
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
