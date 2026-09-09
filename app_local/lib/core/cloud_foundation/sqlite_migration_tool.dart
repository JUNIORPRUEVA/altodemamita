import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SqliteMigrationTool {
  SqliteMigrationTool({DatabaseFactory? databaseFactoryOverride})
    : _databaseFactory = databaseFactoryOverride ?? databaseFactoryFfi;

  final DatabaseFactory _databaseFactory;

  static const businessTables = [
    'clientes',
    'vendedores',
    'solares',
    'ventas',
    'cuotas',
    'pagos',
    'usuarios',
    'roles',
    'permisos',
    'user_roles',
    'role_permissions',
    'company_profiles',
    'informacion_empresa',
    'parametros_financieros',
    'configuracion',
  ];

  static const excludedTables = [
    'configuracion_impresoras',
    'sync_queue',
    'conflict_logs',
    'informacion_backups',
    'preferencias_backup',
    'sesiones_auth',
  ];

  Future<MigrationReport> inspect(String sourceDatabasePath) async {
    sqfliteFfiInit();
    final db = await _databaseFactory.openDatabase(
      sourceDatabasePath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final userVersion = await _userVersion(db);
      final existingTables = await _tables(db);
      final missingTables = businessTables
          .where((table) => !existingTables.contains(table))
          .toList(growable: false);
      final tableCounts = <String, int>{};
      final activeCounts = <String, int>{};
      final deletedCounts = <String, int>{};

      for (final table in businessTables.where(existingTables.contains)) {
        tableCounts[table] = await _count(db, table);
        if (await _hasColumn(db, table, 'deleted_at')) {
          activeCounts[table] = await _countWhere(
            db,
            table,
            'deleted_at IS NULL',
          );
          deletedCounts[table] = await _countWhere(
            db,
            table,
            'deleted_at IS NOT NULL',
          );
        }
      }

      final errors = <String>[
        ...missingTables.map((table) => 'missing business table: $table'),
        ...await _syncIdErrors(db, existingTables),
        ...await _relationshipErrors(db, existingTables),
        ...await _moneyErrors(db, existingTables),
      ];
      final payload = errors.isEmpty
          ? await _buildPayload(db, existingTables)
          : const <String, List<Map<String, Object?>>>{};

      return MigrationReport(
        userVersion: userVersion,
        missingTables: missingTables,
        tableCounts: tableCounts,
        activeCounts: activeCounts,
        deletedCounts: deletedCounts,
        p0Errors: errors,
        payload: payload,
        reconciliation: MigrationReconciliation(
          sourceCounts: tableCounts,
          payloadCounts: payload.map(
            (table, records) => MapEntry(table, records.length),
          ),
          money: await _moneySummary(db, existingTables),
        ),
      );
    } finally {
      await db.close();
    }
  }

  Future<void> writeReports({
    required MigrationReport report,
    required String outputDirectory,
  }) async {
    await Directory(outputDirectory).create(recursive: true);
    final machine = File(path.join(outputDirectory, 'migration_report.json'));
    final human = File(path.join(outputDirectory, 'migration_report.md'));
    await machine.writeAsString(jsonEncode(report.toJson()));
    await human.writeAsString(report.toMarkdown());
  }

  Future<SyntheticDatabaseSummary> createSyntheticDatabase(
    String databasePath,
  ) async {
    sqfliteFfiInit();
    await Directory(path.dirname(databasePath)).create(recursive: true);
    if (await File(databasePath).exists()) {
      await databaseFactoryFfi.deleteDatabase(databasePath);
    }
    final db = await _databaseFactory.openDatabase(databasePath);
    try {
      await db.execute('PRAGMA user_version = 28');
      await _createSyntheticSchema(db);
      await _seedSyntheticData(db);
      final tables = await _tables(db);
      final counts = <String, int>{};
      for (final table in businessTables.where(tables.contains)) {
        counts[table] = await _count(db, table);
      }
      return SyntheticDatabaseSummary(path: databasePath, counts: counts);
    } finally {
      await db.close();
    }
  }
}

class MigrationReport {
  const MigrationReport({
    required this.userVersion,
    required this.missingTables,
    required this.tableCounts,
    required this.activeCounts,
    required this.deletedCounts,
    required this.p0Errors,
    required this.payload,
    required this.reconciliation,
  });

  final int userVersion;
  final List<String> missingTables;
  final Map<String, int> tableCounts;
  final Map<String, int> activeCounts;
  final Map<String, int> deletedCounts;
  final List<String> p0Errors;
  final Map<String, List<Map<String, Object?>>> payload;
  final MigrationReconciliation reconciliation;

  bool get passed => p0Errors.isEmpty;

  Map<String, Object?> toJson() => {
    'userVersion': userVersion,
    'passed': passed,
    'missingTables': missingTables,
    'tableCounts': tableCounts,
    'activeCounts': activeCounts,
    'deletedCounts': deletedCounts,
    'p0Errors': p0Errors,
    'payload': payload,
    'reconciliation': reconciliation.toJson(),
  };

  String toMarkdown() {
    return '''
# SQLite Migration Report

Passed: ${passed ? 'YES' : 'NO'}

User version: $userVersion

P0 errors:
${p0Errors.isEmpty ? '- NONE' : p0Errors.map((error) => '- $error').join('\n')}

Table counts:
${tableCounts.entries.map((entry) => '- ${entry.key}: ${entry.value}').join('\n')}
''';
  }
}

class MigrationReconciliation {
  const MigrationReconciliation({
    required this.sourceCounts,
    required this.payloadCounts,
    required this.money,
  });

  final Map<String, int> sourceCounts;
  final Map<String, int> payloadCounts;
  final Map<String, num> money;

  Map<String, Object?> toJson() => {
    'sourceCounts': sourceCounts,
    'payloadCounts': payloadCounts,
    'money': money,
  };
}

class SyntheticDatabaseSummary {
  const SyntheticDatabaseSummary({required this.path, required this.counts});

  final String path;
  final Map<String, int> counts;
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.first.values.first as int? ?? 0;
}

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name'].toString()).toSet();
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((row) => row['name'] == column);
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.first['count'] as int? ?? 0;
}

Future<int> _countWhere(Database db, String table, String where) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS count FROM $table WHERE $where',
  );
  return rows.first['count'] as int? ?? 0;
}

Future<List<String>> _syncIdErrors(Database db, Set<String> tables) async {
  final errors = <String>[];
  for (final table in tables.intersection(
    SqliteMigrationTool.businessTables.toSet(),
  )) {
    if (!await _hasColumn(db, table, 'sync_id')) {
      continue;
    }
    final missing = await _countWhere(
      db,
      table,
      "sync_id IS NULL OR TRIM(sync_id) = ''",
    );
    if (missing > 0) {
      errors.add('$table has $missing missing sync_id values');
    }
    final duplicates = await db.rawQuery('''
      SELECT sync_id, COUNT(*) AS count
      FROM $table
      WHERE sync_id IS NOT NULL AND TRIM(sync_id) <> ''
      GROUP BY sync_id
      HAVING COUNT(*) > 1
    ''');
    if (duplicates.isNotEmpty) {
      errors.add('$table has duplicate sync_id values');
    }
  }
  return errors;
}

Future<List<String>> _relationshipErrors(
  Database db,
  Set<String> tables,
) async {
  final errors = <String>[];
  if (tables.containsAll(['ventas', 'clientes'])) {
    final orphans = await _countJoinOrphans(
      db,
      'ventas',
      'cliente_id',
      'clientes',
    );
    if (orphans > 0) errors.add('ventas has $orphans orphan cliente_id values');
  }
  if (tables.containsAll(['ventas', 'solares'])) {
    final orphans = await _countJoinOrphans(
      db,
      'ventas',
      'solar_id',
      'solares',
    );
    if (orphans > 0) errors.add('ventas has $orphans orphan solar_id values');
  }
  if (tables.containsAll(['cuotas', 'ventas'])) {
    final orphans = await _countJoinOrphans(db, 'cuotas', 'venta_id', 'ventas');
    if (orphans > 0) errors.add('cuotas has $orphans orphan venta_id values');
  }
  if (tables.containsAll(['pagos', 'ventas'])) {
    final orphans = await _countJoinOrphans(db, 'pagos', 'venta_id', 'ventas');
    if (orphans > 0) errors.add('pagos has $orphans orphan venta_id values');
  }
  if (tables.contains('ventas')) {
    final duplicates = await db.rawQuery('''
      SELECT solar_id, COUNT(*) AS count
      FROM ventas
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(estado, '')) NOT IN ('cancelada','cancelado','anulada','anulado','eliminada','eliminado')
      GROUP BY solar_id
      HAVING COUNT(*) > 1
    ''');
    if (duplicates.isNotEmpty) {
      errors.add('duplicate active sale per lot detected');
    }
  }
  return errors;
}

Future<int> _countJoinOrphans(
  Database db,
  String table,
  String column,
  String parent,
) async {
  final rows = await db.rawQuery('''
    SELECT COUNT(*) AS count
    FROM $table child
    LEFT JOIN $parent parent ON parent.id = child.$column
    WHERE child.$column IS NOT NULL AND parent.id IS NULL
  ''');
  return rows.first['count'] as int? ?? 0;
}

Future<List<String>> _moneyErrors(Database db, Set<String> tables) async {
  if (!tables.contains('ventas')) {
    return const [];
  }
  final rows = await db.rawQuery('''
    SELECT COUNT(*) AS count
    FROM ventas
    WHERE precio_venta IS NULL OR precio_venta < 0
       OR saldo_pendiente IS NULL OR saldo_pendiente < -0.009
  ''');
  final invalid = rows.first['count'] as int? ?? 0;
  return invalid == 0 ? const [] : ['ventas has $invalid invalid money rows'];
}

Future<Map<String, num>> _moneySummary(Database db, Set<String> tables) async {
  final result = <String, num>{};
  if (tables.contains('ventas')) {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(precio_venta), 0) AS sales,
             COALESCE(SUM(saldo_pendiente), 0) AS balances
      FROM ventas
    ''');
    result['sumSales'] = rows.first['sales'] as num? ?? 0;
    result['sumBalances'] = rows.first['balances'] as num? ?? 0;
  }
  if (tables.contains('pagos')) {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(monto_pagado), 0) AS payments FROM pagos',
    );
    result['sumPayments'] = rows.first['payments'] as num? ?? 0;
  }
  return result;
}

Future<Map<String, List<Map<String, Object?>>>> _buildPayload(
  Database db,
  Set<String> tables,
) async {
  final payload = <String, List<Map<String, Object?>>>{};
  for (final table in SqliteMigrationTool.businessTables.where(
    tables.contains,
  )) {
    payload[table] = await db.query(table);
  }
  return payload;
}

Future<void> _createSyntheticSchema(Database db) async {
  await db.execute(
    'CREATE TABLE clientes (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, cedula TEXT, telefono TEXT, direccion TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE vendedores (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, cedula TEXT, telefono TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE solares (id INTEGER PRIMARY KEY, sync_id TEXT, manzana_numero TEXT, solar_numero TEXT, metros_cuadrados REAL, precio_por_metro REAL, estado TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE usuarios (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, email TEXT, rol TEXT, password_hash TEXT, activo INTEGER, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE roles (id INTEGER PRIMARY KEY, sync_id TEXT, code TEXT, name TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE permisos (id INTEGER PRIMARY KEY, sync_id TEXT, usuario_id INTEGER, modulo TEXT, acciones TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE user_roles (id INTEGER PRIMARY KEY, sync_id TEXT, user_id INTEGER, role_id INTEGER, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE role_permissions (id INTEGER PRIMARY KEY, sync_id TEXT, role_id INTEGER, permission_id INTEGER, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE company_profiles (id INTEGER PRIMARY KEY, sync_id TEXT, name TEXT, phone TEXT, address TEXT, logo_base64 TEXT, local_path TEXT, remote_url TEXT, upload_status TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE informacion_empresa (id INTEGER PRIMARY KEY, nombre TEXT, telefono TEXT, direccion TEXT, logo_base64 TEXT, fecha_creacion TEXT, fecha_actualizacion TEXT)',
  );
  await db.execute(
    'CREATE TABLE parametros_financieros (id INTEGER PRIMARY KEY, inicial_porcentaje TEXT, interes_mensual TEXT, cantidad_cuotas TEXT, simbolo_moneda TEXT, lugares_decimales TEXT, fecha_actualizacion TEXT)',
  );
  await db.execute(
    'CREATE TABLE configuracion (clave TEXT PRIMARY KEY, valor TEXT, fecha_actualizacion TEXT)',
  );
  await db.execute(
    'CREATE TABLE ventas (id INTEGER PRIMARY KEY, sync_id TEXT, cliente_id INTEGER, solar_id INTEGER, usuario_id INTEGER, vendedor_id INTEGER, fecha_venta TEXT, precio_venta REAL, saldo_pendiente REAL, estado TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE cuotas (id INTEGER PRIMARY KEY, sync_id TEXT, venta_id INTEGER, numero_cuota INTEGER, capital_cuota REAL, interes_cuota REAL, monto_cuota REAL, monto_pagado REAL, estado TEXT, deleted_at TEXT)',
  );
  await db.execute(
    'CREATE TABLE pagos (id INTEGER PRIMARY KEY, sync_id TEXT, venta_id INTEGER, cliente_id INTEGER, cuota_id INTEGER, monto_pagado REAL, tipo_pago TEXT, deleted_at TEXT)',
  );
  for (final table in SqliteMigrationTool.excludedTables) {
    await db.execute(
      'CREATE TABLE $table (id INTEGER PRIMARY KEY, value TEXT)',
    );
  }
}

Future<void> _seedSyntheticData(Database db) async {
  final batch = db.batch();
  for (var i = 1; i <= 40; i++) {
    batch.insert('clientes', {
      'id': i,
      'sync_id': 'client-$i',
      'nombre': 'Cliente $i',
      'cedula': 'C$i',
      'telefono': '809000${i.toString().padLeft(4, '0')}',
    });
  }
  for (var i = 1; i <= 10; i++) {
    batch.insert('vendedores', {
      'id': i,
      'sync_id': 'seller-$i',
      'nombre': 'Vendedor $i',
    });
    batch.insert('usuarios', {
      'id': i,
      'sync_id': 'user-$i',
      'nombre': 'Usuario $i',
      'email': 'user$i@test.local',
      'rol': i == 1 ? 'admin' : 'vendedor',
      'password_hash': 'hash',
      'activo': 1,
    });
  }
  for (var i = 1; i <= 80; i++) {
    batch.insert('solares', {
      'id': i,
      'sync_id': 'lot-$i',
      'manzana_numero': 'M${(i / 10).ceil()}',
      'solar_numero': '$i',
      'metros_cuadrados': 200,
      'precio_por_metro': 1000,
      'estado': i <= 20
          ? 'vendido'
          : i <= 30
          ? 'reservado'
          : 'disponible',
    });
  }
  for (var i = 1; i <= 3; i++) {
    batch.insert('roles', {
      'id': i,
      'sync_id': 'role-$i',
      'code': i == 1 ? 'ADMIN' : 'TECH_$i',
      'name': 'Role $i',
    });
    batch.insert('permisos', {
      'id': i,
      'sync_id': 'perm-$i',
      'usuario_id': i,
      'modulo': 'ventas',
      'acciones': '["ver","crear"]',
    });
    batch.insert('user_roles', {
      'id': i,
      'sync_id': 'user-role-$i',
      'user_id': i,
      'role_id': i,
    });
    batch.insert('role_permissions', {
      'id': i,
      'sync_id': 'role-perm-$i',
      'role_id': i,
      'permission_id': i,
    });
  }
  batch.insert('company_profiles', {
    'id': 1,
    'sync_id': 'company-profile-1',
    'name': 'EL ALTO DE DONA MAMITA',
    'phone': '8090000000',
    'address': 'Direccion',
    'upload_status': 'uploaded',
  });
  batch.insert('informacion_empresa', {
    'id': 1,
    'nombre': 'EL ALTO DE DONA MAMITA',
    'telefono': '8090000000',
    'direccion': 'Direccion',
    'fecha_creacion': DateTime.now().toIso8601String(),
    'fecha_actualizacion': DateTime.now().toIso8601String(),
  });
  batch.insert('parametros_financieros', {
    'id': 1,
    'inicial_porcentaje': '10',
    'interes_mensual': '1',
    'cantidad_cuotas': '12',
    'simbolo_moneda': 'RD\$',
    'lugares_decimales': '2',
    'fecha_actualizacion': DateTime.now().toIso8601String(),
  });
  batch.insert('configuracion', {
    'clave': 'default_payment_method',
    'valor': 'efectivo',
    'fecha_actualizacion': DateTime.now().toIso8601String(),
  });
  for (var sale = 1; sale <= 20; sale++) {
    batch.insert('ventas', {
      'id': sale,
      'sync_id': 'sale-$sale',
      'cliente_id': sale,
      'solar_id': sale,
      'usuario_id': 1,
      'vendedor_id': (sale % 10) + 1,
      'fecha_venta': DateTime(2026, 1, 1).toIso8601String(),
      'precio_venta': 200000,
      'saldo_pendiente': sale <= 2 ? 0 : 180000,
      'estado': sale <= 2
          ? 'pagada'
          : sale <= 18
          ? 'activa'
          : 'cancelada',
      'deleted_at': sale > 18 ? DateTime(2026, 3, 1).toIso8601String() : null,
    });
    for (var installment = 1; installment <= 12; installment++) {
      final id = ((sale - 1) * 12) + installment;
      batch.insert('cuotas', {
        'id': id,
        'sync_id': 'installment-$id',
        'venta_id': sale,
        'numero_cuota': installment,
        'capital_cuota': 15000,
        'interes_cuota': 1500,
        'monto_cuota': 16500,
        'monto_pagado': installment == 1 ? 16500 : 0,
        'estado': installment == 1 ? 'pagada' : 'pendiente',
      });
    }
    batch.insert('pagos', {
      'id': sale,
      'sync_id': 'payment-$sale',
      'venta_id': sale,
      'cliente_id': sale,
      'cuota_id': ((sale - 1) * 12) + 1,
      'monto_pagado': 16500,
      'tipo_pago': sale % 5 == 0 ? 'abono_capital' : 'cuota',
    });
  }
  await batch.commit(noResult: true);
}
