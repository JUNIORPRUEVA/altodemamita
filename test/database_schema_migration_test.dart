import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_schema_migration_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'migracion v12 conserva cuota parcial y reproyecta cuotas futuras intactas',
    () async {
      final dbPath = path.join(tempDirectory.path, 'migration.db');
      final db = await databaseFactory.openDatabase(dbPath);

      await db.execute('''
        CREATE TABLE usuarios (
          id INTEGER PRIMARY KEY,
          nombre TEXT,
          email TEXT,
          password_hash TEXT,
          password_reset_required INTEGER,
          rol TEXT,
          activo INTEGER,
          telefono TEXT,
          fecha_creacion TEXT,
          fecha_actualizacion TEXT,
          password_updated_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE configuracion (
          clave TEXT PRIMARY KEY,
          valor TEXT NOT NULL,
          fecha_actualizacion TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE ventas (
          id INTEGER PRIMARY KEY,
          saldo_pendiente REAL NOT NULL,
          interes_mensual REAL NOT NULL,
          cantidad_cuotas INTEGER NOT NULL,
          estado TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE cuotas (
          id INTEGER PRIMARY KEY,
          venta_id INTEGER NOT NULL,
          numero_cuota INTEGER NOT NULL,
          fecha_vencimiento TEXT NOT NULL,
          saldo_inicial REAL NOT NULL,
          capital_cuota REAL NOT NULL,
          interes_cuota REAL NOT NULL,
          monto_cuota REAL NOT NULL,
          monto_pagado REAL NOT NULL,
          capital_pagado REAL NOT NULL,
          interes_pagado REAL NOT NULL,
          saldo_final REAL NOT NULL,
          estado TEXT NOT NULL,
          fecha_creacion TEXT NOT NULL,
          fecha_actualizacion TEXT NOT NULL
        )
      ''');

      final now = DateTime(2026, 3, 31);
      final nowIso = now.toIso8601String();
      final due2 = DateTime(2026, 5, 31).toIso8601String();
      final due3 = DateTime(2026, 6, 30).toIso8601String();

      await db.insert('ventas', {
        'id': 1,
        'saldo_pendiente': 889000.0,
        'interes_mensual': 1.0,
        'cantidad_cuotas': 12,
        'estado': 'activa',
      });

      await db.insert('cuotas', {
        'id': 1,
        'venta_id': 1,
        'numero_cuota': 1,
        'fecha_vencimiento': DateTime(2026, 4, 30).toIso8601String(),
        'saldo_inicial': 900000.0,
        'capital_cuota': 75000.0,
        'interes_cuota': 9000.0,
        'monto_cuota': 84000.0,
        'monto_pagado': 20000.0,
        'capital_pagado': 11000.0,
        'interes_pagado': 9000.0,
        'saldo_final': 825000.0,
        'estado': 'parcial',
        'fecha_creacion': nowIso,
        'fecha_actualizacion': nowIso,
      });
      await db.insert('cuotas', {
        'id': 2,
        'venta_id': 1,
        'numero_cuota': 2,
        'fecha_vencimiento': due2,
        'saldo_inicial': 825000.0,
        'capital_cuota': 75000.0,
        'interes_cuota': 8250.0,
        'monto_cuota': 83250.0,
        'monto_pagado': 0.0,
        'capital_pagado': 0.0,
        'interes_pagado': 0.0,
        'saldo_final': 750000.0,
        'estado': 'pendiente',
        'fecha_creacion': nowIso,
        'fecha_actualizacion': nowIso,
      });
      await db.insert('cuotas', {
        'id': 3,
        'venta_id': 1,
        'numero_cuota': 3,
        'fecha_vencimiento': due3,
        'saldo_inicial': 750000.0,
        'capital_cuota': 75000.0,
        'interes_cuota': 7500.0,
        'monto_cuota': 82500.0,
        'monto_pagado': 0.0,
        'capital_pagado': 0.0,
        'interes_pagado': 0.0,
        'saldo_final': 675000.0,
        'estado': 'pendiente',
        'fecha_creacion': nowIso,
        'fecha_actualizacion': nowIso,
      });

      await DatabaseSchema.migrate(db, 11, 12);

      final rows = await db.query(
        'cuotas',
        where: 'venta_id = ?',
        whereArgs: [1],
        orderBy: 'numero_cuota ASC',
      );

      expect(rows, hasLength(3));

      final partialInstallment = rows[0];
      expect(partialInstallment['estado'], 'parcial');
      expect(partialInstallment['monto_pagado'], 20000.0);
      expect(partialInstallment['capital_pagado'], 11000.0);
      expect(partialInstallment['interes_pagado'], 9000.0);
      expect(partialInstallment['capital_cuota'], 75000.0);
      expect(partialInstallment['interes_cuota'], 9000.0);

      final secondInstallment = rows[1];
      final thirdInstallment = rows[2];

      expect(secondInstallment['monto_pagado'], 0.0);
      expect(thirdInstallment['monto_pagado'], 0.0);
      expect(secondInstallment['monto_cuota'], thirdInstallment['monto_cuota']);
      expect(secondInstallment['saldo_inicial'], 825000.0);
      expect(
        (secondInstallment['interes_cuota'] as num).toDouble(),
        greaterThan((thirdInstallment['interes_cuota'] as num).toDouble()),
      );
      expect(
        (secondInstallment['capital_cuota'] as num).toDouble(),
        lessThan((thirdInstallment['capital_cuota'] as num).toDouble()),
      );
      expect(thirdInstallment['saldo_final'], 0.0);

      await db.close();
    },
  );

  test(
    'migracion v13 transforma precio total legado a precio por metro',
    () async {
      final dbPath = path.join(tempDirectory.path, 'migration_v13.db');
      final db = await databaseFactory.openDatabase(dbPath);

      await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        email TEXT,
        password_hash TEXT,
        password_reset_required INTEGER,
        rol TEXT,
        activo INTEGER,
        telefono TEXT,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT,
        password_updated_at TEXT
      )
    ''');
      await db.execute('''
      CREATE TABLE configuracion (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

      await db.execute('''
      CREATE TABLE solares (
        id INTEGER PRIMARY KEY,
        manzana_numero TEXT NOT NULL,
        solar_numero TEXT NOT NULL,
        metros_cuadrados REAL NOT NULL,
        precio REAL NOT NULL,
        estado TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

      final nowIso = DateTime(2026, 3, 31).toIso8601String();
      await db.insert('solares', {
        'id': 1,
        'manzana_numero': 'A',
        'solar_numero': '10',
        'metros_cuadrados': 200.0,
        'precio': 1000000.0,
        'estado': 'disponible',
        'fecha_creacion': nowIso,
        'fecha_actualizacion': nowIso,
      });

      await DatabaseSchema.migrate(db, 12, 13);

      final columns = await db.rawQuery('PRAGMA table_info(solares)');
      final columnNames = columns
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      expect(columnNames, contains('precio_por_metro'));

      final rows = await db.query('solares', where: 'id = ?', whereArgs: [1]);
      expect(rows, hasLength(1));
      expect(rows.single['precio_por_metro'], 5000.0);

      await db.close();
    },
  );

  test('migracion v13 no falla cuando ventas referencia solares', () async {
    final dbPath = path.join(tempDirectory.path, 'migration_v13_with_sales.db');
    final db = await databaseFactory.openDatabase(dbPath);

    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        email TEXT,
        password_hash TEXT,
        password_reset_required INTEGER,
        rol TEXT,
        activo INTEGER,
        telefono TEXT,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT,
        password_updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE configuracion (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY,
        nombre_completo TEXT,
        cedula TEXT,
        telefono TEXT,
        direccion TEXT,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE vendedores (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        cedula TEXT,
        telefono TEXT,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE solares (
        id INTEGER PRIMARY KEY,
        manzana_numero TEXT NOT NULL,
        solar_numero TEXT NOT NULL,
        metros_cuadrados REAL NOT NULL,
        precio REAL NOT NULL,
        estado TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE ventas (
        id INTEGER PRIMARY KEY,
        cliente_id INTEGER NOT NULL,
        solar_id INTEGER NOT NULL UNIQUE,
        usuario_id INTEGER NOT NULL,
        vendedor_id INTEGER,
        fecha_venta TEXT NOT NULL,
        precio_venta REAL NOT NULL DEFAULT 0,
        inicial_porcentaje REAL NOT NULL DEFAULT 0,
        inicial_monto REAL NOT NULL DEFAULT 0,
        monto_inicial_requerido REAL NOT NULL DEFAULT 0,
        monto_inicial_pagado REAL NOT NULL DEFAULT 0,
        monto_inicial_pendiente REAL NOT NULL DEFAULT 0,
        monto_apartado_minimo REAL,
        fecha_limite_inicial TEXT,
        fecha_activacion TEXT,
        saldo_financiado REAL NOT NULL DEFAULT 0,
        saldo_pendiente REAL NOT NULL DEFAULT 0,
        interes_mensual REAL NOT NULL DEFAULT 0,
        cantidad_cuotas INTEGER NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'apartado',
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        FOREIGN KEY(cliente_id) REFERENCES clientes(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(solar_id) REFERENCES solares(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(usuario_id) REFERENCES usuarios(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(vendedor_id) REFERENCES vendedores(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL
      )
    ''');

    final nowIso = DateTime(2026, 3, 31).toIso8601String();
    await db.insert('usuarios', {
      'id': 1,
      'nombre': 'Admin',
      'email': 'admin@test.local',
      'password_hash': '',
      'password_reset_required': 0,
      'rol': 'admin',
      'activo': 1,
      'telefono': '',
      'fecha_creacion': nowIso,
      'fecha_actualizacion': nowIso,
      'password_updated_at': nowIso,
    });
    await db.insert('clientes', {
      'id': 1,
      'nombre_completo': 'Cliente',
      'cedula': '001',
      'telefono': '',
      'direccion': '',
      'fecha_creacion': nowIso,
      'fecha_actualizacion': nowIso,
    });
    await db.insert('vendedores', {
      'id': 1,
      'nombre': 'Vendedor',
      'cedula': '002',
      'telefono': '',
      'fecha_creacion': nowIso,
      'fecha_actualizacion': nowIso,
    });
    await db.insert('solares', {
      'id': 1,
      'manzana_numero': 'A',
      'solar_numero': '10',
      'metros_cuadrados': 200.0,
      'precio': 1000000.0,
      'estado': 'vendido',
      'fecha_creacion': nowIso,
      'fecha_actualizacion': nowIso,
    });
    await db.insert('ventas', {
      'id': 1,
      'cliente_id': 1,
      'solar_id': 1,
      'usuario_id': 1,
      'vendedor_id': 1,
      'fecha_venta': nowIso,
      'precio_venta': 1000000.0,
      'inicial_porcentaje': 10.0,
      'inicial_monto': 100000.0,
      'monto_inicial_requerido': 100000.0,
      'monto_inicial_pagado': 100000.0,
      'monto_inicial_pendiente': 0.0,
      'monto_apartado_minimo': 0.0,
      'fecha_limite_inicial': nowIso,
      'fecha_activacion': nowIso,
      'saldo_financiado': 900000.0,
      'saldo_pendiente': 900000.0,
      'interes_mensual': 1.0,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': nowIso,
      'fecha_actualizacion': nowIso,
    });

    await DatabaseSchema.migrate(db, 12, 13);

    final lotRows = await db.query('solares', where: 'id = ?', whereArgs: [1]);
    expect(lotRows, hasLength(1));
    expect(lotRows.single['precio_por_metro'], 5000.0);

    final salesRows = await db.query('ventas', where: 'id = ?', whereArgs: [1]);
    expect(salesRows, hasLength(1));
    expect(salesRows.single['solar_id'], 1);

    await db.close();
  });

  test(
    'migracion v19 agrega metadata offline-first sin perder datos',
    () async {
      final dbPath = path.join(tempDirectory.path, 'migration_v19.db');
      final db = await databaseFactory.openDatabase(dbPath);

      await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        email TEXT,
        password_hash TEXT,
        password_reset_required INTEGER,
        rol TEXT,
        activo INTEGER,
        telefono TEXT,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT,
        password_updated_at TEXT
      )
    ''');

      await db.execute('''
      CREATE TABLE configuracion (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

      await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY,
        sync_id TEXT,
        version INTEGER DEFAULT 1,
        nombre TEXT NOT NULL,
        cedula TEXT NOT NULL,
        telefono TEXT,
        direccion TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

      final nowIso = DateTime(2026, 5, 3, 12, 0).toIso8601String();
      await db.insert('clientes', {
        'id': 7,
        'sync_id': 'client-v19',
        'version': 3,
        'nombre': 'Cliente Metadata',
        'cedula': '001-0000000-7',
        'telefono': '8095550007',
        'direccion': 'Migracion',
        'fecha_creacion': nowIso,
        'fecha_actualizacion': nowIso,
        'deleted_at': null,
        'sync_status': 'pending',
      });

      await DatabaseSchema.migrate(db, 18, 19);

      final columns = await db.rawQuery('PRAGMA table_info(clientes)');
      final columnNames = columns
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      expect(
        columnNames,
        containsAll({
          'id_local',
          'id_remote',
          'last_modified_local',
          'last_modified_remote',
        }),
      );

      final rows = await db.query(
        'clientes',
        columns: [
          'id',
          'id_local',
          'id_remote',
          'last_modified_local',
          'last_modified_remote',
          'sync_status',
        ],
        where: 'id = ?',
        whereArgs: [7],
        limit: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.single['id_local'], 7);
      expect(rows.single['id_remote'], isNull);
      expect(rows.single['last_modified_local'], nowIso);
      expect(rows.single['last_modified_remote'], isNull);
      expect(
        rows.single['sync_status'],
        DatabaseSchema.syncStatusPendingCreate,
      );

      await db.close();
    },
  );

  test('migracion v20 crea tablas de paridad y columnas de media offline', () async {
    final dbPath = path.join(tempDirectory.path, 'migration_v20.db');
    final db = await databaseFactory.openDatabase(dbPath);

    final nowIso = DateTime(2026, 5, 3, 14, 0).toIso8601String();
    await db.execute('''
      CREATE TABLE informacion_empresa (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        telefono TEXT,
        direccion TEXT,
        logo_base64 TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        sync_status TEXT,
        id_remote TEXT,
        last_modified_local TEXT,
        last_modified_remote TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT,
        email TEXT,
        password_hash TEXT,
        password_reset_required INTEGER,
        rol TEXT,
        activo INTEGER,
        telefono TEXT,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT,
        password_updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE configuracion (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE permisos (
        id INTEGER PRIMARY KEY,
        modulo TEXT,
        acciones TEXT,
        fecha_creacion TEXT
      )
    ''');

    await db.insert('informacion_empresa', {
      'id': 1,
      'nombre': 'Empresa Demo',
      'telefono': '8095550001',
      'direccion': 'Zona Norte',
      'logo_base64': null,
      'fecha_creacion': nowIso,
      'fecha_actualizacion': nowIso,
      'sync_status': 'synced',
      'id_remote': null,
      'last_modified_local': nowIso,
      'last_modified_remote': null,
      'deleted_at': null,
    });

    await DatabaseSchema.migrate(db, 19, 20);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).whereType<String>().toSet();
    expect(
      names,
      containsAll({
        DatabaseSchema.rolesTable,
        DatabaseSchema.userRolesTable,
        DatabaseSchema.rolePermissionsTable,
        DatabaseSchema.companyProfilesTable,
      }),
    );

    final companyColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseSchema.companyInfoTable})',
    );
    final companyColumnNames = companyColumns
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    expect(
      companyColumnNames,
      containsAll({'local_path', 'remote_url', 'upload_status'}),
    );

    final mirrored = await db.query(DatabaseSchema.companyProfilesTable, limit: 1);
    expect(mirrored, hasLength(1));
    expect(mirrored.first['name'], 'Empresa Demo');

    await db.close();
  });
}
