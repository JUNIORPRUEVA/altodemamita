import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/resilience/app_paths.dart';

class SyncLogger {
  SyncLogger({AppPaths? appPaths}) : _appPaths = appPaths ?? AppPaths();

  static final SyncLogger instance = SyncLogger();

  final AppPaths _appPaths;

  Future<void> log({
    required String action,
    required String entity,
    required String result,
    String? error,
    Map<String, Object?> extra = const {},
  }) async {
    await _appPaths.ensureCriticalDirectories();
    final file = File(path.join(_appPaths.logsDirectory, 'sync.log'));
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
}