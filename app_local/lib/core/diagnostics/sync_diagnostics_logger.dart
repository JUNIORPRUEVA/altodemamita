import 'dart:io';

import '../resilience/app_paths.dart';

class SyncDiagnosticsLogger {
  SyncDiagnosticsLogger._();

  static final SyncDiagnosticsLogger instance = SyncDiagnosticsLogger._();

  final AppPaths _appPaths = AppPaths();
  File? _logFile;
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> get logFile async {
    final current = _logFile;
    if (current != null) {
      return current;
    }

    await Directory(_appPaths.logsDirectory).create(recursive: true);
    final file = File(_appPaths.syncDiagnosticsLogPath);
    _logFile = file;
    return file;
  }

  String get expectedLogPath => _appPaths.syncDiagnosticsLogPath;

  Future<void> log(String message) {
    _pendingWrite = _pendingWrite.then((_) => _write(message));
    return _pendingWrite;
  }

  Future<void> _write(String message) async {
    try {
      final file = await logFile;
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '$timestamp $message${Platform.lineTerminator}',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Diagnostics must never block the production app.
    }
  }

  void logUnawaited(String message) {
    _pendingWrite = _pendingWrite.then((_) => _write(message));
  }
}
