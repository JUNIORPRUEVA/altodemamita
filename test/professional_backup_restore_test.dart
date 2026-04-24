import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/services/professional_backup/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Professional backup restore', () {
    test('restaura la base completa desde un backup local profesional', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'sistema_solares_professional_restore_',
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

        final db = await appDatabase.database;
        final timestamp = DateTime.now().toIso8601String();

        await db.rawInsert(
          'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
          '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
          ['sentinel_professional_restore_key', 'value_before', timestamp],
        );

        final backupFile = await backupService.createLocalBackup(
          trigger: BackupTrigger.manual,
        );
        expect(backupFile, isNotNull);
        expect(await backupFile!.exists(), isTrue);

        await db.rawInsert(
          'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
          '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
          ['sentinel_professional_restore_key', 'value_after', timestamp],
        );

        final restoreResult = await backupService.restoreFromLocalBackup(
          backupPath: backupFile.path,
        );

        expect(restoreResult.success, isTrue);

        await appDatabase.close();
        await appDatabase.initialize();

        final restoredDb = await appDatabase.database;
        final rows = await restoredDb.rawQuery(
          'SELECT valor FROM ${DatabaseSchema.settingsTable} WHERE clave = ?',
          ['sentinel_professional_restore_key'],
        );

        expect(rows, hasLength(1));
        expect(rows.first['valor'], 'value_before');

        final snapshots = await Directory(appPaths.recoveryDirectory)
            .list(recursive: true)
            .where((e) => e is File)
            .cast<File>()
            .toList();

        expect(
          snapshots.any(
            (file) =>
                path.basename(file.path).contains('professional_pre_restore'),
          ),
          isTrue,
        );
      } finally {
        await appDatabase.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });
  });
}
