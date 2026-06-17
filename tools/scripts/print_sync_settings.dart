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

Future<void> main() async {
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
    const keys = <String>[
      'sync.base_url',
      'sync.last_error',
      'sync.last_run_at',
      'sync.conflict_strategy',
    ];

    final rows = await db.query(
      'configuracion',
      columns: ['clave', 'valor', 'fecha_actualizacion'],
      where: 'clave IN (?, ?, ?, ?)',
      whereArgs: keys,
      orderBy: 'clave ASC',
    );

    final byKey = <String, Map<String, Object?>>{
      for (final row in rows)
        (row['clave']?.toString() ?? ''): row,
    };

    for (final key in keys) {
      final row = byKey[key];
      if (row == null) {
        if (key == 'sync.base_url') {
          stdout.writeln(
            'sync.base_url: <not set> (sync disabled until configured)',
          );
        } else {
          stdout.writeln('$key: <not set>');
        }
        continue;
      }

      stdout.writeln(
        '${row['clave']}: ${row['valor']} (updated: ${row['fecha_actualizacion']})',
      );
    }
  } finally {
    await db.close();
  }
}
