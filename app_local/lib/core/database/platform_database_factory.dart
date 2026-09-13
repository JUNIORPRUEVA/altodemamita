// Selección condicional de la implementación de SQLite.
//
// - Nativo: `sqflite_common_ffi` (databaseFactoryFfi).
// - Web: `sqflite_common_ffi_web` (SQLite WASM sobre IndexedDB).
//
// Los repositorios, el esquema y los servicios NO cambian: sólo cambia la
// fábrica de base de datos.
export 'platform_database_factory_io.dart'
    if (dart.library.js_interop) 'platform_database_factory_web.dart';
