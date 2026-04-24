import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import 'backup_log_agent.dart';
import 'backup_validator_agent.dart';
import 'cloud_restore_agent.dart';
import 'database_activity_guard.dart';
import 'professional_restore_agent.dart';

class BackupRestoreService {
  BackupRestoreService({
    AppDatabase? appDatabase,
    AppPaths? appPaths,
    BackupValidatorAgent? validator,
    ProfessionalRestoreAgent? restoreAgent,
    CloudRestoreAgent? cloudRestoreAgent,
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
       _cloudRestoreAgent = cloudRestoreAgent ?? CloudRestoreAgent(),
       _logAgent = logAgent ?? BackupLogAgent(appPaths: appPaths),
       _activityGuard = activityGuard ?? const DatabaseActivityGuard();

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final BackupValidatorAgent _validator;
  final ProfessionalRestoreAgent _restoreAgent;
  final CloudRestoreAgent _cloudRestoreAgent;
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

  Future<List<CloudBackupListItem>> listCloudBackups() {
    return _cloudRestoreAgent.listBackups();
  }

  Future<ProfessionalRestoreResult> restoreCloud({
    required String backupId,
  }) async {
    final now = DateTime.now();
    File? zipFile;
    File? extractedDb;

    try {
      await _appPaths.ensureCriticalDirectories();

      await _activityGuard.waitForNoActiveWriters(
        databasePath: await _appDatabase.databasePath,
      );

      final zipPath = path.join(_appPaths.tempDirectory, 'cloud_restore_$backupId');
      zipFile = await _cloudRestoreAgent.downloadBackup(
        id: backupId,
        destinationPath: zipPath,
      );

      await _validator.validateZipFile(zipFile);

      extractedDb = await _extractDbFromZip(zipFile);
      await _validator.validateSQLiteDbFile(extractedDb);

      final result = await _restoreAgent.restoreFromLocalBackup(
        backupPath: extractedDb.path,
      );

      await _logAgent.log(
        timestamp: now,
        type: 'restore_cloud',
        operation: 'restore',
        result: result.success ? 'ok' : 'error',
        sizeBytes: await zipFile.length(),
        message: result.errorMessage,
      );

      return result;
    } catch (e) {
      await _logAgent.log(
        timestamp: now,
        type: 'restore_cloud',
        operation: 'restore',
        result: 'error',
        sizeBytes: zipFile == null ? null : await zipFile.length(),
        message: e.toString(),
      );
      rethrow;
    } finally {
      // Best-effort cleanup of temp artifacts.
      try {
        await extractedDb?.delete();
      } catch (_) {}
      try {
        await zipFile?.delete();
      } catch (_) {}
    }
  }

  Future<File> _extractDbFromZip(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    ArchiveFile? candidate;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name.toLowerCase().endsWith('.db')) {
        candidate = file;
        break;
      }
    }

    if (candidate == null) {
      throw StateError('El ZIP no contiene ningún archivo .db.');
    }

    final filename = path.basename(candidate.name);
    final outPath = path.join(
      _appPaths.tempDirectory,
      'cloud_restore_extracted_${DateTime.now().millisecondsSinceEpoch}_$filename',
    );

    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);

    final data = candidate.content;
    if (data is! List<int>) {
      throw StateError('No se pudo leer el contenido del .db dentro del ZIP.');
    }

    await outFile.writeAsBytes(data, flush: true);
    return outFile;
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
