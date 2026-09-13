@TestOn('browser')
library;

// Prueba de humo REAL en navegador.
//
// Se ejecuta con:  flutter test --platform chrome test/web_pwa/
//
// Comprueba que la app funciona en web de verdad:
// - `AppPaths` usa la implementación web (sin `dart:io`).
// - SQLite Web (WASM sobre IndexedDB) crea el esquema completo.
// - Se puede escribir y leer información.
// - La información persiste al cerrar y reabrir la base de datos.
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  test('AppPaths web no depende del sistema de archivos', () {
    final paths = AppPaths();
    expect(paths.supportsFileSystem, isFalse);
    expect(paths.databasePath, contains('sistema_solares.db'));
    expect(paths.databasePath, isNot(contains('LOCALAPPDATA')));
  });

  test('SQLite Web: esquema completo + escritura + persistencia', () async {
    const databasePath = '/SistemaSolares/data/database/web_smoke.db';

    // --- Inicialización en frío -------------------------------------------
    final first = AppDatabase.test(databasePath);
    await first.initialize();
    final db = await first.database;
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final version = (versionRows.first.values.first as num?)?.toInt() ?? 0;
    expect(
      version,
      greaterThan(0),
      reason: 'el esquema debe tener version despues de crearse',
    );

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tables
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    for (final required in [
      DatabaseSchema.clientsTable,
      DatabaseSchema.lotsTable,
      DatabaseSchema.salesTable,
      DatabaseSchema.installmentsTable,
      DatabaseSchema.paymentsTable,
      DatabaseSchema.syncQueueTable,
    ]) {
      expect(
        tableNames,
        contains(required),
        reason: 'falta la tabla $required en el esquema web',
      );
    }

    // --- Escritura --------------------------------------------------------
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'web-smoke-client-1',
      'nombre': 'CLIENTE WEB SMOKE',
      'cedula': '00000000001',
      'telefono': '8090000000',
      'direccion': 'prueba web',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPending,
    });

    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'sync_id = ?',
      whereArgs: ['web-smoke-client-1'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['nombre'], 'CLIENTE WEB SMOKE');

    await first.close();

    // --- Persistencia (IndexedDB) ----------------------------------------
    final second = AppDatabase.test(databasePath);
    await second.initialize();
    final reopened = await second.database;
    final persisted = await reopened.query(
      DatabaseSchema.clientsTable,
      where: 'sync_id = ?',
      whereArgs: ['web-smoke-client-1'],
    );
    expect(
      persisted,
      hasLength(1),
      reason: 'los datos deben persistir tras cerrar y reabrir en web',
    );

    // Limpieza de la prueba.
    await reopened.delete(DatabaseSchema.clientsTable);
    await second.close();
  });
}
