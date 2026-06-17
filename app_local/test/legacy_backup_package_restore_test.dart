import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/features/backup/data/backup_config_repository.dart';
import 'package:sistema_solares/features/backup/domain/backup_config.dart';
import 'package:sistema_solares/features/backup/services/backup_service.dart';
import 'package:sistema_solares/features/backup/services/disk_detection_service.dart';
import 'package:sistema_solares/services/professional_backup/backup_log_agent.dart';

class _TestExternalDiskService extends DiskDetectionService {
  @override
  bool isPathOnSystemDrive(String pathValue) {
    // In tests we treat the temp directory as “external” to avoid
    // depending on real physical secondary drives.
    return false;
  }

  @override
  Future<bool> canAccessBackupPath(String pathValue) async {
    final trimmed = pathValue.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return Directory(trimmed).exists();
  }

  @override
  Future<bool> createBackupDirectory(String pathValue) async {
    await Directory(pathValue).create(recursive: true);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legacy external backup - full ZIP package', () {
    test('creates a ZIP package (db+config+generated) and restores fully',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'sistema_solares_legacy_zip_restore_',
      );
      final supportDirectory = path.join(tempDirectory.path, 'support');
      final databasePath = path.join(tempDirectory.path, 'data', 'app.db');
      final externalBackupPath = path.join(tempDirectory.path, 'external_backups');

      final appDatabase = AppDatabase.test(databasePath);
      final appPaths = AppPaths(supportDirectory: supportDirectory);
      final configRepository = BackupConfigRepository(
        configPath: path.join(supportDirectory, 'backup_config.json'),
        backupHistoryPath: path.join(supportDirectory, 'backup_history.json'),
      );

      final backupService = BackupService(
        appDatabase: appDatabase,
        configRepository: configRepository,
        diskDetectionService: _TestExternalDiskService(),
        appPaths: appPaths,
        logAgent: BackupLogAgent(appPaths: appPaths),
      );

      try {
        await appPaths.ensureCriticalDirectories();
        await Directory(externalBackupPath).create(recursive: true);
        await configRepository.saveConfig(BackupConfig.defaults(externalBackupPath));

        await appDatabase.initialize();

        // Seed DB state.
        final db = await appDatabase.database;
        final timestamp = DateTime.now().toIso8601String();
        await db.rawInsert(
          'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
          '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
          ['sentinel_legacy_zip_key', 'value_before', timestamp],
        );

        // Seed files under support/config and support/generated.
        final configFile = File(path.join(appPaths.configDirectory, 'test_config.json'));
        await configFile.parent.create(recursive: true);
        await configFile.writeAsString('{"k":"before"}', flush: true);

        final generatedFile = File(
          path.join(appPaths.generatedDirectory, 'test_generated.txt'),
        );
        await generatedFile.parent.create(recursive: true);
        await generatedFile.writeAsString('before', flush: true);

        // Create ZIP backup.
        final backupResult = await backupService.createBackup(backupType: 'manual');
        expect(backupResult.success, isTrue);
        expect(backupResult.backupPath.toLowerCase().endsWith('.zip'), isTrue);
        expect(await File(backupResult.backupPath).exists(), isTrue);

        // Mutate state after backup.
        final dbAfterBackup = await appDatabase.database;
        await dbAfterBackup.rawInsert(
          'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
          '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
          ['sentinel_legacy_zip_key', 'value_after', timestamp],
        );
        await configFile.writeAsString('{"k":"after"}', flush: true);
        await generatedFile.writeAsString('after', flush: true);

        // Simulate loss.
        await appDatabase.close();
        final dbFile = File(databasePath);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
        for (final suffix in ['-wal', '-shm', '-journal']) {
          final sidecar = File('$databasePath$suffix');
          if (await sidecar.exists()) {
            await sidecar.delete();
          }
        }
        if (await configFile.exists()) {
          await configFile.delete();
        }
        if (await generatedFile.exists()) {
          await generatedFile.delete();
        }

        // Restore from ZIP.
        final restoreResult = await backupService.restoreFromBackup(
          backupPath: backupResult.backupPath,
        );
        expect(restoreResult.success, isTrue);

        // Validate DB restored to backup state.
        await appDatabase.close();
        await appDatabase.initialize();
        final restoredDb = await appDatabase.database;
        final rows = await restoredDb.rawQuery(
          'SELECT valor FROM ${DatabaseSchema.settingsTable} WHERE clave = ?',
          ['sentinel_legacy_zip_key'],
        );
        expect(rows, hasLength(1));
        expect(rows.first['valor'], 'value_before');

        // Validate files restored.
        expect(await configFile.exists(), isTrue);
        expect(await configFile.readAsString(), '{"k":"before"}');
        expect(await generatedFile.exists(), isTrue);
        expect(await generatedFile.readAsString(), 'before');

        // Validate logging contains backup + restore for legacy.
        final logAgent = BackupLogAgent(appPaths: appPaths);
        final logFile = File(logAgent.logFilePath);
        expect(await logFile.exists(), isTrue);
        final logText = await logFile.readAsString();
        expect(logText.contains('| backup | legacy_external | ok'), isTrue);
        expect(logText.contains('| restore | legacy_external | ok'), isTrue);
      } finally {
        await appDatabase.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });
  });
}
