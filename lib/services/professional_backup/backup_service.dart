import 'dart:async';
import 'dart:io';

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import '../../models/sync/sync_report.dart';
import 'backup_cleaner_agent.dart';
import 'backup_log_agent.dart';
import 'database_activity_guard.dart';
import 'local_backup_agent.dart';
import 'professional_restore_agent.dart';
import 'professional_backup_settings.dart';
import 'professional_backup_settings_repository.dart';

enum BackupTrigger { appShutdown, syncCompleted, manual, periodic }

class BackupService {
  BackupService({
    AppDatabase? appDatabase,
    AppPaths? appPaths,
    ProfessionalBackupSettingsRepository? settingsRepository,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _appPaths = appPaths ?? AppPaths(),
       _settingsRepository =
           settingsRepository ?? ProfessionalBackupSettingsRepository(),
       _cleaner = const BackupCleanerAgent(),
       _logAgent = BackupLogAgent(appPaths: appPaths),
       _activityGuard = const DatabaseActivityGuard() {
    _localAgent = LocalBackupAgent(
      appDatabase: _appDatabase,
      appPaths: _appPaths,
    );
    _restoreAgent = ProfessionalRestoreAgent(
      appDatabase: _appDatabase,
      appPaths: _appPaths,
    );
  }

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final ProfessionalBackupSettingsRepository _settingsRepository;
  final BackupCleanerAgent _cleaner;
  final BackupLogAgent _logAgent;
  final DatabaseActivityGuard _activityGuard;
  Timer? _localPeriodicTimer;

  static const Duration _localPeriodicInterval = Duration(hours: 6);

  late final ProfessionalRestoreAgent _restoreAgent;

  late final LocalBackupAgent _localAgent;

  ProfessionalBackupSettings? _cachedSettings;
  Future<void> _queue = Future<void>.value();

  static final BackupService instance = BackupService();

  Future<ProfessionalBackupSettings> getSettings() async {
    final cached = _cachedSettings;
    if (cached != null) {
      return cached;
    }
    final loaded = await _settingsRepository.load();
    _cachedSettings = loaded;
    return loaded;
  }

  Future<void> saveSettings(ProfessionalBackupSettings settings) async {
    _cachedSettings = settings;
    await _settingsRepository.save(settings);
    _rescheduleLocalPeriodicBackups(settings);
  }

  Future<void> initialize() async {
    final settings = await getSettings();
    _rescheduleLocalPeriodicBackups(settings);
  }

  void dispose() {
    _localPeriodicTimer?.cancel();
    _localPeriodicTimer = null;
  }

  String get localBackupDirectoryPath => _localAgent.localBackupsDirectory.path;

  Future<File?> createLocalBackup({
    BackupTrigger trigger = BackupTrigger.manual,
  }) async {
    final settings = await getSettings();
    if (!settings.localBackupEnabled) {
      return null;
    }

    return _enqueue<File?>(() async {
      final ts = DateTime.now();
      print('[PRO-BACKUP] Creando backup local (trigger=$trigger)');

      try {
        final dbPath = await _appDatabase.databasePath;
        await _activityGuard.waitForNoActiveWriters(databasePath: dbPath);

        final file = await _localAgent.createLocalBackup();
        print('[PRO-BACKUP] Backup local listo: ${file.path}');

        await _logAgent.log(
          timestamp: ts,
          type: 'local',
          operation: 'backup',
          result: 'ok',
          sizeBytes: await file.length(),
        );

        await _cleaner.enforceLocalRetention(
          directory: _localAgent.localBackupsDirectory,
          keepLast: 15,
        );
        return file;
      } catch (e) {
        await _logAgent.log(
          timestamp: ts,
          type: 'local',
          operation: 'backup',
          result: 'error',
          message: e.toString(),
        );
        rethrow;
      }
    });
  }

  void _rescheduleLocalPeriodicBackups(ProfessionalBackupSettings settings) {
    _localPeriodicTimer?.cancel();
    _localPeriodicTimer = null;

    if (!settings.localBackupEnabled) {
      return;
    }

    _localPeriodicTimer = Timer.periodic(_localPeriodicInterval, (_) {
      unawaited(
        createLocalBackup(
          trigger: BackupTrigger.periodic,
        ).catchError((_, __) => null),
      );
    });
  }

  Future<ProfessionalRestoreResult> restoreLocalBackup({
    required String backupPath,
  }) {
    return _enqueue<ProfessionalRestoreResult>(() async {
      final ts = DateTime.now();
      final dbPath = await _appDatabase.databasePath;
      await _activityGuard.waitForNoActiveWriters(databasePath: dbPath);

      final result = await _restoreAgent.restoreFromLocalBackup(
        backupPath: backupPath,
      );

      await _logAgent.log(
        timestamp: ts,
        type: 'restore_local',
        operation: 'restore',
        result: result.success ? 'ok' : 'error',
        sizeBytes: await _safeFileSize(backupPath),
        message: result.errorMessage,
      );

      return result;
    });
  }

  Future<ProfessionalRestoreResult> restoreFromLocalBackup({
    required String backupPath,
  }) {
    return restoreLocalBackup(backupPath: backupPath);
  }

  Future<void> onSyncStarted() async {
    // Compatibility hook: sync can notify us, but we don't coordinate/lock.
    print('[PRO-BACKUP] Sync iniciado');
  }

  Future<void> onSyncFinished(SyncReport report) async {
    print('[PRO-BACKUP] Sync finalizado');
    if (!report.isSuccess) {
      return;
    }
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        await createLocalBackup(trigger: BackupTrigger.syncCompleted);
      }).catchError((_) {}),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }

  static Future<int?> _safeFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      return null;
    }
  }
}
