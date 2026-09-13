// Fábrica de base de datos WEB.
//
// SQLite compilado a WebAssembly y persistido en IndexedDB a través de
// `sqflite_common_ffi_web`. Expone la MISMA interfaz `DatabaseFactory` que la
// versión nativa, por lo que esquema, repositorios, servicios, outbox y
// sincronización se reutilizan sin cambios.
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

DatabaseFactory createPlatformDatabaseFactory() =>
    databaseFactoryFfiWebNoWebWorker;
