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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_recovery_test_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'reconstruye configuracion minima cuando el archivo esta dañado',
    () async {
      final configPath = path.join(tempDirectory.path, 'config', 'backup.json');
      final historyPath = path.join(
        tempDirectory.path,
        'config',
        'history.json',
      );
      final repository = BackupConfigRepository(
        configPath: configPath,
        backupHistoryPath: historyPath,
      );

      await File(configPath).parent.create(recursive: true);
      await File(configPath).writeAsString('{invalido');

      final repaired = await repository.ensureMinimumConfig();
      final config = await repository.loadConfig();

      expect(repaired, isTrue);
      expect(config.backupPath, isNotEmpty);
      expect(await File(configPath).exists(), isTrue);
    },
  );

  test('prepara una base limpia cuando encuentra un archivo vacio', () async {
    final dbPath = path.join(tempDirectory.path, 'db', 'test.db');
    final configPath = path.join(tempDirectory.path, 'config', 'backup.json');
    final historyPath = path.join(tempDirectory.path, 'config', 'history.json');
    final backupPath = path.join(tempDirectory.path, 'backups');
    final supportPath = path.join(tempDirectory.path, 'support');

    await File(dbPath).parent.create(recursive: true);
    await File(dbPath).writeAsBytes(const []);

    final appDatabase = AppDatabase.test(dbPath);
    addTearDown(() async {
      await appDatabase.close();
    });
    final configRepository = BackupConfigRepository(
      configPath: configPath,
      backupHistoryPath: historyPath,
    );
    await configRepository.saveConfig(BackupConfig.defaults(backupPath));
    await configRepository.ensureReadableHistory();
    final appPaths = AppPaths(supportDirectory: supportPath);
    final backupService = BackupService(
      appDatabase: appDatabase,
      configRepository: configRepository,
      diskDetectionService: DiskDetectionService(),
    );
    final service = StartupRecoveryService(
      appDatabase: appDatabase,
      backupConfigRepository: configRepository,
      backupService: backupService,
      diskDetectionService: DiskDetectionService(),
      incidentLogger: IncidentLogger(appPaths: appPaths),
      appPaths: appPaths,
    );

    final report = await service.prepareApplication();
    final database = await appDatabase.database;
    final missingTables = await DatabaseSchema.missingCriticalTables(database);
    final quarantinedFiles = await Directory(
      path.join(supportPath, 'recovery', 'quarantine'),
    ).list().toList();

    expect(report.status, StartupRecoveryStatus.needsAttention);
    expect(report.canContinue, isTrue);
    expect(report.repairs, isNotEmpty);
    expect(await File(dbPath).exists(), isTrue);
    expect(missingTables, isEmpty);
    expect(quarantinedFiles, isNotEmpty);
  });

  test('no reemplaza una base no vacia cuando el archivo esta corrupto', () async {
    final dbPath = path.join(tempDirectory.path, 'db', 'corrupt.db');
    final configPath = path.join(tempDirectory.path, 'config', 'backup.json');
    final historyPath = path.join(tempDirectory.path, 'config', 'history.json');
    final backupPath = path.join(tempDirectory.path, 'backups');
    final supportPath = path.join(tempDirectory.path, 'support');

    await File(dbPath).parent.create(recursive: true);
    await File(dbPath).writeAsBytes(const [1, 2, 3, 4, 5], flush: true);

    final appDatabase = AppDatabase.test(dbPath);
    addTearDown(() async {
      await appDatabase.close();
    });

    final configRepository = BackupConfigRepository(
      configPath: configPath,
      backupHistoryPath: historyPath,
    );
    await configRepository.saveConfig(BackupConfig.defaults(backupPath));
    await configRepository.ensureReadableHistory();

    final appPaths = AppPaths(supportDirectory: supportPath);
    final service = StartupRecoveryService(
      appDatabase: appDatabase,
      backupConfigRepository: configRepository,
      backupService: BackupService(
        appDatabase: appDatabase,
        configRepository: configRepository,
        diskDetectionService: DiskDetectionService(),
      ),
      diskDetectionService: DiskDetectionService(),
      incidentLogger: IncidentLogger(appPaths: appPaths),
      appPaths: appPaths,
    );

    final report = await service.prepareApplication();
    final snapshots = await Directory(
      path.join(supportPath, 'recovery', 'snapshots'),
    ).list().toList();

    expect(report.status, StartupRecoveryStatus.failed);
    expect(report.canContinue, isFalse);
    expect(await File(dbPath).exists(), isTrue);
    expect(await File(dbPath).length(), 5);
    expect(snapshots, isNotEmpty);
  });
}
