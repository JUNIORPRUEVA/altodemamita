import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../domain/backup_config.dart';
import '../domain/backup_metadata.dart';
import '../domain/disk_info.dart';
import '../services/backup_service.dart';
import '../services/disk_detection_service.dart';

class BackupController extends ChangeNotifier {
  static const Duration _silentEntryBackupInterval = Duration(hours: 12);

  BackupController({
    required BackupService backupService,
    required DiskDetectionService diskDetectionService,
  }) : _backupService = backupService,
       _diskDetectionService = diskDetectionService;

  final BackupService _backupService;
  final DiskDetectionService _diskDetectionService;

  // State
  List<DiskInfo> _availableDrives = [];
  DiskInfo? _primaryDrive;
  DiskInfo? _secondaryDrive;
  BackupConfig? _config;
  List<BackupMetadata> _backupHistory = [];
  bool _isLoading = true;
  bool _isCreatingBackup = false;
  bool _isRestoringBackup = false;
  String? _statusMessage;
  String? _errorMessage;
  Future<void>? _initializeFuture;
  Future<void>? _silentEntryBackupFuture;
  bool _isDisposed = false;
  bool _hasLoadedInitialState = false;

  // Getters
  List<DiskInfo> get availableDrives => _availableDrives;
  DiskInfo? get primaryDrive => _primaryDrive;
  DiskInfo? get secondaryDrive => _secondaryDrive;
  BackupConfig? get config => _config;
  List<BackupMetadata> get backupHistory => _backupHistory;
  bool get isLoading => _isLoading;
  bool get isCreatingBackup => _isCreatingBackup;
  bool get isRestoringBackup => _isRestoringBackup;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  bool get hasLoadedInitialState => _hasLoadedInitialState;

  bool get isUsingExternalBackupPath {
    final backupPath = _config?.backupPath.trim();
    if (backupPath == null || backupPath.isEmpty) {
      return false;
    }
    return !_diskDetectionService.isPathOnSystemDrive(backupPath);
  }

  bool get canOpenBackupFolder {
    final backupPath = _config?.backupPath.trim();
    return backupPath != null && backupPath.isNotEmpty;
  }

  bool get isBackupSystemHealthy =>
      _config != null &&
      isUsingExternalBackupPath &&
      _secondaryDrive != null &&
      _secondaryDrive!.hasEnoughSpace;

  String? get lastBackupInfo {
    if (_backupHistory.isEmpty) return null;
    final lastBackup = _backupHistory.first;
    return '${lastBackup.localized} - ${lastBackup.formattedDate} (${lastBackup.formattedSize})';
  }

  /// Initialize controller - detect drives and load config
  /// Handle cases where secondary drive is not available
  Future<void> initialize({
    bool silent = false,
    bool forceRefresh = false,
  }) async {
    final running = _initializeFuture;
    if (running != null) {
      return running;
    }

    if (forceRefresh) {
      _initializeFuture = null;
    }

    final future = _initializeInternal(silent: silent);
    _initializeFuture = future;
    await future.whenComplete(() {
      if (identical(_initializeFuture, future)) {
        _initializeFuture = null;
      }
    });
  }

  Future<void> createSilentEntryBackupIfNeeded({
    Duration minimumInterval = _silentEntryBackupInterval,
    DateTime? now,
  }) async {
    final running = _silentEntryBackupFuture;
    if (running != null) {
      return running;
    }

    final future = _createSilentEntryBackupIfNeededInternal(
      minimumInterval: minimumInterval,
      now: now,
    );
    _silentEntryBackupFuture = future;
    await future.whenComplete(() {
      if (identical(_silentEntryBackupFuture, future)) {
        _silentEntryBackupFuture = null;
      }
    });
  }

  Future<void> _initializeInternal({required bool silent}) async {
    try {
      if (!silent) {
        _setLoading(true);
      }
      _clearMessages();

      // Detect drives
      _availableDrives = await _diskDetectionService.detectAvailableDrives();
      _primaryDrive = await _diskDetectionService.getPrimaryDrive(
        _availableDrives,
      );
      _secondaryDrive = await _diskDetectionService.getSecondaryDrive(
        _availableDrives,
      );

      print(
        '[BACKUP_CONTROLLER] Discos detectados: ${_availableDrives.length}',
      );
      print('[BACKUP_CONTROLLER] Disco primario: ${_primaryDrive?.drive}');
      print('[BACKUP_CONTROLLER] Disco secundario: ${_secondaryDrive?.drive}');

      // Load configuration
      _config = await _backupService.getConfig();
      final validation = await _validateBackupDestination();

      // Load backup history
      _backupHistory = await _backupService.getAllBackups();
      _hasLoadedInitialState = true;

      if (silent) {
        notifyListeners();
      } else if (validation.error != null) {
        _setErrorMessage(validation.error!);
      } else if (validation.status != null) {
        _setStatusMessage(validation.status!);
      } else if (_secondaryDrive == null) {
        _setStatusMessage(
          '⚠️  Sistema configurado, pero sin disco secundario. '
          'Se recomienda conectar una unidad para backup seguro.',
        );
      } else {
        _setStatusMessage(
          'Sistema de backup inicializado correctamente '
          '(${_backupHistory.length} backup(s) disponible(s))',
        );
      }
    } catch (e) {
      print('[BACKUP_CONTROLLER] ERROR en inicialización: $e');
      if (!silent) {
        _setErrorMessage(
          FriendlyErrorMessages.forOperation(
            'inicializar el sistema de respaldos',
            e,
          ),
        );
      }
    } finally {
      if (silent) {
        if (_isLoading) {
          _isLoading = false;
          notifyListeners();
        }
      } else {
        _setLoading(false);
      }
    }
  }

  Future<void> _createSilentEntryBackupIfNeededInternal({
    required Duration minimumInterval,
    DateTime? now,
  }) async {
    if (_isCreatingBackup || _isRestoringBackup) {
      return;
    }

    if (!_hasLoadedInitialState) {
      await initialize(silent: true);
    }

    if (!isBackupSystemHealthy || _config == null) {
      return;
    }

    if (!_config!.autoBackupEnabled) {
      return;
    }

    final referenceTime = now ?? DateTime.now();
    final lastBackupTimestamp =
        _config!.lastBackupTimestamp ??
        (_backupHistory.isNotEmpty ? _backupHistory.first.timestamp : null);

    if (lastBackupTimestamp != null &&
        referenceTime.difference(lastBackupTimestamp) < minimumInterval) {
      return;
    }

    try {
      final result = await _backupService.createBackup(
        backupType: 'module_entry',
      );
      if (!result.success) {
        print(
          '[BACKUP_CONTROLLER] Respaldo silencioso omitido: ${result.errorMessage}',
        );
        return;
      }

      _config = await _backupService.getConfig();
      _backupHistory = await _backupService.getAllBackups();
      notifyListeners();
    } catch (error) {
      print('[BACKUP_CONTROLLER] Error en respaldo silencioso: $error');
    }
  }

  Future<({String? status, String? error})> _validateBackupDestination() async {
    final config = _config;
    if (config == null) {
      return (
        status: null,
        error: 'No se pudo cargar la configuración del sistema de respaldos.',
      );
    }

    final currentPath = config.backupPath.trim();
    final isExternalPath =
        currentPath.isNotEmpty &&
        !_diskDetectionService.isPathOnSystemDrive(currentPath);
    final isAccessiblePath =
        currentPath.isNotEmpty &&
        await _diskDetectionService.canAccessBackupPath(currentPath);

    if (isExternalPath && isAccessiblePath) {
      return (status: null, error: null);
    }

    if (_secondaryDrive != null) {
      final suggestedPath = _getDefaultBackupPath(_secondaryDrive!);
      print(
        '[BACKUP_CONTROLLER] Ajustando respaldo a disco externo: $suggestedPath',
      );
      await _applyBackupPathUpdate(suggestedPath, showSuccessMessage: false);

      final locationLabel =
          '${_secondaryDrive!.drive} (${_secondaryDrive!.label})';
      if (!isExternalPath) {
        return (
          status:
              'Por seguridad, los respaldos ahora se guardan fuera del disco del sistema en $locationLabel.',
          error: null,
        );
      }

      return (
        status:
            'La ruta anterior no estaba disponible. Los respaldos se redirigieron a $locationLabel.',
        error: null,
      );
    }

    if (!isExternalPath) {
      return (
        status: null,
        error:
            'Los respaldos deben guardarse en un disco distinto al del sistema. Conecte una unidad secundaria para habilitarlos.',
      );
    }

    return (
      status: null,
      error:
          'La ruta de backup configurada no está disponible. Conecte la unidad externa donde se guardan los respaldos.',
    );
  }

  /// Create a manual backup
  /// Validates backup path is available before attempting
  Future<void> createManualBackup() async {
    try {
      final pendingBackgroundBackup = _silentEntryBackupFuture;
      if (pendingBackgroundBackup != null) {
        await pendingBackgroundBackup;
      }

      _isCreatingBackup = true;
      _clearMessages();
      notifyListeners();

      if (_config == null) {
        throw StateError('Configuración de backup no cargada');
      }

      if (!isUsingExternalBackupPath) {
        throw StateError(
          'Por seguridad, el respaldo debe guardarse en un disco distinto al del sistema.',
        );
      }

      // Verify path is still available
      final pathAvailable = await _diskDetectionService.canAccessBackupPath(
        _config!.backupPath,
      );
      if (!pathAvailable) {
        throw StateError(
          'Ruta de backup no disponible: ${_config!.backupPath}. '
          'Verificar que el disco está conectado.',
        );
      }

      print('[UI] Iniciando creación de backup manual...');
      final result = await _backupService.createBackup(backupType: 'manual');

      if (result.success) {
        _backupHistory = await _backupService.getAllBackups();
        _setStatusMessage(
          '✓ Backup creado exitosamente\n'
          '${result.metadata.formattedDate} - ${result.metadata.formattedSize}',
        );
        print('[UI] Backup manual creado exitosamente');
      } else {
        _setErrorMessage(
          result.errorMessage ??
              'No se pudo crear la copia de seguridad en este momento.',
        );
        print('[UI] Error en backup manual: ${result.errorMessage}');
      }
    } catch (e) {
      print('[UI] Error in createManualBackup: $e');
      _setErrorMessage(
        FriendlyErrorMessages.forOperation('crear la copia de seguridad', e),
      );
    } finally {
      _isCreatingBackup = false;
      notifyListeners();
    }
  }

  /// Restore from a backup
  /// Creates automatic safety backup before restoring
  Future<void> restoreFromBackup(String backupPath) async {
    try {
      final pendingBackgroundBackup = _silentEntryBackupFuture;
      if (pendingBackgroundBackup != null) {
        await pendingBackgroundBackup;
      }

      _isRestoringBackup = true;
      _clearMessages();
      notifyListeners();

      print('[UI] Iniciando restauración de backup: $backupPath');
      _setStatusMessage('Restaurando base de datos... Por favor espere...');
      notifyListeners();

      final result = await _backupService.restoreFromBackup(
        backupPath: backupPath,
      );

      if (result.success) {
        _backupHistory = await _backupService.getAllBackups();
        _setStatusMessage(
          '✓ Base de datos restaurada exitosamente\n'
          'Se creó backup de seguridad del estado anterior',
        );
        print('[UI] Restauración completada exitosamente');
      } else {
        _setErrorMessage(
          result.errorMessage ??
              'No se pudo restaurar la copia seleccionada en este momento.',
        );
        print('[UI] Error en restauración: ${result.errorMessage}');
      }
    } catch (e) {
      print('[UI] Error in restoreFromBackup: $e');
      _setErrorMessage(
        FriendlyErrorMessages.forOperation(
          'restaurar la copia de seguridad',
          e,
        ),
      );
    } finally {
      _isRestoringBackup = false;
      notifyListeners();
    }
  }

  /// Delete a backup
  Future<void> deleteBackup(String backupPath) async {
    try {
      final success = await _backupService.deleteBackup(backupPath);
      if (success) {
        _backupHistory = await _backupService.getAllBackups();
        _setStatusMessage('Backup eliminado correctamente');
      } else {
        _setErrorMessage(
          'No se pudo eliminar la copia de seguridad en este momento.',
        );
      }
    } catch (e) {
      _setErrorMessage(
        FriendlyErrorMessages.forOperation('eliminar la copia de seguridad', e),
      );
    }
  }

  /// Update backup configuration
  Future<void> updateAutoBackup({
    bool? enabled,
    bool? onStartup,
    bool? onShutdown,
    int? maxRetention,
  }) async {
    if (_config == null) return;

    try {
      final updated = _config!.copyWith(
        autoBackupEnabled: enabled ?? _config!.autoBackupEnabled,
        autoBackupOnStartup: onStartup ?? _config!.autoBackupOnStartup,
        autoBackupOnShutdown: onShutdown ?? _config!.autoBackupOnShutdown,
        maxBackupRetention: maxRetention ?? _config!.maxBackupRetention,
      );

      await _backupService.updateConfig(updated);
      _config = updated;
      _setStatusMessage('Configuración actualizada');
      notifyListeners();
    } catch (e) {
      _setErrorMessage(
        FriendlyErrorMessages.forOperation('actualizar la configuración', e),
      );
    }
  }

  /// Update backup path
  Future<void> updateBackupPath(String newPath) async {
    await _applyBackupPathUpdate(newPath, showSuccessMessage: true);
  }

  Future<void> _applyBackupPathUpdate(
    String newPath, {
    required bool showSuccessMessage,
  }) async {
    if (_config == null) return;

    try {
      if (_diskDetectionService.isPathOnSystemDrive(newPath)) {
        throw StateError(
          'Por seguridad, los respaldos solo se permiten en un disco distinto al del sistema.',
        );
      }

      // Verify path exists or can be created
      final isAvailable = await _diskDetectionService.canAccessBackupPath(
        newPath,
      );
      if (!isAvailable) {
        final created = await _diskDetectionService.createBackupDirectory(
          newPath,
        );
        if (!created) {
          throw StateError('No se pudo crear el directorio: $newPath');
        }
      }

      final updated = _config!.copyWith(backupPath: newPath);
      await _backupService.updateConfig(updated);
      _config = updated;
      if (showSuccessMessage) {
        _setStatusMessage('Ruta de backup actualizada: $newPath');
      } else {
        notifyListeners();
      }
    } catch (e) {
      _setErrorMessage(
        FriendlyErrorMessages.forOperation('actualizar la ruta de respaldo', e),
      );
    }
  }

  Future<void> openBackupFolder() async {
    final backupPath = _config?.backupPath.trim();
    if (backupPath == null || backupPath.isEmpty) {
      _setErrorMessage('No hay una ruta de backup configurada para abrir.');
      return;
    }

    final opened = await _diskDetectionService.openInFileExplorer(backupPath);
    if (!opened) {
      _setErrorMessage(
        'No se pudo abrir la carpeta de backups. Verifique que la unidad esté conectada.',
      );
      return;
    }

    _setStatusMessage('Abriendo carpeta de backups: $backupPath');
  }

  /// Re-detect drives and update state
  Future<void> redetectDrives() async {
    try {
      _setLoading(true);
      _clearMessages();

      _availableDrives = await _diskDetectionService.detectAvailableDrives();
      _primaryDrive = await _diskDetectionService.getPrimaryDrive(
        _availableDrives,
      );
      _secondaryDrive = await _diskDetectionService.getSecondaryDrive(
        _availableDrives,
      );

      _setStatusMessage('Detección de discos completada');
    } catch (e) {
      _setErrorMessage(
        FriendlyErrorMessages.forOperation(
          'detectar las unidades disponibles',
          e,
        ),
      );
    } finally {
      _setLoading(false);
    }
  }

  /// Get backups by type
  List<BackupMetadata> getBackupsByType(String type) {
    return _backupHistory.where((b) => b.type == type).toList();
  }

  // Private helpers
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setStatusMessage(String message) {
    _statusMessage = message;
    _errorMessage = null;
    notifyListeners();
  }

  void _setErrorMessage(String message) {
    _errorMessage = message;
    _statusMessage = null;
    notifyListeners();
  }

  void _clearMessages() {
    _statusMessage = null;
    _errorMessage = null;
  }

  String _getDefaultBackupPath(DiskInfo drive) {
    return '${drive.drive}\\SistemaSolares\\Backups';
  }

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
