import 'dart:convert';
import 'dart:io';

import '../../../core/resilience/app_paths.dart';
import '../domain/backup_config.dart';
import '../domain/backup_metadata.dart';

class BackupConfigRepository {
  BackupConfigRepository({
    String? configPath,
    String? backupHistoryPath,
    AppPaths? appPaths,
  })
    : _configPath = configPath,
      _backupHistoryPathOverride = backupHistoryPath,
      _appPaths = appPaths;

  final String? _configPath;
  final String? _backupHistoryPathOverride;
  final AppPaths? _appPaths;

  AppPaths get appPaths => _appPaths ?? AppPaths();

  late final String _fullConfigPath =
      _configPath ?? appPaths.backupConfigPath;

  late final String _backupHistoryPath =
      _backupHistoryPathOverride ?? appPaths.backupHistoryPath;

  String get configPath => _fullConfigPath;
  String get backupHistoryPath => _backupHistoryPath;

  /// Initialize config directory
  Future<void> initialize() async {
    await _migrateLegacyFilesIfNeeded();
    final configFile = File(_fullConfigPath);
    if (!await configFile.parent.exists()) {
      await configFile.parent.create(recursive: true);
    }

    if (!await configFile.exists()) {
      final defaultConfig = BackupConfig.defaults(_getDefaultBackupPath());
      await saveConfig(defaultConfig);
    }
  }

  Future<bool> ensureMinimumConfig() async {
    await _migrateLegacyFilesIfNeeded();
    final configFile = File(_fullConfigPath);

    try {
      if (!await configFile.parent.exists()) {
        await configFile.parent.create(recursive: true);
      }

      if (!await configFile.exists()) {
        await saveConfig(BackupConfig.defaults(_getDefaultBackupPath()));
        return true;
      }

      final content = await configFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      BackupConfig.fromJson(decoded);
      return false;
    } catch (e) {
      print('Error repairing backup config: $e');
      await saveConfig(BackupConfig.defaults(_getDefaultBackupPath()));
      return true;
    }
  }

  Future<bool> ensureReadableHistory() async {
    await _migrateLegacyFilesIfNeeded();
    final historyFile = File(_backupHistoryPath);

    try {
      if (!await historyFile.parent.exists()) {
        await historyFile.parent.create(recursive: true);
      }

      if (!await historyFile.exists()) {
        await historyFile.writeAsString('[]');
        return true;
      }

      final content = await historyFile.readAsString();
      if (content.trim().isEmpty) {
        await historyFile.writeAsString('[]');
        return true;
      }

      final decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) {
        await historyFile.writeAsString('[]');
        return true;
      }

      return false;
    } catch (e) {
      print('Error repairing backup history: $e');
      await historyFile.writeAsString('[]');
      return true;
    }
  }

  /// Load configuration from file
  Future<BackupConfig> loadConfig() async {
    try {
      await _migrateLegacyFilesIfNeeded();
      final configFile = File(_fullConfigPath);

      if (!await configFile.exists()) {
        await initialize();
      }

      final content = await configFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      return BackupConfig.fromJson(json);
    } catch (e) {
      print('Error loading backup config: $e');
      return BackupConfig.defaults(_getDefaultBackupPath());
    }
  }

  /// Save configuration to file
  Future<void> saveConfig(BackupConfig config) async {
    final configFile = File(_fullConfigPath);

    if (!await configFile.parent.exists()) {
      await configFile.parent.create(recursive: true);
    }

    final json = jsonEncode(config.toJson());
    await _atomicWrite(configFile, json);
  }

  /// Load backup history
  Future<List<BackupMetadata>> loadBackupHistory() async {
    try {
      await _migrateLegacyFilesIfNeeded();
      final historyFile = File(_backupHistoryPath);

      if (!await historyFile.exists()) {
        return [];
      }

      final content = await historyFile.readAsString();
      final jsonList = jsonDecode(content) as List<dynamic>;

      return jsonList
          .map((item) => BackupMetadata.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading backup history: $e');
      return [];
    }
  }

  /// Save backup history
  Future<void> saveBackupHistory(List<BackupMetadata> backups) async {
    final historyFile = File(_backupHistoryPath);

    if (!await historyFile.parent.exists()) {
      await historyFile.parent.create(recursive: true);
    }

    final jsonList = backups.map((b) => b.toJson()).toList();
    final json = jsonEncode(jsonList);
    await _atomicWrite(historyFile, json);
  }

  /// Add backup entry to history
  Future<void> addBackupEntry(BackupMetadata backup) async {
    try {
      final history = await loadBackupHistory();
      history.insert(0, backup); // Insert at the beginning
      await saveBackupHistory(history);
    } catch (e) {
      print('Error adding backup entry: $e');
    }
  }

  /// Get default backup path
  String _getDefaultBackupPath() {
    return appPaths.defaultBackupDirectory;
  }

  Future<void> _migrateLegacyFilesIfNeeded() async {
    await _migrateLegacyFile(
      legacyPath: appPaths.legacyBackupConfigPath,
      targetPath: _fullConfigPath,
    );
    await _migrateLegacyFile(
      legacyPath: appPaths.legacyBackupHistoryPath,
      targetPath: _backupHistoryPath,
    );
  }

  Future<void> _migrateLegacyFile({
    required String legacyPath,
    required String targetPath,
  }) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      return;
    }

    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      return;
    }

    await targetFile.parent.create(recursive: true);
    try {
      await legacyFile.rename(targetPath);
    } on FileSystemException {
      await legacyFile.copy(targetPath);
      await legacyFile.delete();
    }
  }

  Future<void> _atomicWrite(File targetFile, String contents) async {
    final tempFile = File('${targetFile.path}.tmp');
    final backupFile = File('${targetFile.path}.bak');
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsString(contents, flush: true);

    final targetExists = await targetFile.exists();
    if (targetExists) {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      await targetFile.rename(backupFile.path);
    }

    try {
      await tempFile.rename(targetFile.path);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (await backupFile.exists()) {
        await backupFile.rename(targetFile.path);
      }
      rethrow;
    }
  }
}
