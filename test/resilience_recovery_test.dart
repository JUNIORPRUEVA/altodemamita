import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/core/resilience/incident_logger.dart';
import 'package:sistema_solares/core/resilience/startup_recovery_service.dart';
import 'package:sistema_solares/features/backup/data/backup_config_repository.dart';
import 'package:sistema_solares/features/backup/domain/backup_config.dart';
import 'package:sistema_solares/features/backup/services/backup_service.dart';
import 'package:sistema_solares/features/backup/services/disk_detection_service.dart';

class _FakeDiskDetectionService extends DiskDetectionService {
  @override
  Future<bool> isPathAvailable(String pathValue) async {
    return Directory(pathValue).exists();
  }

  @override
  Future<bool> createBackupDirectory(String pathValue) async {
    await Directory(pathValue).create(recursive: true);
    return true;
  }
}

void main() {
  group('Resilience and recovery', () {
    test(
      'startup recovery repairs config and history, quarantines empty database, and keeps backup restore as last resort',
      () async {
        final tempDirectory = await Directory.systemTemp.createTemp(
          'sistema_solares_resilience_startup_',
        );
        final supportDirectory = path.join(tempDirectory.path, 'support');
        final databasePath = path.join(tempDirectory.path, 'data', 'app.db');
        final configRepository = BackupConfigRepository(
          configPath: path.join(supportDirectory, 'backup_config.json'),
          backupHistoryPath: path.join(supportDirectory, 'backup_history.json'),
        );
        final appDatabase = AppDatabase.test(databasePath);
        final appPaths = AppPaths(supportDirectory: supportDirectory);
        final diskDetectionService = _FakeDiskDetectionService();
        final backupService = BackupService(
          appDatabase: appDatabase,
          configRepository: configRepository,
          diskDetectionService: diskDetectionService,
        );
        final startupRecoveryService = StartupRecoveryService(
          appDatabase: appDatabase,
          backupConfigRepository: configRepository,
          backupService: backupService,
          diskDetectionService: diskDetectionService,
          incidentLogger: IncidentLogger(appPaths: appPaths),
          appPaths: appPaths,
        );

        try {
          await Directory(supportDirectory).create(recursive: true);
          await Directory(path.dirname(databasePath)).create(recursive: true);
          await File(configRepository.configPath).writeAsString('{broken');
          await File(configRepository.backupHistoryPath).writeAsString('{broken');
          await File(databasePath).writeAsBytes(const []);

          final report = await startupRecoveryService.prepareApplication();

          expect(report.status, StartupRecoveryStatus.needsAttention);
          expect(report.canContinue, isTrue);
          expect(report.allowBackupRestore, isFalse);
          expect(
            report.repairs.any(
              (item) => item.contains('configuracion minima del sistema'),
            ),
            isTrue,
          );
          expect(
            report.repairs.any(
              (item) => item.contains('historial local de copias'),
            ),
            isTrue,
          );
          expect(
            report.repairs.any(
              (item) => item.contains('base de datos vacio'),
            ),
            isTrue,
          );

          final quarantinedEntries = await Directory(
            appPaths.quarantineDirectory,
          ).list().toList();
          expect(quarantinedEntries.whereType<File>(), isNotEmpty);

          final db = await appDatabase.database;
          expect(await DatabaseSchema.missingCriticalTables(db), isEmpty);
        } finally {
          await appDatabase.close();
          if (await tempDirectory.exists()) {
            await tempDirectory.delete(recursive: true);
          }
        }
      },
    );

    test(
      'backup restore rolls back to the previous state when the selected backup is invalid',
      () async {
        final tempDirectory = await Directory.systemTemp.createTemp(
          'sistema_solares_resilience_restore_',
        );
        final supportDirectory = path.join(tempDirectory.path, 'support');
        final databasePath = path.join(tempDirectory.path, 'data', 'app.db');
        final backupPath = path.join(tempDirectory.path, 'backups');
        final invalidBackupPath = path.join(
          tempDirectory.path,
          'incoming',
          'invalid_restore.db',
        );
        final configRepository = BackupConfigRepository(
          configPath: path.join(supportDirectory, 'backup_config.json'),
          backupHistoryPath: path.join(supportDirectory, 'backup_history.json'),
        );
        final appDatabase = AppDatabase.test(databasePath);
        final backupService = BackupService(
          appDatabase: appDatabase,
          configRepository: configRepository,
          diskDetectionService: _FakeDiskDetectionService(),
        );

        try {
          await configRepository.saveConfig(BackupConfig.defaults(backupPath));
          await appDatabase.initialize();

          final db = await appDatabase.database;
          final timestamp = DateTime.now().toIso8601String();
          await db.rawInsert(
            'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
            '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
            ['sentinel_restore_key', 'still_here', timestamp],
          );

          final invalidBackupFile = File(invalidBackupPath);
          await invalidBackupFile.parent.create(recursive: true);
          await invalidBackupFile.writeAsString('this is not a sqlite database');

          final result = await backupService.restoreFromBackup(
            backupPath: invalidBackupFile.path,
          );

          expect(result.success, isFalse);

          await appDatabase.close();
          await appDatabase.initialize();

          final restoredDb = await appDatabase.database;
          final rows = await restoredDb.rawQuery(
            'SELECT valor FROM ${DatabaseSchema.settingsTable} WHERE clave = ?',
            ['sentinel_restore_key'],
          );

          expect(rows, hasLength(1));
          expect(rows.first['valor'], 'still_here');

          final history = await configRepository.loadBackupHistory();
          expect(
            history.any((backup) => backup.type == 'pre_restore' && backup.success),
            isTrue,
          );
        } finally {
          await appDatabase.close();
          if (await tempDirectory.exists()) {
            await tempDirectory.delete(recursive: true);
          }
        }
      },
    );
  });
}