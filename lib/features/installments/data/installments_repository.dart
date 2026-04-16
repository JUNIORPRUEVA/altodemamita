import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../domain/installment_detail.dart';

class InstallmentsRepository {
  InstallmentsRepository({AppDatabase? database})
    : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  /// Get all installments with related sale and client information
  Future<List<InstallmentDetail>> getAll() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT 
        q.id,
        q.numero_cuota,
        q.venta_id,
        COALESCE(c.nombre, 'N/A') as nombre_cliente,
        COALESCE(c.cedula, 'N/A') as cedula_cliente,
        COALESCE(s.manzana_numero || '-' || s.solar_numero, 'N/A') as codigo_solar,
        q.fecha_vencimiento,
        q.saldo_inicial,
        q.capital_cuota,
        q.interes_cuota,
        q.monto_cuota,
        q.monto_pagado,
        q.saldo_final,
        q.estado
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE q.estado <> 'ajustada'
      ORDER BY q.venta_id ASC, q.numero_cuota ASC, q.fecha_vencimiento ASC
    ''');

    return rows.map((row) => InstallmentDetail.fromMap(row)).toList();
  }

  /// Get installments for a specific sale
  Future<List<InstallmentDetail>> getBySaleId(int saleId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT 
        q.id,
        q.numero_cuota,
        q.venta_id,
        COALESCE(c.nombre, 'N/A') as nombre_cliente,
        COALESCE(c.cedula, 'N/A') as cedula_cliente,
        COALESCE(s.manzana_numero || '-' || s.solar_numero, 'N/A') as codigo_solar,
        q.fecha_vencimiento,
        q.saldo_inicial,
        q.capital_cuota,
        q.interes_cuota,
        q.monto_cuota,
        q.monto_pagado,
        q.saldo_final,
        q.estado
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE q.venta_id = ? AND q.estado <> 'ajustada'
      ORDER BY q.numero_cuota ASC
    ''', [saleId]);

    return rows.map((row) => InstallmentDetail.fromMap(row)).toList();
  }

  /// Search installments by multiple criteria
  Future<List<InstallmentDetail>> search(String query) async {
    final db = await _appDatabase.database;
    final searchPattern = '%${query.toLowerCase()}%';

    final rows = await db.rawQuery('''
      SELECT 
        q.id,
        q.numero_cuota,
        q.venta_id,
        COALESCE(c.nombre, 'N/A') as nombre_cliente,
        COALESCE(c.cedula, 'N/A') as cedula_cliente,
        COALESCE(s.manzana_numero || '-' || s.solar_numero, 'N/A') as codigo_solar,
        q.fecha_vencimiento,
        q.saldo_inicial,
        q.capital_cuota,
        q.interes_cuota,
        q.monto_cuota,
        q.monto_pagado,
        q.saldo_final,
        q.estado
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE q.estado <> 'ajustada'
        AND (
         LOWER(COALESCE(c.nombre, '')) LIKE ?
         OR LOWER(COALESCE(c.cedula, '')) LIKE ?
         OR LOWER(COALESCE(s.manzana_numero, '')) LIKE ?
         OR LOWER(COALESCE(s.solar_numero, '')) LIKE ?
         OR CAST(q.venta_id AS TEXT) LIKE ?
        )
      ORDER BY q.venta_id ASC, q.numero_cuota ASC, q.fecha_vencimiento ASC
    ''', [searchPattern, searchPattern, searchPattern, searchPattern, searchPattern]);

    return rows.map((row) => InstallmentDetail.fromMap(row)).toList();
  }

  /// Get summary information for a specific sale
  Future<SaleInstallmentsSummary?> getSaleSummary(int saleId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT 
        v.id as venta_id,
        c.nombre as nombre_cliente,
        c.cedula as cedula_cliente,
        s.manzana_numero || '-' || s.solar_numero as codigo_solar,
        v.saldo_financiado as monto_total,
        (v.saldo_financiado - v.saldo_pendiente) as total_pagado,
        v.saldo_pendiente as total_pendiente,
        COUNT(CASE WHEN q.estado <> 'ajustada' THEN 1 END) as total_cuotas,
        SUM(CASE WHEN q.estado <> 'ajustada' AND q.monto_pagado >= q.monto_cuota THEN 1 ELSE 0 END) as cuotas_pagadas,
        SUM(CASE WHEN q.estado <> 'ajustada' AND q.monto_pagado < q.monto_cuota AND q.monto_pagado > 0 THEN 1 ELSE 0 END) as cuotas_parciales,
        SUM(CASE WHEN q.estado <> 'ajustada' AND q.monto_pagado = 0 THEN 1 ELSE 0 END) as cuotas_pendientes
      FROM ${DatabaseSchema.salesTable} v
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.venta_id = v.id
      WHERE v.id = ?
      GROUP BY v.id
    ''', [saleId]);

    if (rows.isEmpty) {
      return null;
    }

    return SaleInstallmentsSummary.fromMap(rows.first);
  }

  /// Get installments by status
  Future<List<InstallmentDetail>> getByStatus(String status) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT 
        q.id,
        q.numero_cuota,
        q.venta_id,
        COALESCE(c.nombre, 'N/A') as nombre_cliente,
        COALESCE(c.cedula, 'N/A') as cedula_cliente,
        COALESCE(s.manzana_numero || '-' || s.solar_numero, 'N/A') as codigo_solar,
        q.fecha_vencimiento,
        q.saldo_inicial,
        q.capital_cuota,
        q.interes_cuota,
        q.monto_cuota,
        q.monto_pagado,
        q.saldo_final,
        q.estado
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE q.estado = ? AND q.estado <> 'ajustada'
      ORDER BY q.venta_id ASC, q.numero_cuota ASC, q.fecha_vencimiento ASC
    ''', [status]);

    return rows.map((row) => InstallmentDetail.fromMap(row)).toList();
  }

  /// Get overdue installments
  Future<List<InstallmentDetail>> getOverdue() async {
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final rows = await db.rawQuery('''
      SELECT 
        q.id,
        q.numero_cuota,
        q.venta_id,
        COALESCE(c.nombre, 'N/A') as nombre_cliente,
        COALESCE(c.cedula, 'N/A') as cedula_cliente,
        COALESCE(s.manzana_numero || '-' || s.solar_numero, 'N/A') as codigo_solar,
        q.fecha_vencimiento,
        q.saldo_inicial,
        q.capital_cuota,
        q.interes_cuota,
        q.monto_cuota,
        q.monto_pagado,
        q.saldo_final,
        q.estado
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE q.fecha_vencimiento < ?
        AND q.estado <> 'ajustada'
        AND q.monto_pagado < q.monto_cuota
      ORDER BY q.venta_id ASC, q.numero_cuota ASC, q.fecha_vencimiento ASC
    ''', [now]);

    return rows.map((row) => InstallmentDetail.fromMap(row)).toList();
  }
}
