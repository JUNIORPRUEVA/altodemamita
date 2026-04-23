import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/resilience/app_paths.dart';
import 'professional_backup_settings.dart';

class ProfessionalBackupSettingsRepository {
  ProfessionalBackupSettingsRepository({AppPaths? appPaths, String? filePath})
    : _appPaths = appPaths,
      _filePathOverride = filePath;

  final AppPaths? _appPaths;
  final String? _filePathOverride;

  AppPaths get appPaths => _appPaths ?? AppPaths();

  String get filePath =>
      _filePathOverride ??
      path.join(appPaths.configDirectory, 'professional_backup_settings.json');

  Future<ProfessionalBackupSettings> load() async {
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        final defaults = ProfessionalBackupSettings.defaults();
        await save(defaults);
        return defaults;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        final defaults = ProfessionalBackupSettings.defaults();
        await save(defaults);
        return defaults;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        final defaults = ProfessionalBackupSettings.defaults();
        await save(defaults);
        return defaults;
      }

      return ProfessionalBackupSettings.fromJson(decoded);
    } catch (_) {
      final defaults = ProfessionalBackupSettings.defaults();
      try {
        await save(defaults);
      } catch (_) {
        // Best effort.
      }
      return defaults;
    }
  }

  Future<void> save(ProfessionalBackupSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final tmpPath = '${file.path}.tmp';
    final tmpFile = File(tmpPath);
    final json = jsonEncode(settings.toJson());
    await tmpFile.writeAsString(json, flush: true);

    try {
      await tmpFile.rename(file.path);
    } on FileSystemException {
      await tmpFile.copy(file.path);
      await tmpFile.delete();
    }
  }
}
