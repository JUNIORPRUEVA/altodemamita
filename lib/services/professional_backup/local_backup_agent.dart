import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import 'backup_validator_agent.dart';

class LocalBackupAgent {
  LocalBackupAgent({
    required AppDatabase appDatabase,
    required AppPaths appPaths,
    BackupValidatorAgent? validator,
  }) : _appDatabase = appDatabase,
       _appPaths = appPaths,
       _validator = validator ?? const BackupValidatorAgent();

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final BackupValidatorAgent _validator;

  Directory get localBackupsDirectory =>
      Directory(path.join(_appPaths.backupsDirectory, 'local'));

  Future<File> createLocalBackup() async {
    final now = DateTime.now();
    final filename =
        'backup_local_${_date(now)}_${_time(now)}.db';

    final outputDir = localBackupsDirectory;
    await outputDir.create(recursive: true);

    final outputPath = path.join(outputDir.path, filename);
    final tmpPath = '$outputPath.tmp';

    final sourcePath = await _appDatabase.databasePath;
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw StateError('Base de datos local no encontrada en: $sourcePath');
    }

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

      final finalFile = File(outputPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }

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
    return '$h-$mm';
  }
}
