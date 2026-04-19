import 'dart:convert';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final databasePath = AppPaths().databasePath;
  final db = await databaseFactory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      onConfigure: (database) => DatabaseSchema.configure(database),
    ),
  );

  print('Local database: $databasePath');

  final counts = await Future.wait([
    _count(db, DatabaseSchema.salesTable),
    _count(db, DatabaseSchema.installmentsTable),
    _count(db, DatabaseSchema.paymentsTable),
    _count(db, DatabaseSchema.syncQueueTable),
  ]);
  print(
    'Counts => sales=${counts[0]} installments=${counts[1]} payments=${counts[2]} queue=${counts[3]}',
  );

  final pendingSales = await db.rawQuery('''
    SELECT
      v.id,
      v.sync_id,
      v.cliente_id,
      v.solar_id,
      v.vendedor_id,
      v.fecha_venta,
      v.precio_venta,
      v.saldo_financiado,
      v.saldo_pendiente,
      v.interes_mensual,
      v.cantidad_cuotas,
      v.estado,
      v.sync_status,
      c.sync_id AS client_sync_id,
      s.sync_id AS product_sync_id,
      vd.sync_id AS seller_sync_id
    FROM ${DatabaseSchema.salesTable} v
    LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
    LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
    LEFT JOIN ${DatabaseSchema.sellersTable} vd ON vd.id = v.vendedor_id
    WHERE v.sync_status = ?
    ORDER BY v.fecha_actualizacion ASC, v.id ASC
  ''', [DatabaseSchema.syncStatusPending]);

  print('\nPending sales rows: ${pendingSales.length}');
  for (final row in pendingSales) {
    print(jsonEncode(row));
  }

  final queuedSales = await db.query(
    DatabaseSchema.syncQueueTable,
    where: 'scope = ?',
    whereArgs: ['sales'],
    orderBy: 'updated_at ASC',
  );
  print('\nQueued sales items: ${queuedSales.length}');
  for (final row in queuedSales) {
    final payloadJson = row['payload_json']?.toString();
    final payload = payloadJson == null || payloadJson.isEmpty
        ? null
        : jsonDecode(payloadJson);
    print(
      jsonEncode({
        'record_sync_id': row['record_sync_id'],
        'operation': row['operation'],
        'attempt_count': row['attempt_count'],
        'last_error': row['last_error'],
        'payload': payload,
      }),
    );
  }

  await db.close();
}

Future<int> _count(Database db, String table) async {
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