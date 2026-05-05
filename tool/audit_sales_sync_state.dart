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
      readOnly: true,
      onConfigure: (database) => DatabaseSchema.configure(database),
    ),
  );

  try {
    print('LOCAL_DB $databasePath');

    await _printSection(
      title: 'LOCAL_COUNTS',
      rows: [
        {
          'ventas_activas': await _count(
            db,
            DatabaseSchema.salesTable,
            where: 'deleted_at IS NULL',
          ),
          'ventas_borradas': await _count(
            db,
            DatabaseSchema.salesTable,
            where: 'deleted_at IS NOT NULL',
          ),
          'cuotas_activas': await _count(
            db,
            DatabaseSchema.installmentsTable,
            where: 'deleted_at IS NULL',
          ),
          'pagos_activos': await _count(
            db,
            DatabaseSchema.paymentsTable,
            where: 'deleted_at IS NULL',
          ),
          'sync_queue': await _count(db, DatabaseSchema.syncQueueTable),
          'conflict_logs': await _count(db, DatabaseSchema.conflictLogsTable),
        },
      ],
    );

    await _printQuery(
      db,
      title: 'VENTAS_VISIBLES_UI',
      query: '''
        SELECT
          v.id,
          v.sync_id,
          v.id_remote,
          v.estado,
          v.sync_status,
          v.version,
          v.fecha_venta,
          v.fecha_actualizacion,
          v.deleted_at,
          c.id AS cliente_id,
          c.sync_id AS client_sync_id,
          c.deleted_at AS client_deleted_at,
          s.id AS solar_id,
          s.sync_id AS product_sync_id,
          s.deleted_at AS product_deleted_at,
          COUNT(CASE WHEN q.deleted_at IS NULL AND q.estado <> 'ajustada' THEN 1 END) AS cuotas_activas,
          COUNT(DISTINCT CASE WHEN p.deleted_at IS NULL THEN p.id END) AS pagos_activos
        FROM ${DatabaseSchema.salesTable} v
        INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
        INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
        LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.venta_id = v.id
        LEFT JOIN ${DatabaseSchema.paymentsTable} p ON p.venta_id = v.id
        WHERE v.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND s.deleted_at IS NULL
        GROUP BY
          v.id, v.sync_id, v.id_remote, v.estado, v.sync_status, v.version,
          v.fecha_venta, v.fecha_actualizacion, v.deleted_at,
          c.id, c.sync_id, c.deleted_at,
          s.id, s.sync_id, s.deleted_at
        ORDER BY v.fecha_venta DESC, v.id DESC
      ''',
    );

    await _printQuery(
      db,
      title: 'VENTAS_OCULTAS_UI',
      query: '''
        SELECT
          v.id,
          v.sync_id,
          v.id_remote,
          v.estado,
          v.sync_status,
          v.version,
          v.fecha_venta,
          v.fecha_actualizacion,
          v.deleted_at,
          c.id AS cliente_id,
          c.sync_id AS client_sync_id,
          c.deleted_at AS client_deleted_at,
          s.id AS solar_id,
          s.sync_id AS product_sync_id,
          s.deleted_at AS product_deleted_at,
          CASE
            WHEN c.id IS NULL THEN 'missing_client'
            WHEN s.id IS NULL THEN 'missing_product'
            WHEN c.deleted_at IS NOT NULL THEN 'client_soft_deleted'
            WHEN s.deleted_at IS NOT NULL THEN 'product_soft_deleted'
            WHEN v.deleted_at IS NOT NULL THEN 'sale_soft_deleted'
            ELSE 'other'
          END AS hidden_reason
        FROM ${DatabaseSchema.salesTable} v
        LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
        LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
        WHERE c.id IS NULL
           OR s.id IS NULL
           OR c.deleted_at IS NOT NULL
           OR s.deleted_at IS NOT NULL
           OR v.deleted_at IS NOT NULL
        ORDER BY v.fecha_actualizacion DESC, v.id DESC
      ''',
    );

    await _printQuery(
      db,
      title: 'VENTAS_LOCAL_TODAS',
      query: '''
        SELECT
          v.id,
          v.sync_id,
          v.id_remote,
          v.cliente_id,
          v.solar_id,
          v.estado,
          v.sync_status,
          v.version,
          v.fecha_venta,
          v.fecha_actualizacion,
          v.deleted_at,
          c.sync_id AS client_sync_id,
          s.sync_id AS product_sync_id
        FROM ${DatabaseSchema.salesTable} v
        LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
        LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
        ORDER BY v.fecha_actualizacion DESC, v.id DESC
      ''',
    );

    await _printQuery(
      db,
      title: 'CUOTAS_POR_VENTA',
      query: '''
        SELECT
          v.sync_id AS sale_sync_id,
          COUNT(q.id) AS cuotas_total,
          COUNT(CASE WHEN q.deleted_at IS NULL THEN 1 END) AS cuotas_activas,
          COUNT(CASE WHEN q.deleted_at IS NOT NULL THEN 1 END) AS cuotas_borradas,
          COUNT(CASE WHEN q.sync_status = '${DatabaseSchema.syncStatusConflict}' THEN 1 END) AS cuotas_conflict,
          MAX(q.fecha_actualizacion) AS cuotas_updated_at
        FROM ${DatabaseSchema.salesTable} v
        LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.venta_id = v.id
        GROUP BY v.sync_id
        ORDER BY cuotas_total DESC, v.sync_id ASC
      ''',
    );

    await _printQuery(
      db,
      title: 'CUOTAS_HUERFANAS',
      query: '''
        SELECT
          q.id,
          q.sync_id,
          q.venta_id,
          q.numero_cuota,
          q.sync_status,
          q.version,
          q.fecha_actualizacion,
          q.deleted_at
        FROM ${DatabaseSchema.installmentsTable} q
        LEFT JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
        WHERE v.id IS NULL
        ORDER BY q.fecha_actualizacion DESC, q.id DESC
      ''',
    );

    await _printQuery(
      db,
      title: 'PAGOS_POR_VENTA',
      query: '''
        SELECT
          v.sync_id AS sale_sync_id,
          COUNT(p.id) AS pagos_total,
          COUNT(CASE WHEN p.deleted_at IS NULL THEN 1 END) AS pagos_activos,
          SUM(CASE WHEN p.deleted_at IS NULL THEN COALESCE(p.monto_pagado, 0) ELSE 0 END) AS monto_pagado_activo,
          MAX(p.fecha_actualizacion) AS pagos_updated_at
        FROM ${DatabaseSchema.salesTable} v
        LEFT JOIN ${DatabaseSchema.paymentsTable} p ON p.venta_id = v.id
        GROUP BY v.sync_id
        ORDER BY pagos_total DESC, v.sync_id ASC
      ''',
    );

    await _printQuery(
      db,
      title: 'SYNC_QUEUE_RELEVANTE',
      query: '''
        SELECT
          id,
          scope,
          record_sync_id,
          operation,
          attempt_count,
          last_error,
          next_attempt_at,
          updated_at
        FROM ${DatabaseSchema.syncQueueTable}
        WHERE scope IN ('sales', 'installments', 'payments')
        ORDER BY updated_at DESC, id DESC
      ''',
    );

    await _printQuery(
      db,
      title: 'CONFLICT_LOGS_RELEVANTE',
      query: '''
        SELECT
          id,
          scope,
          record_sync_id,
          local_version,
          server_version,
          strategy,
          message,
          resolution,
          detected_at,
          resolved_at
        FROM ${DatabaseSchema.conflictLogsTable}
        WHERE scope IN ('sales', 'installments', 'payments')
        ORDER BY detected_at DESC, id DESC
      ''',
    );
  } finally {
    await db.close();
  }
}

Future<void> _printQuery(
  Database db, {
  required String title,
  required String query,
}) async {
  final rows = await db.rawQuery(query);
  await _printSection(title: title, rows: rows);
}

Future<void> _printSection({
  required String title,
  required List<Map<String, Object?>> rows,
}) async {
  print('\n=== $title (${rows.length}) ===');
  for (final row in rows) {
    print(jsonEncode(row));
  }
}

Future<int> _count(
  Database db,
  String tableName, {
  String? where,
}) async {
  final rows = await db.rawQuery(
    where == null
        ? 'SELECT COUNT(*) AS total FROM $tableName'
        : 'SELECT COUNT(*) AS total FROM $tableName WHERE $where',
  );
  final value = rows.first['total'];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}