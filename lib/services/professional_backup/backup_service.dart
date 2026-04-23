import 'dart:async';
import 'dart:io';

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import '../../models/sync/sync_report.dart';
import 'backup_cleaner_agent.dart';
import 'backup_scheduler_agent.dart';
import 'cloud_backup_agent.dart';
import 'local_backup_agent.dart';
import 'professional_backup_settings.dart';
import 'professional_backup_settings_repository.dart';

enum BackupTrigger {
  appShutdown,
  syncCompleted,
  manual,
}

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
       _cleaner = const BackupCleanerAgent() {
    _localAgent = LocalBackupAgent(
      appDatabase: _appDatabase,
      appPaths: _appPaths,
    );
    _cloudAgent = CloudBackupAgent(
      appDatabase: _appDatabase,
      appPaths: _appPaths,
      httpClient: httpClient,
    );
    _scheduler = BackupSchedulerAgent(job: _runScheduledCloudBackup);
  }

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final ProfessionalBackupSettingsRepository _settingsRepository;
  final BackupCleanerAgent _cleaner;

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
  }

  Future<void> initialize() async {
    final settings = await getSettings();
    _scheduler.reschedule(settings);
    // If the app starts after the scheduled time, try to run once.
    unawaited(runCloudBackupIfDue().catchError((_) {}));
  }

  void dispose() {
    _scheduler.dispose();
  }

  Future<File?> createLocalBackup({required BackupTrigger trigger}) async {
    final settings = await getSettings();
    if (!settings.localBackupEnabled) {
      return null;
    }

    return _enqueue<File?>(() async {
      final file = await _localAgent.createLocalBackup();
      await _cleaner.enforceLocalRetention(
        directory: _localAgent.localBackupsDirectory,
        keepLast: 15,
      );
      return file;
    });
  }

  Future<void> onSyncFinished(SyncReport report) async {
    if (!report.isSuccess) {
      return;
    }
    await createLocalBackup(trigger: BackupTrigger.syncCompleted);
  }

  Future<void> runCloudBackupIfDue({bool force = false}) async {
    final settings = await getSettings();
    if (!settings.cloudBackupEnabled) {
      return;
    }

    final today = _calendarDate(DateTime.now());
    if (!force && settings.lastCloudBackupDate == today) {
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
      final result = await _createAndUploadCloudBackupWithRetries(
        date: uploadDate,
        maxRetries: 2,
      );
      if (!result.success) {
        throw StateError(
          'La nube rechazó el backup (${result.statusCode}): ${result.message ?? ''}',
        );
      }

      final updated = (await getSettings()).copyWith(
        lastCloudBackupDate: _calendarDate(uploadDate),
      );
      await saveSettings(updated);
    });
  }

  Future<void> _runScheduledCloudBackup() {
    // Scheduled jobs should still respect "once-per-day".
    return runCloudBackupIfDue(force: false);
  }

  Future<CloudBackupUploadResult> _createAndUploadCloudBackupWithRetries({
    required DateTime date,
    required int maxRetries,
  }) async {
    var attempt = 0;
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

        if (!shouldRetry || attempt >= maxRetries) {
          return result;
        }
      } on SocketException {
        if (attempt >= maxRetries) rethrow;
      } on TimeoutException {
        if (attempt >= maxRetries) rethrow;
      } on HttpException {
        if (attempt >= maxRetries) rethrow;
      }

      attempt++;
      final backoff = Duration(milliseconds: 750 * attempt);
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

  static String _calendarDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
