import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/services/professional_backup/backup_restore_service.dart';
import 'package:sistema_solares/services/professional_backup/local_backup_agent.dart';
import 'package:test/test.dart';

void main() {
  group('Professional backup restore (end-to-end)', () {
    test('crea backup local y restaura a una DB borrada', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'sistema_solares_cloud_restore_e2e_',
      );
      final supportDirectory = path.join(tempDirectory.path, 'support');
      final databasePath = path.join(tempDirectory.path, 'data', 'app.db');

      final appDatabase = AppDatabase.test(databasePath);
      final appPaths = AppPaths(supportDirectory: supportDirectory);

      try {
        await appDatabase.initialize();
        final db = await appDatabase.database;

        const sentinelKey = 'sentinel_professional_cloud_restore_key';
        final now = DateTime.now().toIso8601String();
        await db.rawInsert(
          'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
          '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
          [sentinelKey, 'from_cloud', now],
        );

        // Close the DB before packaging it to ensure a consistent snapshot.
        await appDatabase.close();

        final dbFileForZip = File(databasePath);
        expect(await dbFileForZip.exists(), isTrue);
        expect(await dbFileForZip.length(), greaterThan(0));

        final localAgent = LocalBackupAgent(
          appDatabase: appDatabase,
          appPaths: appPaths,
        );

        final backupFile = await localAgent.createLocalBackup();
        expect(await backupFile.exists(), isTrue);
        expect(await backupFile.length(), greaterThan(0));

        // Ensure the DB file is not locked on Windows before deleting it.
        await appDatabase.close();

        // Simulate catastrophic local loss.
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

        final restoreService = BackupRestoreService(
          appDatabase: appDatabase,
          appPaths: appPaths,
        );

        final result = await restoreService.restoreLocalBackup(
          backupPath: backupFile.path,
        );
        expect(result.success, isTrue);

        await appDatabase.close();
        await appDatabase.initialize();

        final restoredDb = await appDatabase.database;
        final rows = await restoredDb.rawQuery(
          'SELECT valor FROM ${DatabaseSchema.settingsTable} WHERE clave = ?',
          [sentinelKey],
        );

        expect(rows, hasLength(1));
        expect(rows.first['valor'], 'from_cloud');
      } finally {
        await appDatabase.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });
  });
}
