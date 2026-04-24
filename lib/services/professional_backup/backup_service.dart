import 'dart:async';
import 'dart:io';

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import '../../models/sync/sync_report.dart';
import 'backup_cleaner_agent.dart';
import 'backup_log_agent.dart';
import 'backup_scheduler_agent.dart';
import 'cloud_backup_agent.dart';
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
    HttpClient? httpClient,
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
    _cloudAgent = CloudBackupAgent(
      appDatabase: _appDatabase,
      appPaths: _appPaths,
      httpClient: httpClient,
    );
    _restoreAgent = ProfessionalRestoreAgent(
      appDatabase: _appDatabase,
      appPaths: _appPaths,
    );
    _scheduler = BackupSchedulerAgent(job: _runScheduledCloudBackup);
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
  late final CloudBackupAgent _cloudAgent;
  late final BackupSchedulerAgent _scheduler;

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
    _scheduler.reschedule(settings);
    _rescheduleLocalPeriodicBackups(settings);
  }

  Future<void> initialize() async {
    final settings = await getSettings();
    _scheduler.reschedule(settings);
    _rescheduleLocalPeriodicBackups(settings);
    // If the app starts after the scheduled time, try to run once.
    unawaited(runCloudBackupIfDue().catchError((_) {}));
  }

  void dispose() {
    _scheduler.dispose();
    _localPeriodicTimer?.cancel();
    _localPeriodicTimer = null;
  }

  Future<File?> createLocalBackup({required BackupTrigger trigger}) async {
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

  Future<ProfessionalRestoreResult> restoreFromLocalBackup({
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

  Future<void> runCloudBackupIfDue({bool force = false}) async {
    final settings = await getSettings();
    if (!settings.cloudBackupEnabled) {
      return;
    }

    final today = _calendarDate(DateTime.now());

    // Enforce at most one attempt per day unless forced.
    if (!force && settings.lastCloudBackupAttemptDate == today) {
      return;
    }

    // If not pending and already backed up today, nothing to do.
    if (!force &&
        !settings.cloudBackupPending &&
        settings.lastCloudBackupDate == today) {
      return;
    }

    // If not forced, only run after scheduled time for today.
    if (!force) {
      final now = DateTime.now();
      final scheduled = DateTime(
        now.year,
        now.month,
        now.day,
        settings.cloudBackupHour,
        settings.cloudBackupMinute,
      );
      if (now.isBefore(scheduled)) {
        return;
      }
    }

    await _enqueue<void>(() async {
      final uploadDate = DateTime.now();
      final ts = DateTime.now();
      print(
        '[PRO-BACKUP] Iniciando backup nube (force=$force, date=${_calendarDate(uploadDate)})',
      );

      // Persist attempt date first so crash/restart doesn't spam retries.
      await saveSettings(
        (await getSettings()).copyWith(
          lastCloudBackupAttemptDate: _calendarDate(uploadDate),
        ),
      );

      final dbPath = await _appDatabase.databasePath;
      await _activityGuard.waitForNoActiveWriters(databasePath: dbPath);

      final result = await _createAndUploadCloudBackupWithRetries(
        date: uploadDate,
      );
      if (!result.success) {
        print(
          '[PRO-BACKUP] Backup nube falló: status=${result.statusCode} msg=${result.message ?? ''}',
        );

        await saveSettings(
          (await getSettings()).copyWith(cloudBackupPending: true),
        );

        await _logAgent.log(
          timestamp: ts,
          type: 'cloud',
          operation: 'backup',
          result: 'error',
          message: 'status=${result.statusCode} ${result.message ?? ''}'.trim(),
        );

        return;
      }

      print(
        '[PRO-BACKUP] Backup nube subido: ${result.remoteFilename} (status=${result.statusCode})',
      );

      final updated = (await getSettings()).copyWith(
        lastCloudBackupDate: _calendarDate(uploadDate),
        cloudBackupPending: false,
      );
      await saveSettings(updated);

      await _logAgent.log(
        timestamp: ts,
        type: 'cloud',
        operation: 'backup',
        result: 'ok',
        message:
            'status=${result.statusCode} filename=${result.remoteFilename}',
      );
    });
  }

  Future<void> _runScheduledCloudBackup() {
    // Scheduled jobs should still respect "once-per-day".
    return runCloudBackupIfDue(force: false);
  }

  Future<CloudBackupUploadResult> _createAndUploadCloudBackupWithRetries({
    required DateTime date,
  }) async {
    // 3 retries with explicit backoff: 2s → 5s → 10s.
    final retryBackoff = <Duration>[
      const Duration(seconds: 2),
      const Duration(seconds: 5),
      const Duration(seconds: 10),
    ];

    var retryIndex = 0;
    while (true) {
      try {
        final result = await _cloudAgent.createAndUploadDailyBackup(date: date);
        if (result.success) {
          return result;
        }

        final shouldRetry =
            result.statusCode == 408 ||
            result.statusCode == 429 ||
            (result.statusCode >= 500 && result.statusCode <= 599);

        if (!shouldRetry || retryIndex >= retryBackoff.length) {
          return result;
        }
      } on SocketException {
        if (retryIndex >= retryBackoff.length) rethrow;
      } on TimeoutException {
        if (retryIndex >= retryBackoff.length) rethrow;
      } on HttpException {
        if (retryIndex >= retryBackoff.length) rethrow;
      }

      final backoff = retryBackoff[retryIndex];
      print(
        '[PRO-BACKUP] Reintentando backup nube en ${backoff.inSeconds}s (retry ${retryIndex + 1}/${retryBackoff.length})',
      );
      retryIndex++;
      await Future<void>.delayed(backoff);
    }
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

  static String _calendarDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
