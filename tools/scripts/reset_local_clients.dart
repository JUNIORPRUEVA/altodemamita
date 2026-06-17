import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final execute = args.contains('--execute');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final databasePath = AppPaths().databasePath;
  final db = await databaseFactory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      onConfigure: (database) => DatabaseSchema.configure(database),
    ),
  );

  final before = await _collectCounts(db);
  print('Local database: $databasePath');
  print('Local counts before reset: $before');

  if (!execute) {
    print('Dry run only. Re-run with --execute to apply the reset.');
    await db.close();
    return;
  }

  await db.transaction((txn) async {
    await txn.delete(DatabaseSchema.paymentsTable);
    await txn.delete(DatabaseSchema.installmentsTable);
    await txn.delete(DatabaseSchema.salesTable);
    await txn.delete(DatabaseSchema.clientsTable);
    await txn.delete(DatabaseSchema.syncQueueTable);
    await txn.delete(DatabaseSchema.conflictLogsTable);

    await txn.rawUpdate(
      'UPDATE ${DatabaseSchema.lotsTable} '
      'SET estado = ?, fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE deleted_at IS NULL',
      ['disponible'],
    );
  });

  final after = await _collectCounts(db);
  print('Local counts after reset: $after');

  await db.close();
}

Future<Map<String, int>> _collectCounts(dynamic db) async {
  final clients = await _count(db, DatabaseSchema.clientsTable);
  final sales = await _count(db, DatabaseSchema.salesTable);
  final installments = await _count(db, DatabaseSchema.installmentsTable);
  final payments = await _count(db, DatabaseSchema.paymentsTable);
  final queue = await _count(db, DatabaseSchema.syncQueueTable);
  final conflicts = await _count(db, DatabaseSchema.conflictLogsTable);

  return {
    'clients': clients,
    'sales': sales,
    'installments': installments,
    'payments': payments,
    'queue': queue,
    'conflicts': conflicts,
  };
}

Future<int> _count(dynamic db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
  final value = rows.first['total'];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}