import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import 'backup_validator_agent.dart';
import 'database_activity_guard.dart';

class LocalBackupAgent {
  LocalBackupAgent({
    required AppDatabase appDatabase,
    required AppPaths appPaths,
    BackupValidatorAgent? validator,
    DatabaseActivityGuard? activityGuard,
  }) : _appDatabase = appDatabase,
       _appPaths = appPaths,
       _validator = validator ?? const BackupValidatorAgent(),
       _activityGuard = activityGuard ?? const DatabaseActivityGuard();

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final BackupValidatorAgent _validator;
  final DatabaseActivityGuard _activityGuard;

  Directory get localBackupsDirectory =>
      Directory(_appPaths.professionalLocalBackupsDirectory);

  Future<File> createLocalBackup() async {
    final now = DateTime.now();
    final baseFilename = 'backup_local_${_date(now)}_${_time(now)}.db';

    final outputDir = localBackupsDirectory;
    await outputDir.create(recursive: true);

    final outputPath = await _pickAvailablePath(
      outputDir: outputDir,
      preferredFilename: baseFilename,
    );
    final tmpPath = '$outputPath.tmp';

    final sourcePath = await _appDatabase.databasePath;
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw StateError('Base de datos local no encontrada.');
    }

    await _activityGuard.waitForNoActiveWriters(databasePath: sourcePath);

    // Ensure WAL is checkpointed and the DB is closed for a consistent copy.
    try {
      final db = await _appDatabase.database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Best effort.
    }

    await _appDatabase.close();

    try {
      final tmpFile = await sourceFile.copy(tmpPath);
      await _validator.validateSQLiteDbFile(tmpFile);

      try {
        await tmpFile.rename(outputPath);
      } on FileSystemException {
        await tmpFile.copy(outputPath);
        await tmpFile.delete();
      }

      return File(outputPath);
    } finally {
      await _appDatabase.initialize();
    }
  }

  static String _date(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h-$mm-$ss-$ms';
  }

  static Future<String> _pickAvailablePath({
    required Directory outputDir,
    required String preferredFilename,
  }) async {
    final base = preferredFilename.endsWith('.db')
        ? preferredFilename.substring(0, preferredFilename.length - 3)
        : preferredFilename;

    var candidate = path.join(outputDir.path, preferredFilename);
    if (!await File(candidate).exists()) {
      return candidate;
    }

    for (var i = 2; i <= 999; i++) {
      final numbered = '${base}_$i.db';
      candidate = path.join(outputDir.path, numbered);
      if (!await File(candidate).exists()) {
        return candidate;
      }
    }

    throw StateError(
      'No se pudo reservar un nombre de archivo de backup local.',
    );
  }
}
