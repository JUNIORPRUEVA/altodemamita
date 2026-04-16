import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/features/backup/data/backup_config_repository.dart';
import 'package:sistema_solares/features/backup/domain/backup_config.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_storage_test_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('migra una base legacy a la ruta persistente central y la reutiliza', () async {
    final supportPath = path.join(tempDirectory.path, 'support');
    final legacyDatabasesPath = path.join(tempDirectory.path, 'legacy_db');
    final legacyDatabasePath = path.join(
      legacyDatabasesPath,
      'sistema_solares.db',
    );

    final legacyDb = AppDatabase.test(legacyDatabasePath);
    addTearDown(() async {
      await legacyDb.close();
    });
    await legacyDb.initialize();

    final legacyClients = ClientRepository(appDatabase: legacyDb);
    await legacyClients.save(
      Client(
        fullName: 'Cliente Migrado',
        documentId: '001-2222222-2',
        phone: '8095550222',
        address: 'Ruta legacy',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await legacyDb.close();

    final appPaths = AppPaths(supportDirectory: supportPath);
    final productionDb = AppDatabase.forStorage(
      appPaths: appPaths,
      legacyDatabaseLocator: (_) async => legacyDatabasePath,
    );
    addTearDown(() async {
      await productionDb.close();
    });

    await productionDb.initialize();
    final productionClients = ClientRepository(appDatabase: productionDb);
    final migrated = await productionClients.fetchAll(query: 'Migrado');

    expect(appPaths.databasePath, contains(path.join('data', 'database')));
    expect(await File(appPaths.databasePath).exists(), isTrue);
    expect(await File(legacyDatabasePath).exists(), isFalse);
    expect(migrated, hasLength(1));

    await productionDb.close();
    await productionDb.initialize();

    final reopenedClients = await ClientRepository(
      appDatabase: productionDb,
    ).fetchAll(query: 'Migrado');
    expect(reopenedClients, hasLength(1));
  });

  test('migra archivos legacy de backup config al directorio persistente', () async {
    final supportPath = path.join(tempDirectory.path, 'support');
    final appPaths = AppPaths(supportDirectory: supportPath);
    final legacyConfigFile = File(appPaths.legacyBackupConfigPath);
    final legacyHistoryFile = File(appPaths.legacyBackupHistoryPath);

    await legacyConfigFile.parent.create(recursive: true);
    await legacyConfigFile.writeAsString(
      '{"backupPath":"C:/persisted/backups","autoBackupEnabled":true,"autoBackupOnStartup":false,"autoBackupOnShutdown":false,"maxBackupRetention":7,"lastBackupPath":null,"lastBackupTimestamp":null}',
      flush: true,
    );
    await legacyHistoryFile.writeAsString('[]', flush: true);

    final repository = BackupConfigRepository(appPaths: appPaths);
    final config = await repository.loadConfig();

    expect(config.backupPath, 'C:/persisted/backups');
    expect(await File(appPaths.backupConfigPath).exists(), isTrue);
    expect(await File(appPaths.backupHistoryPath).exists(), isTrue);
  });

  test('usa una ruta de backup por defecto persistente y separada de la app', () async {
    final appPaths = AppPaths(supportDirectory: path.join(tempDirectory.path, 'support'));
    final repository = BackupConfigRepository(appPaths: appPaths);
    final config = BackupConfig.defaults(appPaths.defaultBackupDirectory);

    await repository.saveConfig(config);
    final loaded = await repository.loadConfig();

    expect(loaded.backupPath, contains('SistemaSolares'));
    expect(loaded.backupPath, isNot(contains(path.join('data', 'database'))));
    expect(loaded.backupPath, isNot(contains('Program Files')));
  });
}