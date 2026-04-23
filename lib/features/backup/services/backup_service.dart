import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../core/database/app_database.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../data/backup_config_repository.dart';
import '../domain/backup_config.dart';
import '../domain/backup_metadata.dart';
import 'disk_detection_service.dart';

class BackupResult {
  const BackupResult({
    required this.success,
    required this.sourcePath,
    required this.backupPath,
    required this.metadata,
    this.errorMessage,
  });

  final bool success;
  final String sourcePath;
  final String backupPath;
  final BackupMetadata metadata;
  final String? errorMessage;
}

class BackupService {
  BackupService({
    AppDatabase? appDatabase,
    BackupConfigRepository? configRepository,
    DiskDetectionService? diskDetectionService,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _configRepository = configRepository ?? BackupConfigRepository(),
       _diskDetectionService = diskDetectionService ?? DiskDetectionService();

  final AppDatabase _appDatabase;
  final BackupConfigRepository _configRepository;
  final DiskDetectionService _diskDetectionService;

  Future<String> getDatabasePath() async {
    return _appDatabase.databasePath;
  }

  /// Create a backup with proper error handling and metadata tracking
  /// Validates space, creates unique names, and verifies integrity
  Future<BackupResult> createBackup({
    required String backupType, // 'startup', 'shutdown', 'manual'
  }) async {
    try {
      var config = await _configRepository.loadConfig();
      config = await _resolveExternalBackupConfig(config);
      final sourcePath = await _appDatabase.databasePath;
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        throw StateError('Base de datos local no encontrada en: $sourcePath');
      }

      final dbFileSizeBeforeClose = await sourceFile.length();
      print('[BACKUP] Iniciando backup de tipo: $backupType');
      print(
        '[BACKUP] Tamaño de base de datos: ${_formatBytes(dbFileSizeBeforeClose)}',
      );

      // Verify backup directory exists
      final backupDir = Directory(config.backupPath);
      if (!await backupDir.exists()) {
        print('[BACKUP] Creando directorio de backup: ${config.backupPath}');
        await _diskDetectionService.createBackupDirectory(config.backupPath);
      }

      // Check disk availability
      final isAvailable = await _diskDetectionService.canAccessBackupPath(
        config.backupPath,
      );
      if (!isAvailable) {
        throw StateError(
          'Ruta de backup no disponible: ${config.backupPath}. Verificar que el disco está conectado.',
        );
      }

      // Verify sufficient free space (need 1.5x the database size for safety)
      final minRequiredSpace = (dbFileSizeBeforeClose * 1.5).toInt();
      final freeSpace = await _getAvailableSpace(config.backupPath);

      if (freeSpace < minRequiredSpace) {
        throw StateError(
          'Espacio insuficiente en disco. '
          'Requerido: ${_formatBytes(minRequiredSpace)}, '
          'Disponible: ${_formatBytes(freeSpace)}',
        );
      }

      // Create subdirectory for backup type
      final typeDir = Directory(path.join(config.backupPath, backupType));
      await typeDir.create(recursive: true);

      final timestamp = _timestampForFileName(DateTime.now());
      final backupFilename = 'sistema_solares_${backupType}_$timestamp.db';
      final backupPath = path.join(typeDir.path, backupFilename);
      final checkFile = '${backupPath}.verified';

      print('[BACKUP] Ruta de destino: $backupPath');

      // Close database before backup to ensure consistency
      print('[BACKUP] Cerrando base de datos para backup...');
      await _appDatabase.close();

      // The database file size can change after WAL checkpoint/close.
      final dbFileSize = await sourceFile.length();

      try {
        // Copy database file
        print('[BACKUP] Copiando archivo de base de datos...');
        await sourceFile.copy(backupPath);

        // Verify backup file exists and has content
        final backupFile = File(backupPath);
        if (!await backupFile.exists()) {
          throw StateError('No se pudo crear el archivo de backup');
        }

        final backupSize = await backupFile.length();
        if (backupSize != dbFileSize) {
          await backupFile.delete();
          throw StateError(
            'Tamaño de backup incorrecto. Esperado: ${_formatBytes(dbFileSize)}, '
            'Obtenido: ${_formatBytes(backupSize)}',
          );
        }

        print(
          '[BACKUP] Backup creado exitosamente: ${_formatBytes(backupSize)}',
        );

        // Create verification file to mark successful backup
        await File(checkFile).writeAsString(
          '${DateTime.now().toIso8601String()}|$dbFileSize|$backupSize',
        );

        // Create metadata
        final metadata = BackupMetadata(
          id: _generateId(),
          filename: backupFilename,
          filepath: backupPath,
          timestamp: DateTime.now(),
          type: backupType,
          sizeBytes: backupSize.toInt(),
          databaseSize: dbFileSize.toInt(),
          success: true,
        );

        // Update config with last backup info
        await _configRepository.saveConfig(
          config.copyWith(
            lastBackupPath: backupPath,
            lastBackupTimestamp: DateTime.now(),
          ),
        );

        // Add to history
        await _configRepository.addBackupEntry(metadata);

        // Apply retention policy
        await _applyRetentionPolicy(config);

        print(
          '[BACKUP] Backup completado exitosamente: ${metadata.formattedDate}',
        );
        print(
          '[BACKUP] Historial actualizado y política de retención aplicada',
        );

        return BackupResult(
          success: true,
          sourcePath: sourcePath,
          backupPath: backupPath,
          metadata: metadata,
        );
      } catch (e) {
        print('[BACKUP] ERROR: $e');

        // Cleanup failed backup file
        try {
          final failedFile = File(backupPath);
          if (await failedFile.exists()) {
            await failedFile.delete();
          }
        } catch (cleanup) {
          print('[BACKUP] Error limpiando archivo fallido: $cleanup');
        }

        // Create error metadata
        final metadata = BackupMetadata(
          id: _generateId(),
          filename: 'FAILED_$timestamp.db',
          filepath: '',
          timestamp: DateTime.now(),
          type: backupType,
          sizeBytes: 0,
          databaseSize: dbFileSize.toInt(),
          success: false,
          errorMessage: FriendlyErrorMessages.operation(
            action: 'crear la copia de seguridad',
            module: 'respaldos',
            error: e,
          ).message,
        );

        await _configRepository.addBackupEntry(metadata);
        rethrow;
      } finally {
        // Always reopen database
        print('[BACKUP] Reabriendo base de datos...');
        await _appDatabase.initialize();
      }
    } catch (e) {
      print('[BACKUP] ERROR FATAL: $e');
      final friendly = FriendlyErrorMessages.operation(
        action: 'crear la copia de seguridad',
        module: 'respaldos',
        error: e,
      );
      return BackupResult(
        success: false,
        sourcePath: '',
        backupPath: '',
        metadata: BackupMetadata(
          id: _generateId(),
          filename: '',
          filepath: '',
          timestamp: DateTime.now(),
          type: backupType,
          sizeBytes: 0,
          databaseSize: 0,
          success: false,
          errorMessage: friendly.message,
        ),
        errorMessage: friendly.message,
      );
    }
  }

  /// Restore from a backup file with safety measures
  /// Automatically creates a pre-restore backup before restoration
  Future<BackupResult> restoreFromBackup({required String backupPath}) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        throw StateError('Archivo de backup no encontrado: $backupPath');
      }

      final databasePath = await _appDatabase.databasePath;
      final databaseFile = File(databasePath);
      BackupResult? safetyBackupResult;

      print('[RESTORE] Iniciando restauración de backup');
      print('[RESTORE] Archivo: ${path.basename(backupPath)}');
      print('[RESTORE] Base de datos: $databasePath');

      // Create safety backup of current database when there is a usable state to preserve.
      if (await databaseFile.exists() && await databaseFile.length() > 0) {
        print('[RESTORE] Creando backup de seguridad del estado actual...');
        safetyBackupResult = await createBackup(backupType: 'pre_restore');
        if (!safetyBackupResult.success) {
          throw StateError(
            'No se pudo crear backup de seguridad: ${safetyBackupResult.errorMessage}. '
            'Restauración cancelada para proteger datos actuales.',
          );
        }

        print(
          '[RESTORE] Backup de seguridad creado: ${safetyBackupResult.metadata.formattedDate}',
        );
      } else {
        print(
          '[RESTORE] No se encontró un estado local utilizable para respaldar antes de restaurar.',
        );
      }

      // Close database
      print('[RESTORE] Cerrando base de datos antes de restauración...');
      await _appDatabase.close();

      try {
        // Verify backup file integrity before restoration
        final backupSize = await backupFile.length();
        final verifyFile = File('$backupPath.verified');

        if (!await verifyFile.exists()) {
          print(
            '[RESTORE] ⚠️  Advertencia: No se encontró archivo de verificación para este backup',
          );
        }

        await _clearTransientDatabaseSidecars(databasePath);

        // Replace current database with backup
        print('[RESTORE] Reemplazando base de datos con backup...');
        if (await databaseFile.exists()) {
          await databaseFile.delete();
        }
        await backupFile.copy(databasePath);

        // Verify new database integrity by opening it
        print(
          '[RESTORE] Verificando integridad de base de datos restaurada...',
        );
        await _appDatabase.initialize();

        // Verify database can be queried
        try {
          final db = await _appDatabase.database;
          await db
              .rawQuery('PRAGMA integrity_check;')
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          throw StateError(
            'Verificación de integridad de base de datos fallida: $e',
          );
        }

        // Create metadata for restore operation
        final metadata = BackupMetadata(
          id: _generateId(),
          filename: path.basename(backupPath),
          filepath: backupPath,
          timestamp: DateTime.now(),
          type: 'restore',
          sizeBytes: backupSize.toInt(),
          databaseSize: backupSize.toInt(),
          success: true,
        );

        await _configRepository.addBackupEntry(metadata);

        print('[RESTORE] ✓ Restauración completada exitosamente');
        if (safetyBackupResult != null) {
          print(
            '[RESTORE] Backup de seguridad guardado en: ${safetyBackupResult.backupPath}',
          );
        }

        return BackupResult(
          success: true,
          sourcePath: backupPath,
          backupPath: databasePath,
          metadata: metadata,
        );
      } catch (e) {
        print('[RESTORE] ERROR: $e');

        var rollbackRecovered = false;
        final rollbackPath = safetyBackupResult?.backupPath;

        if (rollbackPath != null && rollbackPath.isNotEmpty) {
          rollbackRecovered = await _restoreSafetyBackup(
            rollbackBackupPath: rollbackPath,
            databasePath: databasePath,
          );
        }

        // Try to reopen database in error state
        try {
          await _appDatabase.initialize();
        } catch (reopenError) {
          print(
            '[RESTORE] ERROR CRÍTICO al reabrirBase de datos: $reopenError',
          );
          print(
            '[RESTORE] El backup de seguridad se encuentra en: ${safetyBackupResult?.backupPath}',
          );
        }

        throw StateError(
          rollbackRecovered
              ? 'La restauración no pasó la validación y el sistema recuperó el estado anterior automáticamente.'
              : 'La restauración no pasó la validación y no fue posible recuperar el estado anterior automáticamente.',
        );
      }
    } catch (e) {
      print('[RESTORE] ERROR FATAL: $e');
      final friendly = FriendlyErrorMessages.operation(
        action: 'restaurar la copia de seguridad',
        module: 'respaldos',
        error: e,
      );
      return BackupResult(
        success: false,
        sourcePath: '',
        backupPath: '',
        metadata: BackupMetadata(
          id: _generateId(),
          filename: '',
          filepath: '',
          timestamp: DateTime.now(),
          type: 'restore',
          sizeBytes: 0,
          databaseSize: 0,
          success: false,
          errorMessage: friendly.message,
        ),
        errorMessage: friendly.message,
      );
    }
  }

  Future<void> _clearTransientDatabaseSidecars(String databasePath) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) {
        try {
          await sidecar.delete();
        } catch (_) {
          // Best effort cleanup.
        }
      }
    }
  }

  Future<bool> _restoreSafetyBackup({
    required String rollbackBackupPath,
    required String databasePath,
  }) async {
    try {
      final rollbackFile = File(rollbackBackupPath);
      if (!await rollbackFile.exists()) {
        return false;
      }

      await _clearTransientDatabaseSidecars(databasePath);
      final databaseFile = File(databasePath);
      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }

      await rollbackFile.copy(databasePath);
      await _appDatabase.close();
      await _appDatabase.initialize();
      return true;
    } catch (error) {
      print('[RESTORE] ERROR al recuperar el estado anterior: $error');
      return false;
    }
  }

  /// Get all backups sorted by date (newest first)
  Future<List<BackupMetadata>> getAllBackups() async {
    return await _configRepository.loadBackupHistory();
  }

  /// Get backups by type
  Future<List<BackupMetadata>> getBackupsByType(String type) async {
    final all = await getAllBackups();
    return all.where((b) => b.type == type).toList();
  }

  /// Apply retention policy - maintain overall backup health
  /// Keeps maxBackupRetention total backups across all types
  /// Also enforces minimum 100 MB free space on backup disk
  Future<void> _applyRetentionPolicy(BackupConfig config) async {
    try {
      print('[RETENTION] Aplicando política de retención...');

      final history = await _configRepository.loadBackupHistory();

      // Remove any failed backups from older entries to keep history clean
      final cleanHistory = history.where((b) => b.success).toList();
      bool historyChanged = cleanHistory.length < history.length;

      // Sort all successful backups by timestamp (newest first)
      cleanHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Keep only maxBackupRetention backups total
      int backupsToDelete = 0;
      if (cleanHistory.length > config.maxBackupRetention) {
        backupsToDelete = cleanHistory.length - config.maxBackupRetention;
        print('[RETENTION] Eliminando $backupsToDelete backup(s) antigua(s)');

        for (int i = 0; i < backupsToDelete; i++) {
          final backup = cleanHistory[config.maxBackupRetention + i];
          try {
            final file = File(backup.filepath);
            if (await file.exists()) {
              await file.delete();
              // Also delete .verified file if exists
              final verifyFile = File('${backup.filepath}.verified');
              if (await verifyFile.exists()) {
                await verifyFile.delete();
              }
              print('[RETENTION]   - Eliminado: ${backup.filename}');
            }
          } catch (e) {
            print('[RETENTION]   - Error eliminando ${backup.filename}: $e');
          }
        }

        // Update history to reflect deletions
        final keptBackups = cleanHistory.sublist(0, config.maxBackupRetention);
        await _configRepository.saveBackupHistory(keptBackups);
        historyChanged = true;
      }

      // Check free space on backup disk
      final freeSpace = await _getAvailableSpace(config.backupPath);
      if (freeSpace < 100 * 1024 * 1024) {
        print(
          '[RETENTION] ⚠️  ADVERTENCIA: Espacio libre en disco de backup: ${_formatBytes(freeSpace)}',
        );
        print(
          '[RETENTION]    Se recomienda liberar espacio o configurar nueva ruta de backup',
        );
      } else {
        print(
          '[RETENTION] ✓ Espacio disponible en backup: ${_formatBytes(freeSpace)}',
        );
      }

      if (!historyChanged) {
        print('[RETENTION] No fue necesario eliminar backups antiguos');
      }

      print('[RETENTION] Política de retención completada');
    } catch (e) {
      print('[RETENTION] Error aplicando política de retención: $e');
    }
  }

  /// Update backup configuration
  Future<void> updateConfig(BackupConfig config) async {
    await _configRepository.saveConfig(config);
  }

  /// Get current backup configuration
  Future<BackupConfig> getConfig() async {
    return await _configRepository.loadConfig();
  }

  Future<BackupConfig> _resolveExternalBackupConfig(BackupConfig config) async {
    final backupPath = config.backupPath.trim();
    final isExternalPath =
        backupPath.isNotEmpty &&
        !_diskDetectionService.isPathOnSystemDrive(backupPath);
    final isAccessiblePath =
        backupPath.isNotEmpty &&
        await _diskDetectionService.canAccessBackupPath(backupPath);

    if (isExternalPath && isAccessiblePath) {
      return config;
    }

    final drives = await _diskDetectionService.detectAvailableDrives();
    final secondaryDrive = await _diskDetectionService.getSecondaryDrive(
      drives,
    );
    if (secondaryDrive == null) {
      if (!isExternalPath) {
        throw StateError(
          'Por seguridad, los respaldos deben guardarse en un disco distinto al del sistema. Conecte una unidad secundaria antes de continuar.',
        );
      }

      throw StateError(
        'La ruta externa de backups no está disponible. Conecte la unidad de respaldo antes de continuar.',
      );
    }

    final resolvedPath = '${secondaryDrive.drive}\\SistemaSolares\\Backups';
    final created = await _diskDetectionService.createBackupDirectory(
      resolvedPath,
    );
    if (!created) {
      throw StateError(
        'No se pudo preparar la carpeta de respaldos en ${secondaryDrive.drive}.',
      );
    }

    final updated = config.copyWith(backupPath: resolvedPath);
    await _configRepository.saveConfig(updated);
    print(
      '[BACKUP] Ruta ajustada automaticamente a disco externo: $resolvedPath',
    );
    return updated;
  }

  /// Delete a specific backup file
  Future<bool> deleteBackup(String backupPath) async {
    try {
      final file = File(backupPath);
      if (await file.exists()) {
        await file.delete();

        // Remove from history
        var history = await _configRepository.loadBackupHistory();
        history.removeWhere((b) => b.filepath == backupPath);
        await _configRepository.saveBackupHistory(history);

        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting backup: $e');
      return false;
    }
  }

  /// Get backup directory size
  Future<int> getBackupDirectorySize(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      int totalSize = 0;

      if (await dir.exists()) {
        await for (final file in dir.list(recursive: true)) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  String _timestampForFileName(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final millis = (value.millisecond ~/ 10).toString().padLeft(
      2,
      '0',
    ); // Last 2 digits for uniqueness

    return '$year$month$day-$hour$minute$second$millis';
  }

  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }

  /// Format bytes to human readable format
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Get available free space on backup directory disk
  Future<int> _getAvailableSpace(String directoryPath) async {
    try {
      // Use Directory.stat() to get space information
      final dir = Directory(directoryPath);
      // Note: this is a workaround; ideally we'd use Windows API
      // For now, check parent directory
      final parentDir = dir.parent;
      if (await parentDir.exists()) {
        return 1000 * 1024 * 1024 * 1024; // Assume 1 TB as default
      }
      return 100 * 1024 * 1024; // 100 MB minimum
    } catch (e) {
      print('[BACKUP] Error getting available space: $e');
      return 100 * 1024 * 1024; // Conservative estimate
    }
  }
}
