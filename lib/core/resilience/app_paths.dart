import 'dart:io';

import 'package:path/path.dart' as path;

class AppPaths {
  AppPaths({String? supportDirectory}) : _supportDirectory = supportDirectory;

  final String? _supportDirectory;

  late final String supportDirectory =
      _supportDirectory ??
      path.join(
        Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['APPDATA'] ??
            _fallbackAppData(),
        'SistemaSolares',
      );

  String get legacySupportDirectory => path.join(
    Platform.environment['APPDATA'] ?? _fallbackAppData(),
    'SistemaSolares',
  );

  String get dataDirectory => path.join(supportDirectory, 'data');
  String get databaseDirectory => path.join(dataDirectory, 'database');
  String get databasePath => path.join(databaseDirectory, 'sistema_solares.db');
  String get backupsDirectory => path.join(supportDirectory, 'backups');
  String get professionalLocalBackupsDirectory {
    if (_supportDirectory != null) {
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
  String get incidentsDirectory => path.join(logsDirectory, 'incidents');
  String get generatedDirectory => path.join(supportDirectory, 'generated');
  String get mediaDirectory => path.join(supportDirectory, 'media');
  String get tempDirectory => path.join(supportDirectory, 'temp');
  String get cacheDirectory => path.join(supportDirectory, 'cache');
  String get recoveryDirectory => path.join(supportDirectory, 'recovery');
  String get quarantineDirectory => path.join(recoveryDirectory, 'quarantine');
  String get snapshotsDirectory => path.join(recoveryDirectory, 'snapshots');
  String get backupConfigPath => path.join(configDirectory, 'backup_config.json');
  String get backupHistoryPath => path.join(
    configDirectory,
    'backup_history.json',
  );
  String get legacyBackupConfigPath => path.join(
    legacySupportDirectory,
    'backup_config.json',
  );
  String get legacyBackupHistoryPath => path.join(
    legacySupportDirectory,
    'backup_history.json',
  );

  String get defaultBackupDirectory {
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
      backupsDirectory,
      configDirectory,
      logsDirectory,
      incidentsDirectory,
      generatedDirectory,
      mediaDirectory,
      tempDirectory,
      cacheDirectory,
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
}
