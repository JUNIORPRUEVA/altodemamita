import 'dart:io';

import 'package:path/path.dart' as path;

class AppPaths {
  AppPaths({String? supportDirectory}) : _supportDirectory = supportDirectory;

  static String? _debugDefaultSupportDirectoryOverride;

  static String? get debugDefaultSupportDirectoryOverride =>
      _debugDefaultSupportDirectoryOverride;

  static void debugOverrideDefaultSupportDirectory(String? supportDirectory) {
    _debugDefaultSupportDirectoryOverride = supportDirectory;
  }

  final String? _supportDirectory;

  bool get supportsFileSystem => true;

  bool get _usesInjectedSupportDirectory =>
      _supportDirectory != null ||
      _debugDefaultSupportDirectoryOverride != null;

  late final String supportDirectory =
      _supportDirectory ??
      _debugDefaultSupportDirectoryOverride ??
      _flutterTestSupportDirectory() ??
      path.join(
        Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['APPDATA'] ??
            _fallbackAppData(),
        'SistemaSolares',
      );

  String get legacySupportDirectory => path.join(
    _supportDirectory ??
        _debugDefaultSupportDirectoryOverride ??
        _flutterTestSupportDirectory() ??
        Platform.environment['APPDATA'] ??
        _fallbackAppData(),
    'SistemaSolares',
  );

  String get dataDirectory => path.join(supportDirectory, 'data');
  String get databaseDirectory => path.join(dataDirectory, 'database');
  String get databasePath => path.join(databaseDirectory, 'sistema_solares.db');
  String get dataCacheDirectory => path.join(dataDirectory, 'cache');
  String get dataOutboxDirectory => path.join(dataDirectory, 'outbox');
  String get dataStateDirectory => path.join(dataDirectory, 'state');
  String get cacheDatabasePath => path.join(dataCacheDirectory, 'cache.db');
  String get outboxDatabasePath => path.join(dataOutboxDirectory, 'outbox.db');
  String get deviceStateDatabasePath =>
      path.join(dataStateDirectory, 'device_state.db');
  String get backupsDirectory => path.join(supportDirectory, 'backups');
  String get localBackupsDirectory => path.join(backupsDirectory, 'local');
  String get professionalLocalBackupsDirectory {
    if (_usesInjectedSupportDirectory || _isFlutterTest) {
      return path.join(backupsDirectory, 'local');
    }

    if (Platform.isWindows) {
      const preferredDrive = 'D:\\';
      if (Directory(preferredDrive).existsSync()) {
        return path.join(preferredDrive, 'FULLPOS_BACKUPS');
      }

      return path.join(defaultBackupDirectory, 'FULLPOS_BACKUPS');
    }

    if (Platform.isAndroid) {
      return path.join(backupsDirectory, 'local');
    }

    return path.join(backupsDirectory, 'local');
  }

  String get configDirectory => path.join(supportDirectory, 'config');
  String get logsDirectory => path.join(supportDirectory, 'logs');
  String get syncLogPath => path.join(logsDirectory, 'sync.log');
  String get syncDiagnosticsLogPath =>
      path.join(logsDirectory, 'sync_diagnostics.log');
  String get incidentsDirectory => path.join(logsDirectory, 'incidents');
  String get generatedDirectory => path.join(supportDirectory, 'generated');
  String get mediaDirectory => path.join(supportDirectory, 'media');
  String get tempDirectory => path.join(supportDirectory, 'temp');
  String get cacheDirectory => path.join(supportDirectory, 'cache');
  String get migrationDirectory => path.join(supportDirectory, 'migration');
  String get recoveryDirectory => path.join(supportDirectory, 'recovery');
  String get quarantineDirectory => path.join(recoveryDirectory, 'quarantine');
  String get snapshotsDirectory => path.join(recoveryDirectory, 'snapshots');
  String get backupConfigPath =>
      path.join(configDirectory, 'backup_config.json');
  String get backupHistoryPath =>
      path.join(configDirectory, 'backup_history.json');
  String get legacyBackupConfigPath =>
      path.join(legacySupportDirectory, 'backup_config.json');
  String get legacyBackupHistoryPath =>
      path.join(legacySupportDirectory, 'backup_history.json');

  String get defaultBackupDirectory {
    if (_usesInjectedSupportDirectory || _isFlutterTest) {
      return path.join(
        supportDirectory,
        'Documents',
        'SistemaSolares',
        'Backups',
      );
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return path.join(userProfile, 'Documents', 'SistemaSolares', 'Backups');
    }
    return backupsDirectory;
  }

  Future<void> ensureCriticalDirectories() async {
    for (final directoryPath in [
      supportDirectory,
      dataDirectory,
      databaseDirectory,
      dataCacheDirectory,
      dataOutboxDirectory,
      dataStateDirectory,
      backupsDirectory,
      localBackupsDirectory,
      configDirectory,
      logsDirectory,
      incidentsDirectory,
      generatedDirectory,
      mediaDirectory,
      tempDirectory,
      cacheDirectory,
      migrationDirectory,
      recoveryDirectory,
      quarantineDirectory,
      snapshotsDirectory,
    ]) {
      await Directory(directoryPath).create(recursive: true);
    }
  }

  Future<void> cleanTransientFiles({
    Duration maxAge = const Duration(days: 2),
  }) async {
    final expiration = DateTime.now().subtract(maxAge);

    for (final directoryPath in [tempDirectory, cacheDirectory]) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        continue;
      }

      await for (final entity in directory.list(recursive: true)) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(expiration)) {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          }
        } catch (_) {
          // Best effort cleanup.
        }
      }
    }
  }

  static String _fallbackAppData() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return path.join(userProfile, 'AppData', 'Local');
    }
    return Directory.systemTemp.parent.path;
  }

  static bool get _isFlutterTest =>
      Platform.environment['FLUTTER_TEST'] == 'true' ||
      Platform.environment['DART_TEST'] == 'true';

  static String? _flutterTestSupportDirectory() {
    if (!_isFlutterTest) {
      return null;
    }

    return path.join(
      Directory.systemTemp.path,
      'SistemaSolaresFlutterTests',
      'pid_$pid',
    );
  }
}
