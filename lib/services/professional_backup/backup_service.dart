import 'dart:async';
import 'dart:io';

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import 'backup_cleaner_agent.dart';
import 'backup_log_agent.dart';
import 'database_activity_guard.dart';
import 'local_backup_agent.dart';
import 'professional_restore_agent.dart';

enum BackupTrigger { manual }

class BackupService {
  BackupService({
    AppDatabase? appDatabase,
    AppPaths? appPaths,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _appPaths = appPaths ?? AppPaths(),
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
  final BackupCleanerAgent _cleaner;
  final BackupLogAgent _logAgent;
  final DatabaseActivityGuard _activityGuard;

  late final ProfessionalRestoreAgent _restoreAgent;

  late final LocalBackupAgent _localAgent;

  Future<void> _queue = Future<void>.value();

  static final BackupService instance = BackupService();

  Future<void> initialize() async {
    return;
  }

  void dispose() {
    return;
  }

  String get localBackupDirectoryPath => _localAgent.localBackupsDirectory.path;

  Future<File?> createLocalBackup({
    BackupTrigger trigger = BackupTrigger.manual,
  }) async {
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
