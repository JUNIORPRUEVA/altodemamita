import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/resilience/app_paths.dart';

class BackupLogAgent {
  BackupLogAgent({AppPaths? appPaths}) : _appPaths = appPaths ?? AppPaths();

  final AppPaths _appPaths;

  String get logFilePath => path.join(_appPaths.logsDirectory, 'backup.log');

  Future<void> log({
    required DateTime timestamp,
    required String type, // local|cloud|restore_local|restore_cloud
    required String operation, // backup|restore
    required String result, // ok|error
    int? sizeBytes,
    String? message,
  }) async {
    try {
      await Directory(_appPaths.logsDirectory).create(recursive: true);

      final line = _formatLine(
        timestamp: timestamp,
        type: type,
        operation: operation,
        result: result,
        sizeBytes: sizeBytes,
        message: message,
      );

      final file = File(logFilePath);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Best effort: logging must never break backup/restore.
    }
  }

  static String _formatLine({
    required DateTime timestamp,
    required String type,
    required String operation,
    required String result,
    int? sizeBytes,
    String? message,
  }) {
    final ts = timestamp.toIso8601String();
    final normalizedMessage = (message ?? '').replaceAll('\n', ' ').trim();
    final sizeLabel = sizeBytes == null ? '' : ' sizeBytes=$sizeBytes';
    final msgLabel = normalizedMessage.isEmpty
        ? ''
        : ' message=${normalizedMessage.replaceAll('|', '/')}' ;
    return '$ts | $operation | $type | $result$sizeLabel$msgLabel';
  }
}
