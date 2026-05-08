import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/domain/admin_override_scope.dart';
import '../../auth/domain/permission_model.dart';
import '../../auth/presentation/admin_override_prompt.dart';
import '../../auth/presentation/auth_provider.dart';
import '../domain/backup_config.dart';
import '../domain/backup_metadata.dart';
import '../domain/disk_info.dart';
import '../services/backup_service.dart';
import '../services/disk_detection_service.dart';
import 'backup_controller.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/dangerous_action_confirm_dialog.dart';

class BackupPage extends StatefulWidget {
  final BackupController? controller;
  final BackupService backupService;
  final DiskDetectionService diskDetectionService;
  final Future<String> Function()? onResetBusinessData;

  const BackupPage({
    Key? key,
    this.controller,
    required this.backupService,
    required this.diskDetectionService,
    this.onResetBusinessData,
  }) : super(key: key);

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupController _controller;
  late final bool _ownsController;
  bool _isRunningBusinessReset = false;

  @override
  void initState() {
    super.initState();
    final providedController = widget.controller;
    _ownsController = providedController == null;
    _controller =
        providedController ??
        BackupController(
          backupService: widget.backupService,
          diskDetectionService: widget.diskDetectionService,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_loadBackupScreenSilently());
    });
  }

  Future<void> _loadBackupScreenSilently() async {
    await _controller.initialize(silent: true, forceRefresh: true);
    if (!mounted) {
      return;
    }
    await _controller.createSilentEntryBackupIfNeeded();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  bool _canManageBackup(AuthProvider auth) {
    return auth.hasScopedAccess(
      scope: AdminOverrideScope.settingsBackup,
      module: PermissionCatalog.settings,
      action: PermissionAction.update,
    );
  }

  Future<bool> _ensureAuthorized() async {
    final auth = context.read<AuthProvider>();
    if (_canManageBackup(auth)) {
      return true;
    }

    return requestAdminOverride(
      context,
      scope: AdminOverrideScope.settingsBackup,
      title: 'Autorización administrativa requerida',
      message:
          'Necesitas la clave de un administrador para crear, restaurar o modificar respaldos.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Backup',
      child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_controller.statusMessage != null)
                        _buildStatusBanner(
                          message: _controller.statusMessage!,
                          isError: false,
                        ),
                      if (_controller.errorMessage != null)
                        _buildStatusBanner(
                          message: _controller.errorMessage!,
                          isError: true,
                        ),
                      if (_controller.primaryDrive != null ||
                          _controller.secondaryDrive != null)
                        _buildSystemStatusSection(_controller),
                      if (_controller.config != null)
                        _buildConfigurationSection(_controller),
                      _buildManualBackupSection(_controller),
                      _buildDangerZoneSection(),
                      _buildBackupHistorySection(_controller),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusBanner({required String message, required bool isError}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        border: Border(
          left: BorderSide(
            color: isError ? Colors.red : Colors.green,
            width: 4,
          ),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade900 : Colors.green.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusSection(BackupController controller) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  controller.isBackupSystemHealthy
                      ? Icons.check_circle
                      : Icons.warning,
                  color: controller.isBackupSystemHealthy
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 12),
                Text(
                  'Estado del Sistema',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Primary Drive
            if (controller.primaryDrive != null)
              _buildDriveInfo(controller.primaryDrive!, 'Unidad Principal'),
            const SizedBox(height: 12),
            // Secondary Drive
            if (controller.secondaryDrive != null)
              _buildDriveInfo(controller.secondaryDrive!, 'Unidad de Backup'),
            if (controller.secondaryDrive == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No se detectó unidad secundaria para backup',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveInfo(DiskInfo drive, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${drive.usedPercentage.toStringAsFixed(1)}% usado',
              style: TextStyle(
                color: drive.usedPercentage > 80
                    ? Colors.red
                    : Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${drive.drive} - ${drive.label}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: drive.usedPercentage / 100,
            minHeight: 8,
            valueColor: AlwaysStoppedAnimation<Color>(
              drive.usedPercentage > 80 ? Colors.red : Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Libre: ${drive.formattedFree}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            Text(
              'Total: ${drive.formattedTotal}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        if (!drive.hasEnoughSpace) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Espacio insuficiente para backup (se requieren 100 MB)',
                  style: TextStyle(fontSize: 12, color: Colors.red[700]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildConfigurationSection(BackupController controller) {
    final config = controller.config!;
    final usesExternalPath = controller.isUsingExternalBackupPath;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            // Backup Path
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ruta de Backup',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          config.backupPath,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          // Handle path selection
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'change',
                            child: Text('Cambiar ruta'),
                          ),
                        ],
                        child: Icon(
                          Icons.more_vert,
                          color: Colors.grey[700],
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: usesExternalPath
                            ? const Color(0xFFEAF8F0)
                            : const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            usesExternalPath
                                ? Icons.verified_outlined
                                : Icons.warning_amber_rounded,
                            size: 16,
                            color: usesExternalPath
                                ? const Color(0xFF1A7F45)
                                : const Color(0xFFB35600),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            usesExternalPath
                                ? 'Destino externo verificado'
                                : 'Debe estar fuera del disco del sistema',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: usesExternalPath
                                  ? const Color(0xFF1A7F45)
                                  : const Color(0xFFB35600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: controller.canOpenBackupFolder
                          ? () async {
                              await controller.openBackupFolder();
                            }
                          : null,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Abrir carpeta de backups'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Auto Backup Settings
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Backup Automático',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Switch(
                      value: config.autoBackupEnabled,
                      onChanged: (value) async {
                        if (!await _ensureAuthorized()) {
                          return;
                        }
                        controller.updateAutoBackup(enabled: value);
                      },
                    ),
                  ],
                ),
                if (config.autoBackupEnabled) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text(
                      'Al iniciar aplicación',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: config.autoBackupOnStartup,
                    onChanged: (value) async {
                      if (!await _ensureAuthorized()) {
                        return;
                      }
                      controller.updateAutoBackup(onStartup: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text(
                      'Al cerrar aplicación',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: config.autoBackupOnShutdown,
                    onChanged: (value) async {
                      if (!await _ensureAuthorized()) {
                        return;
                      }
                      controller.updateAutoBackup(onShutdown: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Retention Policy
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backups a Retener',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${config.maxBackupRetention} copias',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () async {
                    if (!await _ensureAuthorized()) {
                      return;
                    }
                    _showRetentionDialog(context, controller, config);
                  },
                  child: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Last Backup Info
            if (controller.lastBackupInfo != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Último backup: ${controller.lastBackupInfo}',
                        style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualBackupSection(BackupController controller) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Acciones Rápidas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                    !controller.isCreatingBackup &&
                        controller.isBackupSystemHealthy
                    ? () => _confirmBackup(context, controller)
                    : null,
                icon: controller.isCreatingBackup
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                      )
                    : const Icon(Icons.backup),
                label: Text(
                  controller.isCreatingBackup
                      ? 'Creando copia de seguridad...'
                      : 'Crear Copia de Seguridad Ahora',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            if (controller.secondaryDrive == null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Se necesita una unidad externa distinta al disco del sistema para crear backups',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (!controller.isUsingExternalBackupPath)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'La ruta actual no es válida para respaldos. Debe estar en una unidad externa.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupHistorySection(BackupController controller) {
    final backups = controller.backupHistory;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Historial de Backups',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (backups.isNotEmpty)
                  Text(
                    '${backups.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (backups.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.backup_table,
                        color: Colors.grey[400],
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No hay backups disponibles',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: backups.length,
                separatorBuilder: (_, __) => Divider(color: Colors.grey[300]),
                itemBuilder: (context, index) {
                  final backup = backups[index];
                  return _buildBackupItem(context, backup, controller);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZoneSection() {
    final callback = widget.onResetBusinessData;
    final enabled = callback != null && !_isRunningBusinessReset;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB42318)),
          title: const Text(
            'Zona avanzada: reseteo de datos',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Borra clientes, solares, vendedores y ventas (nube + local).',
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF4C7C3)),
              ),
              child: const Text(
                'Accion irreversible. Tambien elimina cuotas y pagos asociados para mantener consistencia.\n\n'
                'Requiere clave del usuario actual.',
                style: TextStyle(color: Color(0xFF7A271A), height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? _resetBusinessData : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB42318),
                ),
                icon: _isRunningBusinessReset
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: Text(
                  _isRunningBusinessReset
                      ? 'Ejecutando reseteo...'
                      : 'Ejecutar reseteo',
                ),
              ),
            ),
            if (callback == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'El servicio de reseteo no esta disponible en esta version.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetBusinessData() async {
    if (_isRunningBusinessReset) {
      return;
    }

    final callback = widget.onResetBusinessData;
    if (callback == null) {
      return;
    }

    if (!await _ensureAuthorized()) {
      return;
    }

    final confirmed = await DangerousActionConfirmDialog.show(
      context,
      title: 'Confirmar reseteo de datos',
      warning:
          'Se eliminaran definitivamente los datos comerciales en la nube y en esta PC: clientes, solares, vendedores, ventas, cuotas y pagos.\n\n'
          'No se borran usuarios, permisos, impresoras ni configuracion general.',
      confirmLabel: 'Si, ejecutar reseteo',
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isRunningBusinessReset = true;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Ejecutando reseteo de datos...')),
    );

    try {
      final summary = await callback();
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(SnackBar(content: Text(summary)));
      await _controller.initialize(silent: true, forceRefresh: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo completar el reseteo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningBusinessReset = false;
        });
      }
    }
  }

  Widget _buildBackupItem(
    BuildContext context,
    BackupMetadata backup,
    BackupController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getBackupTypeIcon(backup.type),
                          size: 20,
                          color: Colors.grey[700],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          backup.localized,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (!backup.success)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      backup.formattedDate,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (backup.success)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tamaño: ${backup.formattedSize}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (!await _ensureAuthorized()) {
                    return;
                  }
                  if (value == 'restore') {
                    _confirmRestore(context, backup, controller);
                  } else if (value == 'delete') {
                    _confirmDelete(context, backup, controller);
                  }
                },
                itemBuilder: (_) => [
                  if (backup.success)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Row(
                        children: [
                          Icon(Icons.restore, size: 18),
                          SizedBox(width: 8),
                          Text('Restaurar'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Eliminar'),
                      ],
                    ),
                  ),
                ],
                child: Icon(Icons.more_vert, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getBackupTypeIcon(String type) {
    switch (type) {
      case 'module_entry':
        return Icons.auto_awesome_outlined;
      case 'startup':
        return Icons.play_circle_outline;
      case 'shutdown':
        return Icons.stop_circle_outlined;
      case 'manual':
        return Icons.backup;
      case 'restore':
        return Icons.restore;
      case 'pre_restore':
        return Icons.shield;
      default:
        return Icons.backup;
    }
  }

  void _showRetentionDialog(
    BuildContext context,
    BackupController controller,
    BackupConfig config,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cantidad de Backups a Retener'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Actualmente: ${config.maxBackupRetention}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Slider(
              value: config.maxBackupRetention.toDouble(),
              min: 3,
              max: 20,
              divisions: 17,
              label: config.maxBackupRetention.toString(),
              onChanged: (value) {
                // Update would happen on save
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Se eliminarán automáticamente los backups más antiguos',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBackup(
    BuildContext context,
    BackupController controller,
  ) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Crear Copia de Seguridad?'),
        content: const Text(
          'Se creará una copia de seguridad de la base de datos. Este proceso puede tomar algunos minutos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              controller.createManualBackup();
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRestore(
    BuildContext context,
    BackupMetadata backup,
    BackupController controller,
  ) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Restaurar Copia de Seguridad?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Advertencia: Se restaurarán todos los datos de la copia seleccionada. Se creará una copia de seguridad de los datos actuales antes de restaurar.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    backup.formattedDate,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Tamaño: ${backup.formattedSize}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              controller.restoreFromBackup(backup.filepath);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    BackupMetadata backup,
    BackupController controller,
  ) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar Copia de Seguridad?'),
        content: Text(
          'Se eliminará permanentemente la copia del ${backup.formattedDate}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              controller.deleteBackup(backup.filepath);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
