import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import '../domain/backup_info.dart';

class BackupRepository {
  const BackupRepository(this.database);

  final Database database;

  // === Backup Info ===
  Future<List<BackupInfo>> getAllBackups() async {
    try {
      final maps = await database.query(
        DatabaseSchema.backupInfoTable,
        orderBy: 'fecha_creacion DESC',
      );
      return maps.map((map) => BackupInfo.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<BackupInfo?> getLastBackup() async {
    try {
      final maps = await database.query(
        DatabaseSchema.backupInfoTable,
        orderBy: 'fecha_creacion DESC',
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return BackupInfo.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  Future<BackupInfo> saveBackup(BackupInfo backup) async {
    SystemConfigService.instance.ensureWritable();

    final id = await database.insert(
      DatabaseSchema.backupInfoTable,
      backup.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return backup.copyWith(id: id);
  }

  Future<void> deleteBackup(int id) async {
    SystemConfigService.instance.ensureWritable();

    await database.delete(
      DatabaseSchema.backupInfoTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteBackupByFileName(String fileName) async {
    SystemConfigService.instance.ensureWritable();

    await database.delete(
      DatabaseSchema.backupInfoTable,
      where: 'nombre_archivo = ?',
      whereArgs: [fileName],
    );
  }

  // === Backup Preferences ===
  Future<BackupPreferences> getBackupPreferences() async {
    try {
      final maps = await database.query(
        DatabaseSchema.backupPreferencesTable,
        limit: 1,
      );

      if (maps.isEmpty) {
        if (!SystemConfigService.instance.isReadOnly) {
          await _initializePreferences();
        }
        return BackupPreferences.defaults();
      }

      return BackupPreferences.fromMap(maps.first);
    } catch (e) {
      return BackupPreferences.defaults();
    }
  }

  Future<void> saveBackupPreferences(BackupPreferences prefs) async {
    SystemConfigService.instance.ensureWritable();

    final existing = await getBackupPreferences();

    if (existing.id != null) {
      await database.update(
        DatabaseSchema.backupPreferencesTable,
        prefs.toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    } else {
      await database.insert(
        DatabaseSchema.backupPreferencesTable,
        prefs.toMap(),
      );
    }
  }

  Future<void> updateLastBackupDate(DateTime date) async {
    final prefs = await getBackupPreferences();
    await saveBackupPreferences(prefs.copyWith(ultimaFechaBackup: date));
  }

  Future<void> toggleAutoBackup(bool enabled) async {
    final prefs = await getBackupPreferences();
    await saveBackupPreferences(prefs.copyWith(autoBackupEnabled: enabled));
  }

  Future<void> updateAutoBackupInterval(int days) async {
    final prefs = await getBackupPreferences();
    await saveBackupPreferences(prefs.copyWith(autoBackupIntervalDays: days));
  }

  Future<void> _initializePreferences() async {
    final defaults = BackupPreferences.defaults();
    await database.insert(
      DatabaseSchema.backupPreferencesTable,
      defaults.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
