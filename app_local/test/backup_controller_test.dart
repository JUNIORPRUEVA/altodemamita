import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/backup/data/backup_config_repository.dart';
import 'package:sistema_solares/features/backup/domain/backup_config.dart';
import 'package:sistema_solares/features/backup/domain/backup_metadata.dart';
import 'package:sistema_solares/features/backup/domain/disk_info.dart';
import 'package:sistema_solares/features/backup/presentation/backup_controller.dart';
import 'package:sistema_solares/features/backup/services/backup_service.dart';
import 'package:sistema_solares/features/backup/services/disk_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_backup_controller_test_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'initialize no falla si el controller se dispone durante la carga',
    () async {
      final diskService = FakeDiskDetectionService(
        drives: _sampleDrives(),
        accessiblePaths: {r'D:\SistemaSolares\Backups'},
      );
      final backupService = FakeBackupService(
        tempDirectory: tempDirectory,
        config: BackupConfig.defaults(r'C:\SistemaSolares\Backups'),
      );

      final controller = BackupController(
        backupService: backupService,
        diskDetectionService: diskService,
      );

      final initializeFuture = controller.initialize();
      controller.dispose();

      await expectLater(initializeFuture, completes);
    },
  );

  test('initialize redirige backups al disco externo disponible', () async {
    final diskService = FakeDiskDetectionService(
      drives: _sampleDrives(),
      accessiblePaths: {r'D:\SistemaSolares\Backups'},
    );
    final backupService = FakeBackupService(
      tempDirectory: tempDirectory,
      config: BackupConfig.defaults(r'C:\SistemaSolares\Backups'),
    );

    final controller = BackupController(
      backupService: backupService,
      diskDetectionService: diskService,
    );

    await controller.initialize();

    expect(controller.config, isNotNull);
    expect(controller.config!.backupPath, r'D:\SistemaSolares\Backups');
    expect(controller.isUsingExternalBackupPath, isTrue);
    expect(backupService.savedConfigs, isNotEmpty);
    expect(
      backupService.savedConfigs.last.backupPath,
      r'D:\SistemaSolares\Backups',
    );
    expect(controller.statusMessage, contains('fuera del disco del sistema'));
  });

  test('initialize silencioso no publica banners de estado', () async {
    final diskService = FakeDiskDetectionService(
      drives: _sampleDrives(),
      accessiblePaths: {r'D:\SistemaSolares\Backups'},
    );
    final backupService = FakeBackupService(
      tempDirectory: tempDirectory,
      config: BackupConfig.defaults(r'D:\SistemaSolares\Backups'),
    );

    final controller = BackupController(
      backupService: backupService,
      diskDetectionService: diskService,
    );

    await controller.initialize(silent: true);

    expect(controller.hasLoadedInitialState, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.statusMessage, isNull);
    expect(controller.errorMessage, isNull);
    expect(controller.config?.backupPath, r'D:\SistemaSolares\Backups');
  });

  test('crea respaldo silencioso al entrar si el ultimo es antiguo', () async {
    final diskService = FakeDiskDetectionService(
      drives: _sampleDrives(),
      accessiblePaths: {r'D:\SistemaSolares\Backups'},
    );
    final backupService = FakeBackupService(
      tempDirectory: tempDirectory,
      config: BackupConfig(
        backupPath: r'D:\SistemaSolares\Backups',
        autoBackupEnabled: true,
        autoBackupOnStartup: true,
        autoBackupOnShutdown: true,
        maxBackupRetention: 10,
        lastBackupPath: null,
        lastBackupTimestamp: DateTime(2026, 3, 25, 8),
      ),
    );

    final controller = BackupController(
      backupService: backupService,
      diskDetectionService: diskService,
    );

    await controller.initialize(silent: true);
    await controller.createSilentEntryBackupIfNeeded(
      now: DateTime(2026, 3, 28, 9),
    );

    expect(backupService.createdBackupTypes, contains('module_entry'));
    expect(controller.statusMessage, isNull);
    expect(controller.errorMessage, isNull);
    expect(controller.backupHistory, isNotEmpty);
    expect(controller.backupHistory.first.type, 'module_entry');
  });

  test('omite respaldo silencioso si ya hubo uno reciente', () async {
    final diskService = FakeDiskDetectionService(
      drives: _sampleDrives(),
      accessiblePaths: {r'D:\SistemaSolares\Backups'},
    );
    final backupService = FakeBackupService(
      tempDirectory: tempDirectory,
      config: BackupConfig(
        backupPath: r'D:\SistemaSolares\Backups',
        autoBackupEnabled: true,
        autoBackupOnStartup: true,
        autoBackupOnShutdown: true,
        maxBackupRetention: 10,
        lastBackupPath: r'D:\SistemaSolares\Backups\manual\ultimo.db',
        lastBackupTimestamp: DateTime(2026, 3, 28, 8),
      ),
    );

    final controller = BackupController(
      backupService: backupService,
      diskDetectionService: diskService,
    );

    await controller.initialize(silent: true);
    await controller.createSilentEntryBackupIfNeeded(
      now: DateTime(2026, 3, 28, 9),
    );

    expect(backupService.createdBackupTypes, isEmpty);
  });
}

List<DiskInfo> _sampleDrives() {
  return const [
    DiskInfo(
      drive: 'C:',
      label: 'Windows',
      totalSize: 500 * 1024 * 1024 * 1024,
      freeSize: 300 * 1024 * 1024 * 1024,
      isAvailable: true,
      isSystemDrive: true,
    ),
    DiskInfo(
      drive: 'D:',
      label: 'Backups',
      totalSize: 1000 * 1024 * 1024 * 1024,
      freeSize: 800 * 1024 * 1024 * 1024,
      isAvailable: true,
      isSystemDrive: false,
    ),
  ];
}

class FakeDiskDetectionService extends DiskDetectionService {
  FakeDiskDetectionService({
    required this.drives,
    required Set<String> accessiblePaths,
  }) : _accessiblePaths = accessiblePaths;

  final List<DiskInfo> drives;
  final Set<String> _accessiblePaths;

  @override
  String getSystemDrive() => 'C:';

  @override
  Future<List<DiskInfo>> detectAvailableDrives() async => drives;

  @override
  Future<DiskInfo?> getPrimaryDrive(List<DiskInfo> drives) async {
    for (final drive in drives) {
      if (drive.isSystemDrive) {
        return drive;
      }
    }
    return drives.isEmpty ? null : drives.first;
  }

  @override
  Future<DiskInfo?> getSecondaryDrive(List<DiskInfo> drives) async {
    for (final drive in drives) {
      if (!drive.isSystemDrive && drive.isAvailable && drive.hasEnoughSpace) {
        return drive;
      }
    }
    return null;
  }

  @override
  Future<bool> canAccessBackupPath(String path) async {
    if (_accessiblePaths.contains(path)) {
      return true;
    }

    final drive = extractDriveLetter(path);
    return drives.any((item) => item.drive == drive && item.isAvailable);
  }

  @override
  Future<bool> createBackupDirectory(String path) async {
    _accessiblePaths.add(path);
    return true;
  }

  @override
  Future<bool> openInFileExplorer(String path) async => true;
}

class FakeBackupService extends BackupService {
  FakeBackupService({
    required Directory tempDirectory,
    required BackupConfig config,
    List<BackupMetadata> history = const [],
  }) : _config = config,
       _history = List<BackupMetadata>.of(history),
       super(
         appDatabase: AppDatabase.test(
           path.join(tempDirectory.path, 'db', 'test.db'),
         ),
         configRepository: BackupConfigRepository(
           configPath: path.join(tempDirectory.path, 'config', 'backup.json'),
           backupHistoryPath: path.join(
             tempDirectory.path,
             'config',
             'history.json',
           ),
         ),
         diskDetectionService: DiskDetectionService(),
       );

  BackupConfig _config;
  final List<BackupMetadata> _history;
  final List<BackupConfig> savedConfigs = [];
  final List<String> createdBackupTypes = [];

  @override
  Future<BackupConfig> getConfig() async => _config;

  @override
  Future<List<BackupMetadata>> getAllBackups() async => _history;

  @override
  Future<void> updateConfig(BackupConfig config) async {
    _config = config;
    savedConfigs.add(config);
  }

  @override
  Future<BackupResult> createBackup({required String backupType}) async {
    createdBackupTypes.add(backupType);
    final metadata = BackupMetadata(
      id: 'backup-${createdBackupTypes.length}',
      filename: '$backupType.db',
      filepath: path.join(_config.backupPath, backupType, '$backupType.db'),
      timestamp: DateTime.now(),
      type: backupType,
      sizeBytes: 1024,
      databaseSize: 1024,
      success: true,
    );
    _history.insert(0, metadata);
    _config = _config.copyWith(
      lastBackupPath: metadata.filepath,
      lastBackupTimestamp: metadata.timestamp,
    );
    savedConfigs.add(_config);

    return BackupResult(
      success: true,
      sourcePath: path.join(_config.backupPath, 'source.db'),
      backupPath: metadata.filepath,
      metadata: metadata,
    );
  }
}
