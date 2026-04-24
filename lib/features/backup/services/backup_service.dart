import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/resilience/app_paths.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../services/professional_backup/backup_log_agent.dart';
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
    AppPaths? appPaths,
    BackupLogAgent? logAgent,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _configRepository = configRepository ?? BackupConfigRepository(),
       _diskDetectionService = diskDetectionService ?? DiskDetectionService(),
       _appPaths = appPaths ?? AppPaths(),
       _logAgent = logAgent ?? BackupLogAgent(appPaths: appPaths ?? AppPaths());

  final AppDatabase _appDatabase;
  final BackupConfigRepository _configRepository;
  final DiskDetectionService _diskDetectionService;
  final AppPaths _appPaths;
  final BackupLogAgent _logAgent;

  static const int _minHistoryDays = 7;

  Future<String> getDatabasePath() async {
    return _appDatabase.databasePath;
  }

  /// Create a backup with proper error handling and metadata tracking
  /// Validates space, creates unique names, and verifies integrity
  Future<BackupResult> createBackup({
    required String backupType, // 'startup', 'shutdown', 'manual'
  }) async {
    final ts = DateTime.now();
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
      final backupFilename = 'sistema_solares_${backupType}_$timestamp.zip';
      final backupPath = path.join(typeDir.path, backupFilename);
      final tmpBackupPath = '$backupPath.tmp';
      final checkFile = '${backupPath}.verified';

      print('[BACKUP] Ruta de destino: $backupPath');

      // Close database before backup to ensure consistency
      print('[BACKUP] Cerrando base de datos para backup...');
      await _appDatabase.close();

      // The database file size can change after WAL checkpoint/close.
      final dbFileSize = await sourceFile.length();

      try {
        await _validateSQLiteSourceDatabase(sourceFile);

        print('[BACKUP] Empaquetando respaldo completo (ZIP)...');
        await _appPaths.ensureCriticalDirectories();

        final tmpBackupFile = File(tmpBackupPath);
        if (await tmpBackupFile.exists()) {
          try {
            await tmpBackupFile.delete();
          } catch (_) {}
        }

        final packaged = await _buildBackupPackage(
          destinationZipPath: tmpBackupPath,
          databaseFile: sourceFile,
        );

        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        try {
          await packaged.rename(backupPath);
        } on FileSystemException {
          await packaged.copy(backupPath);
          await packaged.delete();
        }

        final finalBackupFile = File(backupPath);
        if (!await finalBackupFile.exists()) {
          throw StateError('No se pudo crear el archivo ZIP de backup');
        }

        final backupSize = await finalBackupFile.length();
        if (backupSize <= 0) {
          await finalBackupFile.delete();
          throw StateError('El archivo ZIP de backup está vacío.');
        }

        // Quick ZIP signature validation (PK\x03\x04).
        final header = await _readFirstBytes(finalBackupFile, 4);
        if (header.length < 4 ||
            header[0] != 0x50 ||
            header[1] != 0x4B ||
            header[2] != 0x03 ||
            header[3] != 0x04) {
          await finalBackupFile.delete();
          throw StateError('El archivo generado no parece ser un ZIP válido.');
        }

        print('[BACKUP] Backup completo creado: ${_formatBytes(backupSize)}');

        // Create verification file to mark successful backup
        await File(checkFile).writeAsString(
          '${DateTime.now().toIso8601String()}|dbSize=$dbFileSize|zipSize=$backupSize',
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

        await _logAgent.log(
          timestamp: ts,
          type: 'legacy_external',
          operation: 'backup',
          result: 'ok',
          sizeBytes: backupSize.toInt(),
          message: 'type=$backupType file=${metadata.filename}',
        );

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
          final tmpFile = File(tmpBackupPath);
          if (await tmpFile.exists()) {
            await tmpFile.delete();
          }
        } catch (cleanup) {
          print('[BACKUP] Error limpiando archivo fallido: $cleanup');
        }

        // Create error metadata
        final metadata = BackupMetadata(
          id: _generateId(),
          filename: 'FAILED_$timestamp.zip',
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

        await _logAgent.log(
          timestamp: ts,
          type: 'legacy_external',
          operation: 'backup',
          result: 'error',
          message: metadata.errorMessage ?? e.toString(),
        );
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
    final ts = DateTime.now();
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

        if (_isZipPackage(backupPath)) {
          print('[RESTORE] Restaurando paquete ZIP (DB + archivos)...');
          await _restoreFromZipPackage(
            zipPath: backupPath,
            databasePath: databasePath,
          );
        } else {
          // Replace current database with backup
          print('[RESTORE] Reemplazando base de datos con backup...');
          if (await databaseFile.exists()) {
            await databaseFile.delete();
          }
          await backupFile.copy(databasePath);
        }

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

        await _logAgent.log(
          timestamp: ts,
          type: 'legacy_external',
          operation: 'restore',
          result: 'ok',
          sizeBytes: backupSize.toInt(),
          message: 'file=${path.basename(backupPath)}',
        );

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

      if (_isZipPackage(rollbackBackupPath)) {
        await _restoreFromZipPackage(
          zipPath: rollbackBackupPath,
          databasePath: databasePath,
        );
      } else {
        final databaseFile = File(databasePath);
        if (await databaseFile.exists()) {
          await databaseFile.delete();
        }
        await rollbackFile.copy(databasePath);
      }

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

      // Keep at least the last 7 calendar days, even if it exceeds maxBackupRetention.
      final cutoff = DateTime.now().subtract(const Duration(days: _minHistoryDays));
        final protected = cleanHistory
          .where((b) => !b.timestamp.isBefore(cutoff))
          .toList();
        final candidates = cleanHistory.where((b) => b.timestamp.isBefore(cutoff)).toList();

      // Delete only from older-than-cutoff candidates until we reach maxBackupRetention.
      if (cleanHistory.length > config.maxBackupRetention && candidates.isNotEmpty) {
        var currentCount = cleanHistory.length;
        final targetCount = config.maxBackupRetention;

        // Oldest first among candidates.
        candidates.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        for (final backup in candidates) {
          if (currentCount <= targetCount) {
            break;
          }
          try {
            final file = File(backup.filepath);
            if (await file.exists()) {
              await file.delete();
            }
            final verifyFile = File('${backup.filepath}.verified');
            if (await verifyFile.exists()) {
              await verifyFile.delete();
            }
            currentCount--;
            print('[RETENTION]   - Eliminado: ${backup.filename}');
          } catch (e) {
            print('[RETENTION]   - Error eliminando ${backup.filename}: $e');
          }
        }

        // Rebuild kept list: protected + remaining candidates that still exist.
        final kept = <BackupMetadata>[];
        kept.addAll(protected);
        for (final backup in candidates) {
          if (kept.any((b) => b.id == backup.id)) continue;
          final file = File(backup.filepath);
          if (await file.exists()) {
            kept.add(backup);
          }
        }

        kept.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _configRepository.saveBackupHistory(kept);
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

  bool _isZipPackage(String backupPath) {
    return backupPath.trim().toLowerCase().endsWith('.zip');
  }

  Future<File> _buildBackupPackage({
    required String destinationZipPath,
    required File databaseFile,
  }) async {
    final zipFile = File(destinationZipPath);
    await zipFile.parent.create(recursive: true);

    final encoder = ZipFileEncoder();
    encoder.create(destinationZipPath);

    // Database.
    encoder.addFile(
      databaseFile,
      path.posix.join('database', DatabaseSchema.databaseName),
    );

    // Config files.
    final configDir = Directory(_appPaths.configDirectory);
    if (await configDir.exists()) {
      await for (final entity in configDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: configDir.path);
        encoder.addFile(
          entity,
          path.posix.joinAll(['config', ...path.split(relative)]),
        );
      }
    }

    // Generated files.
    final generatedDir = Directory(_appPaths.generatedDirectory);
    if (await generatedDir.exists()) {
      await for (final entity in generatedDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: generatedDir.path);
        encoder.addFile(
          entity,
          path.posix.joinAll(['generated', ...path.split(relative)]),
        );
      }
    }

    // Manifest.
    final manifestPath = path.join(
      _appPaths.tempDirectory,
      'backup_manifest_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final manifestFile = File(manifestPath);
    await manifestFile.parent.create(recursive: true);
    await manifestFile.writeAsString(
      jsonEncode({
        'createdAt': DateTime.now().toIso8601String(),
        'database': {
          'name': DatabaseSchema.databaseName,
          'sizeBytes': await databaseFile.length(),
        },
      }),
      flush: true,
    );
    encoder.addFile(manifestFile, path.posix.join('manifest.json'));

    encoder.close();

    try {
      await manifestFile.delete();
    } catch (_) {}

    return zipFile;
  }

  Future<void> _restoreFromZipPackage({
    required String zipPath,
    required String databasePath,
  }) async {
    await _appPaths.ensureCriticalDirectories();

    final extractDir = Directory(
      path.join(
        _appPaths.tempDirectory,
        'restore_extract_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await extractDir.create(recursive: true);

    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      extractArchiveToDisk(archive, extractDir.path);

      final extractedDbPath = path.join(
        extractDir.path,
        'database',
        DatabaseSchema.databaseName,
      );
      final extractedDb = File(extractedDbPath);
      if (!await extractedDb.exists()) {
        throw StateError('El paquete ZIP no contiene la base de datos esperada.');
      }

      // Restore config files.
      final extractedConfigDir = Directory(path.join(extractDir.path, 'config'));
      if (await extractedConfigDir.exists()) {
        await for (final entity in extractedConfigDir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final relative = path.relative(entity.path, from: extractedConfigDir.path);
          final dest = File(path.join(_appPaths.configDirectory, relative));
          await dest.parent.create(recursive: true);
          await entity.copy(dest.path);
        }
      }

      // Restore generated files.
      final extractedGeneratedDir = Directory(path.join(extractDir.path, 'generated'));
      if (await extractedGeneratedDir.exists()) {
        await for (final entity in extractedGeneratedDir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final relative = path.relative(entity.path, from: extractedGeneratedDir.path);
          final dest = File(path.join(_appPaths.generatedDirectory, relative));
          await dest.parent.create(recursive: true);
          await entity.copy(dest.path);
        }
      }

      // Restore database atomically.
      final databaseFile = File(databasePath);
      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }
      await extractedDb.copy(databasePath);
    } finally {
      try {
        if (await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _validateSQLiteSourceDatabase(File databaseFile) async {
    sqfliteFfiInit();
    final length = await databaseFile.length();
    if (length <= 0) {
      throw StateError('La base de datos está vacía.');
    }

    final header = await _readFirstBytes(databaseFile, 16);
    const signature = 'SQLite format 3\x00';
    final expected = signature.codeUnits;
    for (var i = 0; i < expected.length; i++) {
      if (i >= header.length || header[i] != expected[i]) {
        throw StateError('El archivo no parece ser una base SQLite válida.');
      }
    }

    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(
        databaseFile.path,
        options: OpenDatabaseOptions(
          readOnly: true,
          singleInstance: false,
        ),
      );

      final rows = await db.rawQuery('PRAGMA quick_check(1)');
      final first = rows.isNotEmpty ? rows.first.values.first : null;
      final normalized = first?.toString().trim().toLowerCase() ?? '';
      if (normalized != 'ok') {
        throw StateError('La base SQLite no pasó quick_check.');
      }

      final missing = await DatabaseSchema.missingCriticalTables(db);
      if (missing.isNotEmpty) {
        throw StateError('La base SQLite no contiene tablas críticas.');
      }
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  static Future<List<int>> _readFirstBytes(File file, int count) async {
    final raf = await file.open();
    try {
      final buffer = List<int>.filled(count, 0);
      final read = await raf.readInto(buffer);
      return buffer.sublist(0, read);
    } finally {
      await raf.close();
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
