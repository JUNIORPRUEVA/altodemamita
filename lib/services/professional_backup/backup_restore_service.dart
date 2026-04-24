import 'dart:io';

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import 'backup_log_agent.dart';
import 'backup_validator_agent.dart';
import 'database_activity_guard.dart';
import 'professional_restore_agent.dart';

class BackupRestoreService {
  BackupRestoreService({
    AppDatabase? appDatabase,
    AppPaths? appPaths,
    BackupValidatorAgent? validator,
    ProfessionalRestoreAgent? restoreAgent,
    BackupLogAgent? logAgent,
    DatabaseActivityGuard? activityGuard,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _appPaths = appPaths ?? AppPaths(),
       _validator = validator ?? const BackupValidatorAgent(),
       _restoreAgent =
           restoreAgent ??
           ProfessionalRestoreAgent(
             appDatabase: appDatabase ?? AppDatabase.instance,
             appPaths: appPaths ?? AppPaths(),
             validator: validator,
           ),
       _logAgent = logAgent ?? BackupLogAgent(appPaths: appPaths),
       _activityGuard = activityGuard ?? const DatabaseActivityGuard();

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final BackupValidatorAgent _validator;
  final ProfessionalRestoreAgent _restoreAgent;
  final BackupLogAgent _logAgent;
  final DatabaseActivityGuard _activityGuard;

  Future<ProfessionalRestoreResult> restoreLocal({
    required String backupPath,
  }) async {
    final now = DateTime.now();
    try {
      await _activityGuard.waitForNoActiveWriters(
        databasePath: await _appDatabase.databasePath,
      );

      final result = await _restoreAgent.restoreFromLocalBackup(
        backupPath: backupPath,
      );

      await _logAgent.log(
        timestamp: now,
        type: 'restore_local',
        operation: 'restore',
        result: result.success ? 'ok' : 'error',
        sizeBytes: await _safeFileSize(backupPath),
        message: result.errorMessage,
      );

      return result;
    } catch (e) {
      await _logAgent.log(
        timestamp: now,
        type: 'restore_local',
        operation: 'restore',
        result: 'error',
        sizeBytes: await _safeFileSize(backupPath),
        message: e.toString(),
      );
      rethrow;
    }
  }

  Future<ProfessionalRestoreResult> restoreLocalBackup({
    required String backupPath,
  }) {
    return restoreLocal(backupPath: backupPath);
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
