import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/resilience/app_paths.dart';

class SyncLogger {
  SyncLogger({AppPaths? appPaths}) : _appPaths = appPaths ?? AppPaths();

  static final SyncLogger instance = SyncLogger();

  final AppPaths _appPaths;

  /// Cap de tamaño de `sync.log`.
  ///
  /// El realtime poll llegaba a registrar un evento cada ~2 s aunque no hubiera
  /// cambios, lo que produjo un `sync.log` de ~282 MB. Ahora se rota igual que
  /// cualquier log de producción: se conserva evidencia reciente y el disco no
  /// crece sin límite.
  static const int maxLogBytes = 8 * 1024 * 1024;
  static const int maxRotatedFiles = 2;

  Future<void> log({
    required String action,
    required String entity,
    required String result,
    String? error,
    Map<String, Object?> extra = const {},
  }) async {
    // En el navegador no hay archivo de log en disco.
    if (!_appPaths.supportsFileSystem) {
      return;
    }
    await _appPaths.ensureCriticalDirectories();
    final file = File(path.join(_appPaths.logsDirectory, 'sync.log'));
    await _rotateIfNeeded(file);
    final payload = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'entity': entity,
      'result': result,
      'error': error,
      'extra': extra,
    };
    await file.writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append);
  }

  /// Rota `sync.log` -> `sync.log.1` -> `sync.log.2` cuando supera el cap.
  ///
  /// Nunca lanza: un fallo de rotación no debe romper la sincronización.
  Future<void> _rotateIfNeeded(File file) async {
    try {
      if (!await file.exists()) {
        return;
      }
      final length = await file.length();
      if (length < maxLogBytes) {
        return;
      }
      final directory = file.parent.path;
      for (var index = maxRotatedFiles; index >= 1; index--) {
        final source = File(
          path.join(
            directory,
            index == 1 ? 'sync.log' : 'sync.log.${index - 1}',
          ),
        );
        if (!await source.exists()) {
          continue;
        }
        final destination = File(path.join(directory, 'sync.log.$index'));
        if (await destination.exists()) {
          await destination.delete();
        }
        await source.rename(destination.path);
      }
    } catch (_) {
      // Best effort: la observabilidad no puede tumbar la sincronización.
    }
  }
}