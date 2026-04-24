import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/services/professional_backup/backup_log_agent.dart';
import 'package:sistema_solares/services/professional_backup/backup_service.dart';
import 'package:sistema_solares/services/professional_backup/backup_validator_agent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Professional backup - rotation and logging', () {
    test('guarda múltiples versiones, no sobreescribe y loggea tamaño/fecha',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'sistema_solares_pro_backup_rotation_',
      );
      final supportDirectory = path.join(tempDirectory.path, 'support');
      final databasePath = path.join(tempDirectory.path, 'data', 'app.db');

      final appDatabase = AppDatabase.test(databasePath);
      final appPaths = AppPaths(supportDirectory: supportDirectory);
      final backupService = BackupService(
        appDatabase: appDatabase,
        appPaths: appPaths,
      );

      try {
        await appDatabase.initialize();

        final backups = <File?>[];
        for (var i = 0; i < 3; i++) {
          backups.add(
            await backupService.createLocalBackup(trigger: BackupTrigger.manual),
          );
        }

        expect(backups.whereType<File>(), hasLength(3));

        final paths = backups.whereType<File>().map((f) => f.path).toSet();
        expect(paths.length, 3, reason: 'Debe crear 3 archivos distintos.');

        final backupsDir = Directory(appPaths.professionalLocalBackupsDirectory);
        expect(await backupsDir.exists(), isTrue);

        final localBackupFiles = (await backupsDir
                .list(followLinks: false)
                .where((e) => e is File)
                .cast<File>()
                .toList())
            .where((f) => path.basename(f.path).startsWith('backup_local_'))
          .where((f) => f.path.toLowerCase().endsWith('.db'))
            .toList();

        expect(localBackupFiles.length, greaterThanOrEqualTo(3));

        // Validate that each backup is a complete/valid SQLite DB.
        final validator = const BackupValidatorAgent();
        for (final file in localBackupFiles) {
          await validator.validateSQLiteDbFile(file);
        }

        // Verify log entries exist with sizeBytes.
        final logAgent = BackupLogAgent(appPaths: appPaths);
        final logFile = File(logAgent.logFilePath);
        expect(await logFile.exists(), isTrue);

        final logText = await logFile.readAsString();
        final okLocalBackupLines = logText
            .split('\n')
            .where((line) =>
                line.contains('| backup | local | ok') &&
                line.contains('sizeBytes='))
            .toList();

        expect(okLocalBackupLines.length, greaterThanOrEqualTo(3));
      } finally {
        await appDatabase.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });
  });
}
