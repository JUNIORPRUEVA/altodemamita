import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// Bitácora de diagnóstico de bajo nivel.
///
/// Escribe en `logs/diagnostics.log` sin depender de `debugPrint` (que no
/// existe en release). Sirve para auditar bloqueos del hilo principal y medir
/// pasos concretos de una operación.
class DiagnosticsLog {
  DiagnosticsLog._();

  static const int _maxBytes = 2 * 1024 * 1024;
  static File? _cachedFile;

  static File? _file() {
    if (kIsWeb) {
      return null;
    }
    final cached = _cachedFile;
    if (cached != null) {
      return cached;
    }
    try {
      final directory = Directory(AppPaths().logsDirectory);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(
        '${directory.path}${Platform.pathSeparator}diagnostics.log',
      );
      _cachedFile = file;
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Agrega una línea con marca de tiempo.
  static void write(String tag, String message) {
    final file = _file();
    if (file == null) {
      return;
    }
    try {
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        file.writeAsStringSync('');
      }
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} [$tag] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // El diagnóstico nunca debe afectar la app.
    }
  }

  /// Vigila bloqueos del hilo principal.
  ///
  /// Cada 250 ms comprueba cuánto se retrasó el tick. Si el retraso supera el
  /// umbral, la interfaz estuvo congelada ese tiempo y queda registrado.
  static Timer? _watchdog;

  static void startStallWatchdog({
    Duration interval = const Duration(milliseconds: 250),
    int stallThresholdMs = 1000,
  }) {
    if (kIsWeb || _watchdog != null) {
      return;
    }
    var expected = DateTime.now();
    _watchdog = Timer.periodic(interval, (_) {
      final now = DateTime.now();
      final drift = now.difference(expected).inMilliseconds;
      if (drift > stallThresholdMs) {
        write(
          'ui-stall',
          'interfaz congelada ~$drift ms (tick esperado ${interval.inMilliseconds} ms)',
        );
      }
      expected = now;
    });
  }

  static void stopStallWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }
}
