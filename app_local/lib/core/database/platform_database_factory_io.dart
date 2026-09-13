// Fábrica de base de datos NATIVA (Windows / Android / desktop).
//
// Comportamiento histórico exacto: `sqfliteFfiInit()` + `databaseFactoryFfi`.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DatabaseFactory createPlatformDatabaseFactory() {
  sqfliteFfiInit();
  return databaseFactoryFfi;
}
