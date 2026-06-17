import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Best-effort guard to avoid running backup/restore while there are active
/// SQLite writers.
///
/// This does NOT require touching sync/login: it uses SQLite locking behavior.
class DatabaseActivityGuard {
  const DatabaseActivityGuard();

  Future<void> waitForNoActiveWriters({
    required String databasePath,
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(milliseconds: 350),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (true) {
      try {
        await _probeImmediateTransaction(databasePath);
        return;
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            'La base de datos está ocupada (escrituras activas).',
            timeout,
          );
        }
        await Future<void>.delayed(pollInterval);
      }
    }
  }

  Future<void> _probeImmediateTransaction(String databasePath) async {
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          readOnly: false,
          singleInstance: false,
        ),
      );

      // Keep probe fast and avoid long waits.
      await db.execute('PRAGMA busy_timeout = 250');
      await db.execute('BEGIN IMMEDIATE');
      await db.execute('ROLLBACK');
    } finally {
      try {
        await db?.close();
      } catch (_) {
        // Best effort.
      }
    }
  }
}
