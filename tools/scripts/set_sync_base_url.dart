import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _supportDirectory() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final appData = Platform.environment['APPDATA'];
  final userProfile = Platform.environment['USERPROFILE'];

  final base = (localAppData != null && localAppData.isNotEmpty)
      ? localAppData
      : (appData != null && appData.isNotEmpty)
          ? appData
          : (userProfile != null && userProfile.isNotEmpty)
              ? path.join(userProfile, 'AppData', 'Local')
              : Directory.systemTemp.parent.path;

  return path.join(base, 'SistemaSolares');
}

String _normalizeBackendBaseUrl(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.trim().isEmpty) {
    return trimmed.replaceAll(RegExp(r'/$'), '');
  }

  final pathSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (pathSegments.isEmpty || pathSegments.last.toLowerCase() != 'api') {
    pathSegments.add('api');
  }

  return uri
      .replace(pathSegments: pathSegments)
      .toString()
      .replaceAll(RegExp(r'/$'), '');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.trim().isEmpty) {
    stderr.writeln('Usage: dart run tool/set_sync_base_url.dart <baseUrl>');
    stderr.writeln('Example: dart run tool/set_sync_base_url.dart https://<your-domain>');
    stderr.writeln('Note: "/api" is appended automatically if missing.');
    exitCode = 64;
    return;
  }

  final normalizedUrl = _normalizeBackendBaseUrl(args.first);
  if (normalizedUrl.isEmpty) {
    stderr.writeln('Error: baseUrl is empty after normalization.');
    exitCode = 64;
    return;
  }

  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  final dbPath = path.join(
    _supportDirectory(),
    'data',
    'database',
    'sistema_solares.db',
  );

  stdout.writeln('DB path: $dbPath');
  if (!File(dbPath).existsSync()) {
    stderr.writeln('DB file not found.');
    exitCode = 2;
    return;
  }

  final db = await databaseFactory.openDatabase(dbPath);
  try {
    final now = DateTime.now().toIso8601String();

    final updated = await db.update(
      'configuracion',
      {'valor': normalizedUrl, 'fecha_actualizacion': now},
      where: 'clave = ?',
      whereArgs: ['sync.base_url'],
    );

    if (updated == 0) {
      await db.insert('configuracion', {
        'clave': 'sync.base_url',
        'valor': normalizedUrl,
        'fecha_actualizacion': now,
      });
    }

    stdout.writeln('sync.base_url set to: $normalizedUrl');
  } finally {
    await db.close();
  }
}
