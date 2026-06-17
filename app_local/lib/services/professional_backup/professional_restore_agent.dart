import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import '../../core/resilience/app_paths.dart';
import 'backup_validator_agent.dart';

class ProfessionalRestoreResult {
  const ProfessionalRestoreResult({
    required this.success,
    required this.preRestoreSnapshotPath,
    this.errorMessage,
  });

  final bool success;
  final String? preRestoreSnapshotPath;
  final String? errorMessage;
}

class ProfessionalRestoreAgent {
  ProfessionalRestoreAgent({
    required AppDatabase appDatabase,
    required AppPaths appPaths,
    BackupValidatorAgent? validator,
  }) : _appDatabase = appDatabase,
       _appPaths = appPaths,
       _validator = validator ?? const BackupValidatorAgent();

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final BackupValidatorAgent _validator;

  Future<ProfessionalRestoreResult> restoreFromLocalBackup({
    required String backupPath,
  }) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      return const ProfessionalRestoreResult(
        success: false,
        preRestoreSnapshotPath: null,
        errorMessage: 'Archivo de backup no encontrado.',
      );
    }

    try {
      print('[PRO-RESTORE] Iniciando restauración desde backup profesional');
      print('[PRO-RESTORE] Backup: ${path.basename(backupPath)}');

      await _validator.validateSQLiteDbFile(backupFile);

      final databasePath = await _appDatabase.databasePath;
      final databaseFile = File(databasePath);

      await _appPaths.ensureCriticalDirectories();

      String? preRestoreSnapshotPath;
      if (await databaseFile.exists() && await databaseFile.length() > 0) {
        preRestoreSnapshotPath = await _createPreRestoreSnapshot(databasePath);
        print(
          '[PRO-RESTORE] Snapshot pre-restore creado: ${path.basename(preRestoreSnapshotPath)}',
        );
      } else {
        print(
          '[PRO-RESTORE] No hay estado local utilizable para snapshot pre-restore.',
        );
      }

      print('[PRO-RESTORE] Cerrando base de datos...');
      await _appDatabase.close();

      try {
        await _clearTransientDatabaseSidecars(databasePath);

        final tmpRestorePath = '$databasePath.restore.tmp';
        final tmpRestoreFile = File(tmpRestorePath);

        if (await tmpRestoreFile.exists()) {
          try {
            await tmpRestoreFile.delete();
          } catch (_) {
            // Best effort.
          }
        }

        await backupFile.copy(tmpRestorePath);

        if (await databaseFile.exists()) {
          await databaseFile.delete();
        }

        try {
          await tmpRestoreFile.rename(databasePath);
        } on FileSystemException {
          await tmpRestoreFile.copy(databasePath);
          await tmpRestoreFile.delete();
        }

        print('[PRO-RESTORE] Inicializando base de datos restaurada...');
        await _appDatabase.initialize();

        final db = await _appDatabase.database;
        final rows = await db.rawQuery('PRAGMA quick_check(1)');
        final first = rows.isNotEmpty ? rows.first.values.first : null;
        final normalized = first?.toString().trim().toLowerCase() ?? '';
        if (normalized != 'ok') {
          throw StateError('La base restaurada no pasó quick_check(1).');
        }

        await _validateRestoredData(db);

        print('[PRO-RESTORE] Restauración completada y validada: OK');
        return ProfessionalRestoreResult(
          success: true,
          preRestoreSnapshotPath: preRestoreSnapshotPath,
        );
      } catch (e) {
        print('[PRO-RESTORE] Restauración falló: $e');

        // Best-effort rollback to the pre-restore snapshot.
        if (preRestoreSnapshotPath != null) {
          try {
            print('[PRO-RESTORE] Intentando rollback al snapshot pre-restore...');
            await _appDatabase.close();
            await _clearTransientDatabaseSidecars(databasePath);

            final snapshotFile = File(preRestoreSnapshotPath);
            if (await snapshotFile.exists()) {
              if (await databaseFile.exists()) {
                await databaseFile.delete();
              }
              await snapshotFile.copy(databasePath);
              await _appDatabase.initialize();
              print('[PRO-RESTORE] Rollback completado.');
            }
          } catch (rollbackError) {
            print('[PRO-RESTORE] Rollback falló: $rollbackError');
          }
        }

        return ProfessionalRestoreResult(
          success: false,
          preRestoreSnapshotPath: preRestoreSnapshotPath,
          errorMessage: 'No se pudo restaurar la base desde el backup.',
        );
      }
    } catch (e) {
      return const ProfessionalRestoreResult(
        success: false,
        preRestoreSnapshotPath: null,
        errorMessage: 'Backup inválido o no verificable.',
      );
    }
  }

  Future<String> _createPreRestoreSnapshot(String databasePath) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final basename = path.basenameWithoutExtension(databasePath);
    final extension = path.extension(databasePath);
    final target = path.join(
      _appPaths.recoveryDirectory,
      '${basename}_professional_pre_restore_$timestamp$extension',
    );

    await File(databasePath).copy(target);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) {
        await sidecar.copy('$target$suffix');
      }
    }

    return target;
  }

  Future<void> _clearTransientDatabaseSidecars(String databasePath) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) {
        try {
          await sidecar.delete();
        } catch (_) {
          // Best effort.
        }
      }
    }
  }

  Future<void> _validateRestoredData(Database db) async {
    // 1) Verify critical tables exist.
    final missing = await DatabaseSchema.missingCriticalTables(db);
    if (missing.isNotEmpty) {
      throw StateError('Faltan tablas críticas tras restore: ${missing.join(', ')}');
    }

    // 2) Verify essential records exist.
    // Settings should always have defaults.
    final settingsCount = await _count(db, DatabaseSchema.settingsTable);
    if (settingsCount <= 0) {
      throw StateError('La tabla configuracion está vacía tras restore.');
    }

    // Users should have at least one row (admin bootstrap).
    final usersCount = await _count(db, DatabaseSchema.usersTable);
    if (usersCount <= 0) {
      throw StateError('La tabla usuarios está vacía tras restore.');
    }
  }

  Future<int> _count(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
