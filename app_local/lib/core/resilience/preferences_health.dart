import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'diagnostics_log.dart';

/// Saneamiento del almacen de SharedPreferences.
///
/// `shared_preferences` guarda TODO el estado de dispositivo (incluidos los
/// cursores de sincronizacion incremental) en un unico JSON. Si el proceso
/// muere mientras se reescribe un archivo grande, el archivo queda lleno de
/// bytes NUL y `SharedPreferences.getInstance()` lanza `FormatException` en
/// CADA llamada.
///
/// Consecuencia observada en produccion: los cursores se leen como `null`, la
/// sincronizacion descarga de nuevo todas las cuotas (19.224 registros) y la
/// interfaz se congela varios minutos.
///
/// Este servicio corre antes de cualquier lectura de preferencias: si el
/// archivo no es JSON valido lo pone en cuarentena y deja un archivo limpio.
class PreferencesHealth {
  PreferencesHealth._();

  /// Ningun valor individual de preferencias debe superar este tamano.
  /// Los snapshots de listados ya viven en SQLite; duplicarlos aqui inflaba el
  /// archivo hasta varios MB y hacia fragil cada escritura.
  static const int maxValueBytes = 256 * 1024;

  static const String _companyName = 'Sistema Solares';
  static const String _productName = 'Sistema Solares';

  /// Repara el archivo de preferencias si esta corrupto o sobredimensionado.
  ///
  /// Devuelve `true` cuando el archivo quedo utilizable. Nunca lanza.
  static bool ensureHealthy() {
    if (kIsWeb || !Platform.isWindows) {
      return true;
    }

    for (final file in _candidateFiles()) {
      if (!file.existsSync()) {
        continue;
      }
      final result = _sanitize(file);
      if (result != null) {
        DiagnosticsLog.write('prefs', result);
      }
    }
    return true;
  }

  static List<File> _candidateFiles() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      return const <File>[];
    }

    final candidates = <File>[
      File(
        path.join(appData, _companyName, _productName, 'shared_preferences.json'),
      ),
    ];

    try {
      final root = Directory(appData);
      if (root.existsSync()) {
        for (final entry in root.listSync(followLinks: false)) {
          if (entry is! Directory) {
            continue;
          }
          if (!path.basename(entry.path).toLowerCase().contains('sistema')) {
            continue;
          }
          final nested = Directory(path.join(entry.path, _productName));
          if (!nested.existsSync()) {
            continue;
          }
          final file = File(path.join(nested.path, 'shared_preferences.json'));
          if (!candidates.any((existing) => existing.path == file.path)) {
            candidates.add(file);
          }
        }
      }
    } catch (_) {
      // Sin acceso al directorio raiz: solo queda la ruta canonica.
    }

    return candidates;
  }

  /// Devuelve una descripcion de la reparacion, o `null` si no hizo falta.
  static String? _sanitize(File file) {
    final bytes = _readBytes(file);
    if (bytes == null) {
      return null;
    }

    if (bytes.isEmpty) {
      return null;
    }

    Map<String, dynamic>? decoded;
    var corrupt = false;
    try {
      final text = utf8.decode(bytes);
      final value = jsonDecode(text);
      if (value is Map<String, dynamic>) {
        decoded = value;
      } else {
        corrupt = true;
      }
    } catch (_) {
      corrupt = true;
    }

    if (corrupt) {
      final backup = _quarantine(file, 'corrupt');
      _writeEmpty(file);
      return 'archivo de preferencias corrupto (${bytes.length} bytes); '
          'cuarentena=${backup == null ? 'fallida' : path.basename(backup.path)}';
    }

    final pruned = _pruneOversized(decoded!);
    if (!pruned) {
      return null;
    }

    final backup = _quarantine(file, 'oversized');
    try {
      file.writeAsStringSync(jsonEncode(decoded), flush: true);
    } catch (_) {
      return 'no se pudo reescribir preferencias; '
          'cuarentena=${backup == null ? 'fallida' : path.basename(backup.path)}';
    }
    return 'preferencias sobredimensionadas recortadas; '
        'cuarentena=${backup == null ? 'fallida' : path.basename(backup.path)}';
  }

  static List<int>? _readBytes(File file) {
    try {
      return file.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  /// Elimina valores individuales gigantes (snapshots de listados).
  static bool _pruneOversized(Map<String, dynamic> values) {
    final oversized = <String>[];
    values.forEach((key, value) {
      if (value is String && value.length > maxValueBytes) {
        oversized.add(key);
      }
    });
    for (final key in oversized) {
      values.remove(key);
    }
    return oversized.isNotEmpty;
  }

  static File? _quarantine(File file, String reason) {
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .replaceAll('-', '');
      final target = File('${file.path}.$reason-$stamp.bak');
      return file.renameSync(target.path);
    } catch (_) {
      // Si no se puede mover, se intenta sobrescribir de todos modos.
      return null;
    }
  }

  static void _writeEmpty(File file) {
    try {
      file.writeAsStringSync('{}', flush: true);
    } catch (_) {
      // Sin permisos: shared_preferences fallara pero el arranque continua.
    }
  }
}
