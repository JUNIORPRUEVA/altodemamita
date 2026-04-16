import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../database/database_schema.dart';
import '../../features/backup/data/backup_config_repository.dart';
import '../../features/backup/services/backup_service.dart';
import '../../features/backup/services/disk_detection_service.dart';
import 'app_incident.dart';
import 'app_paths.dart';
import 'friendly_error_messages.dart';
import 'incident_logger.dart';

enum StartupRecoveryStatus { healthy, recovered, needsAttention, failed }

class StartupRecoveryReport {
  const StartupRecoveryReport({
    required this.status,
    required this.title,
    required this.message,
    required this.suggestions,
    required this.repairs,
    required this.showRecoveryScreen,
    required this.canContinue,
    required this.allowBackupRestore,
    this.incidentCode,
    this.latestBackupPath,
  });

  final StartupRecoveryStatus status;
  final String title;
  final String message;
  final List<String> suggestions;
  final List<String> repairs;
  final bool showRecoveryScreen;
  final bool canContinue;
  final bool allowBackupRestore;
  final String? incidentCode;
  final String? latestBackupPath;
}

class StartupRecoveryService {
  StartupRecoveryService({
    required AppDatabase appDatabase,
    required BackupConfigRepository backupConfigRepository,
    required BackupService backupService,
    required DiskDetectionService diskDetectionService,
    required IncidentLogger incidentLogger,
    AppPaths? appPaths,
  }) : _appDatabase = appDatabase,
       _backupConfigRepository = backupConfigRepository,
       _backupService = backupService,
       _diskDetectionService = diskDetectionService,
       _incidentLogger = incidentLogger,
       _appPaths = appPaths ?? AppPaths();

  final AppDatabase _appDatabase;
  final BackupConfigRepository _backupConfigRepository;
  final BackupService _backupService;
  final DiskDetectionService _diskDetectionService;
  final IncidentLogger _incidentLogger;
  final AppPaths _appPaths;

  Future<StartupRecoveryReport> prepareApplication({
    void Function(String status)? onStatus,
    bool aggressiveRepair = false,
  }) async {
    final repairs = <String>[];
    final warnings = <String>[];

    try {
      onStatus?.call('Verificando carpetas del sistema...');
      await _appPaths.ensureCriticalDirectories();
      await _appPaths.cleanTransientFiles();

      onStatus?.call('Validando recursos esenciales...');
      await _verifyCriticalResources();

      onStatus?.call('Revisando configuracion minima...');
      final configRebuilt = await _backupConfigRepository.ensureMinimumConfig();
      if (configRebuilt) {
        repairs.add('Se reconstruyo la configuracion minima del sistema.');
      }

      final historyRebuilt = await _backupConfigRepository
          .ensureReadableHistory();
      if (historyRebuilt) {
        repairs.add('Se recupero el historial local de copias.');
      }

      final backupConfig = await _backupConfigRepository.loadConfig();
      final backupPathAvailable = await _ensureBackupPath(
        backupConfig.backupPath,
      );
      if (!backupPathAvailable) {
        warnings.add(
          'La ruta de respaldo no estuvo disponible y quedo pendiente de revision.',
        );
      }

      onStatus?.call('Comprobando base de datos local...');
      final databaseResult = await _recoverDatabase(
        onStatus: onStatus,
        aggressiveRepair: aggressiveRepair,
      );
      repairs.addAll(databaseResult.repairs);

      final latestBackupPath = await _findLatestRestorableBackup();

      if (!databaseResult.healthy) {
        final friendly = const FriendlyErrorMessage(
          title: 'No pudimos dejar el sistema listo automaticamente',
          message:
              'Intentamos reparar el inicio varias veces, pero todavia hace falta una accion de recuperacion.',
          details:
              'Detuvimos la apertura normal para evitar que el sistema inicie con informacion incompleta o inestable.',
          suggestions: [
            'Use Reparacion automatica para intentarlo otra vez.',
            'Si hay una copia confiable disponible, restaurela como ultimo recurso.',
          ],
        );

        final incidentCode = await _incidentLogger.logIncident(
          category: 'startup_failure',
          severity: AppIncidentSeverity.critical,
          friendlyMessage: friendly,
          error: databaseResult.failure,
          extra: {'repairs': repairs, 'warnings': warnings},
        );

        return StartupRecoveryReport(
          status: StartupRecoveryStatus.failed,
          title: friendly.title,
          message: friendly.message,
          suggestions: friendly.suggestions,
          repairs: repairs,
          showRecoveryScreen: true,
          canContinue: false,
          allowBackupRestore: latestBackupPath != null,
          incidentCode: incidentCode,
          latestBackupPath: latestBackupPath,
        );
      }

      if (warnings.isNotEmpty || databaseResult.startedWithFreshDatabase) {
        final friendly = FriendlyErrorMessage(
          title: 'El sistema pudo abrirse con recuperacion asistida',
          message: databaseResult.startedWithFreshDatabase
              ? 'Protegimos el estado anterior y preparamos una base local segura para que pueda continuar.'
              : 'El sistema esta utilizable, pero quedaron verificaciones pendientes por completar.',
          details: databaseResult.startedWithFreshDatabase
              ? 'Se creo un entorno local limpio para que pueda retomar el trabajo mientras revisa el estado previo si lo necesita.'
              : 'Puede seguir trabajando, pero conviene revisar las advertencias y ejecutar una verificacion adicional cuando sea oportuno.',
          suggestions: [
            'Puede continuar trabajando si todo luce correcto.',
            'Use Reparacion automatica si desea volver a intentar la verificacion completa.',
            if (latestBackupPath != null)
              'Solo restaure una copia si necesita volver a un estado anterior confiable.',
          ],
        );

        final incidentCode = await _incidentLogger.logIncident(
          category: 'startup_recovered',
          severity: AppIncidentSeverity.warning,
          friendlyMessage: friendly,
          extra: {
            'repairs': repairs,
            'warnings': warnings,
            'startedWithFreshDatabase': databaseResult.startedWithFreshDatabase,
          },
        );

        return StartupRecoveryReport(
          status: StartupRecoveryStatus.needsAttention,
          title: friendly.title,
          message: friendly.message,
          suggestions: [...friendly.suggestions, ...warnings],
          repairs: repairs,
          showRecoveryScreen: true,
          canContinue: true,
          allowBackupRestore: false,
          incidentCode: incidentCode,
          latestBackupPath: latestBackupPath,
        );
      }

      return StartupRecoveryReport(
        status: repairs.isEmpty
            ? StartupRecoveryStatus.healthy
            : StartupRecoveryStatus.recovered,
        title: 'Sistema listo',
        message: 'La aplicacion se preparo correctamente.',
        suggestions: const [],
        repairs: repairs,
        showRecoveryScreen: false,
        canContinue: true,
        allowBackupRestore: false,
      );
    } catch (error, stackTrace) {
      final friendly = FriendlyErrorMessages.unexpected(error);
      final incidentCode = await _incidentLogger.logIncident(
        category: 'startup_unexpected',
        severity: AppIncidentSeverity.critical,
        friendlyMessage: friendly,
        error: error,
        stackTrace: stackTrace,
      );

      return StartupRecoveryReport(
        status: StartupRecoveryStatus.failed,
        title: 'No se pudo completar el inicio',
        message:
            'El sistema encontro un problema inesperado antes de abrir la aplicacion.',
        suggestions: const [
          'Use Reintentar inicio para volver a cargar.',
          'Si no mejora, ejecute una nueva reparacion automatica.',
        ],
        repairs: repairs,
        showRecoveryScreen: true,
        canContinue: false,
        allowBackupRestore: await _findLatestRestorableBackup() != null,
        incidentCode: incidentCode,
        latestBackupPath: await _findLatestRestorableBackup(),
      );
    }
  }

  Future<bool> _ensureBackupPath(String backupPath) async {
    if (backupPath.trim().isEmpty) {
      return false;
    }

    if (await _diskDetectionService.isPathAvailable(backupPath)) {
      return true;
    }

    return _diskDetectionService.createBackupDirectory(backupPath);
  }

  Future<void> _verifyCriticalResources() async {
    final databasePath = await _appDatabase.databasePath;
    final directoriesToProbe = <String>{
      _appPaths.supportDirectory,
      _appPaths.tempDirectory,
      _appPaths.cacheDirectory,
      _appPaths.recoveryDirectory,
      _appPaths.quarantineDirectory,
      path.dirname(databasePath),
    };

    for (final directoryPath in directoriesToProbe) {
      await Directory(directoryPath).create(recursive: true);
      await _probeDirectory(directoryPath);
    }
  }

  Future<void> _probeDirectory(String directoryPath) async {
    final probeFile = File(
      path.join(
        directoryPath,
        '.probe_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );

    try {
      await probeFile.writeAsString('ok', flush: true);
      await probeFile.delete();
    } on FileSystemException {
      rethrow;
    }
  }

  Future<_DatabaseRecoveryResult> _recoverDatabase({
    void Function(String status)? onStatus,
    required bool aggressiveRepair,
  }) async {
    final repairs = <String>[];
    final databasePath = await _appDatabase.databasePath;
    final databaseFile = File(databasePath);
    await databaseFile.parent.create(recursive: true);

    if (await databaseFile.exists() && await databaseFile.length() == 0) {
      await _quarantineDatabase(databasePath, reason: 'empty_file');
      repairs.add(
        'Se aparto un archivo de base de datos vacio y se preparo uno nuevo.',
      );
    }

    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        onStatus?.call('Abriendo base de datos local...');
        await _appDatabase.close();
        await _appDatabase.initialize();
        final db = await _appDatabase.database;

        onStatus?.call('Validando integridad de datos...');
        await db.transaction((txn) async {
          await DatabaseSchema.ensureCoreStructures(txn);
        });

        final missingTables = await DatabaseSchema.missingCriticalTables(db);
        if (missingTables.isNotEmpty) {
          throw StateError(
            'missing_critical_tables=${missingTables.join(',')}',
          );
        }

        final integrity = await _runIntegrityCheck(db);
        if (integrity != 'ok') {
          throw StateError('integrity_check=$integrity');
        }

        return _DatabaseRecoveryResult(
          healthy: true,
          repairs: repairs,
          startedWithFreshDatabase: repairs.any(
            (item) =>
                item.contains('se preparo uno nuevo') ||
                item.contains('base limpia'),
          ),
        );
      } catch (error) {
        lastError = error;

        if (attempt == 1) {
          final journalRepairApplied = await _clearTransientDatabaseSidecars(
            databasePath,
          );
          if (journalRepairApplied) {
            repairs.add(
              'Se limpiaron archivos temporales pendientes de la base local.',
            );
          }
          continue;
        }

        if (attempt == 2 || aggressiveRepair) {
          final preserved = await _snapshotDatabase(
            databasePath,
            reason: aggressiveRepair ? 'aggressive_repair' : 'startup_failure',
          );
          if (preserved) {
            repairs.add(
              'Se guardo una copia diagnostica del archivo actual para analisis y recuperacion posterior.',
            );
          }
        }

        break;
      }
    }

    return _DatabaseRecoveryResult(
      healthy: false,
      repairs: repairs,
      failure: lastError,
    );
  }

  Future<String> _runIntegrityCheck(Database db) async {
    final quickRows = await db.rawQuery('PRAGMA quick_check;');
    final quickResult = quickRows.isNotEmpty
        ? quickRows.first.values.first
        : 'ok';
    if ('$quickResult' == 'ok') {
      return 'ok';
    }

    final fullRows = await db.rawQuery('PRAGMA integrity_check;');
    return fullRows.isNotEmpty ? '${fullRows.first.values.first}' : 'unknown';
  }

  Future<bool> _clearTransientDatabaseSidecars(String databasePath) async {
    var changed = false;

    for (final suffix in ['-wal', '-shm', '-journal']) {
      final file = File('$databasePath$suffix');
      if (await file.exists()) {
        try {
          await file.delete();
          changed = true;
        } catch (_) {
          // Best effort cleanup.
        }
      }
    }

    return changed;
  }

  Future<bool> _quarantineDatabase(
    String databasePath, {
    required String reason,
  }) async {
    final databaseFile = File(databasePath);
    if (!await databaseFile.exists()) {
      return false;
    }

    await _appPaths.ensureCriticalDirectories();
    await _appDatabase.close();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final basename = path.basenameWithoutExtension(databasePath);
    final extension = path.extension(databasePath);
    final target = path.join(
      _appPaths.quarantineDirectory,
      '${basename}_${reason}_$timestamp$extension',
    );

    await databaseFile.rename(target);
    await _clearTransientDatabaseSidecars(databasePath);
    return true;
  }

  Future<bool> _snapshotDatabase(
    String databasePath, {
    required String reason,
  }) async {
    final databaseFile = File(databasePath);
    if (!await databaseFile.exists()) {
      return false;
    }

    await _appPaths.ensureCriticalDirectories();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final basename = path.basenameWithoutExtension(databasePath);
    final extension = path.extension(databasePath);
    final target = path.join(
      _appPaths.snapshotsDirectory,
      '${basename}_${reason}_$timestamp$extension',
    );

    await databaseFile.copy(target);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) {
        await sidecar.copy('$target$suffix');
      }
    }

    return true;
  }

  Future<String?> _findLatestRestorableBackup() async {
    final backups = await _backupService.getAllBackups();
    final successfulBackups =
        backups
            .where((backup) => backup.success && backup.filepath.isNotEmpty)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (final backup in successfulBackups) {
      if (await File(backup.filepath).exists()) {
        return backup.filepath;
      }
    }

    return null;
  }
}

class _DatabaseRecoveryResult {
  const _DatabaseRecoveryResult({
    required this.healthy,
    required this.repairs,
    this.failure,
    this.startedWithFreshDatabase = false,
  });

  final bool healthy;
  final List<String> repairs;
  final Object? failure;
  final bool startedWithFreshDatabase;
}
