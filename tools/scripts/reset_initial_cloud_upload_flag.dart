/// Script para resetear la bandera de sincronización inicial completa.
///
/// Uso:
///   dart run tools/scripts/reset_initial_cloud_upload_flag.dart
///
/// Esto permite probar la sincronización inicial múltiples veces en DEV.
/// Borra la bandera 'sync.local_upload_bootstrap_completed' de SharedPreferences
/// y también la entrada de configuración en SQLite si existe.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_local/lib/core/database/app_database.dart';
import '../app_local/lib/core/database/database_schema.dart';

Future<void> main() async {
  sqfliteFfiInit();

  print('=== Reset Initial Cloud Upload Flag ===');
  print('');

  // 1. Resetear SharedPreferences
  print('1. Resetting SharedPreferences...');
  final prefs = await SharedPreferences.getInstance();
  final removed = prefs.remove('sync.local_upload_bootstrap_completed');
  print('   sync.local_upload_bootstrap_completed removed: $removed');

  // 2. Resetear SQLite settings si existe
  print('2. Resetting SQLite settings...');
  try {
    final db = await databaseFactoryFfi.openDatabase(
      await AppPaths.databasePath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.schemaVersion,
        onCreate: (db, version) async {},
      ),
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tables.map((r) => r['name'] as String).toSet();

    if (tableNames.contains(DatabaseSchema.settingsTable)) {
      await db.delete(
        DatabaseSchema.settingsTable,
        where: 'clave = ?',
        whereArgs: ['sync.local_upload_bootstrap_completed'],
      );
      print('   Deleted from settings table.');
    } else {
      print('   Settings table not found, skipping.');
    }

    await db.close();
  } catch (e) {
    print('   Error accessing SQLite: $e');
  }

  print('');
  print('=== Done ===');
  print('');
  print('La bandera initial_cloud_upload_completed ha sido reseteada.');
  print('La próxima vez que la app se inicie, ejecutará la sincronización inicial.');
}
