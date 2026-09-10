import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regresión del incidente INC-20260909-110818-46143.
///
/// Un caché local re-hidratado desde la nube puede contener tombstones
/// eliminados cuyo prefijo `__DELETED__<n>` corresponde a un id local ANTERIOR
/// (el id local cambió al re-hidratar). Cuando arranca la app,
/// `StartupRecoveryService._recoverDatabase` ejecuta
/// `DatabaseSchema.ensureCoreStructures` dentro de una transacción, y la
/// migración v24 intentaba anonimizar en un solo `UPDATE`:
///
///   UPDATE clientes SET cedula = '__DELETED__' || id
///   WHERE deleted_at IS NOT NULL AND ...
///
/// Si otro tombstone ya ocupaba ese valor canónico, SQLite lanzaba
/// `UNIQUE constraint failed: clientes.cedula` y la app entraba a la pantalla
/// de recuperación ("No pudimos dejar el sistema listo automáticamente") en
/// lugar de reparar el caché y seguir.
///
/// La anonimización ahora reserva un valor único (con sufijo si hace falta) y
/// no puede detener el arranque por una colisión UNIQUE.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp(
      'startup_anonymization_collision_',
    );
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'ensureCoreStructures anonimiza tombstones con colision UNIQUE sin entrar a recuperacion',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();

      Future<void> insertClient({
        required int id,
        required String syncId,
        required String cedula,
        required String? deletedAt,
      }) async {
        await db.insert(DatabaseSchema.clientsTable, {
          'id': id,
          'sync_id': syncId,
          'nombre': 'Cliente $id',
          'cedula': cedula,
          'telefono': '8090000000',
          'fecha_creacion': now,
          'fecha_actualizacion': now,
          'deleted_at': deletedAt,
          'sync_status': DatabaseSchema.syncStatusSynced,
        });
      }

      // Tombstone antiguo cuyo prefijo corresponde a un id local previo
      // (escenario real: caché re-hidratada, id local reasignado).
      await insertClient(
        id: 8,
        syncId: 'client-stale-8',
        cedula: '__DELETED__12',
        deletedAt: DateTime(2026, 5, 11).toIso8601String(),
      );

      // Borrados recientes que conservan la cédula real (aplicados por sync).
      await insertClient(
        id: 11,
        syncId: 'client-deleted-11',
        cedula: '1788926948116001',
        deletedAt: DateTime(2026, 9, 9, 4, 9).toIso8601String(),
      );
      await insertClient(
        id: 12,
        syncId: 'client-deleted-12',
        cedula: '1788927182981001',
        deletedAt: DateTime(2026, 9, 9, 4, 13).toIso8601String(),
      );

      // Mismo paso de arranque que StartupRecoveryService._recoverDatabase:
      // antes de la corrección, el UPDATE masivo de la migración v24 lanzaba
      // 'UNIQUE constraint failed: clientes.cedula' (error 2067).
      await expectLater(
        db.transaction(
          (txn) => DatabaseSchema.ensureCoreStructures(txn),
        ),
        completes,
      );

      final rows = await db.query(
        DatabaseSchema.clientsTable,
        where: 'id IN (?, ?, ?)',
        whereArgs: [8, 11, 12],
        orderBy: 'id ASC',
      );
      expect(rows, hasLength(3));

      final cedulas = <int, String>{
        for (final row in rows) row['id'] as int: '${row['cedula']}',
      };

      // El valor canónico se mantiene cuando está libre...
      expect(cedulas[11], '__DELETED__11');

      // ...y cuando el canónico ya está ocupado se reserva un valor único.
      expect(cedulas[12], isNot('__DELETED__12'));
      expect(cedulas[12]!.startsWith('__DELETED__12'), isTrue);

      final allCedulas = cedulas.values.toList();
      expect(
        allCedulas.toSet().length,
        allCedulas.length,
        reason: 'las cédulas anonimizadas deben ser únicas: $allCedulas',
      );
      expect(
        allCedulas.every((value) => value.startsWith('__DELETED__')),
        isTrue,
      );

      // Idempotente: un segundo arranque no cambia el estado ni lanza error.
      await expectLater(
        db.transaction(
          (txn) => DatabaseSchema.ensureCoreStructures(txn),
        ),
        completes,
      );

      final rowsAfterSecondPass = await db.query(
        DatabaseSchema.clientsTable,
        where: 'id IN (?, ?, ?)',
        whereArgs: [8, 11, 12],
        orderBy: 'id ASC',
      );
      final cedulasAfterSecondPass = <int, String>{
        for (final row in rowsAfterSecondPass)
          row['id'] as int: '${row['cedula']}',
      };
      expect(cedulasAfterSecondPass, equals(cedulas));

      // La tabla sigue aceptando un cliente activo nuevo con cédula real.
      await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-fresh-active',
        'nombre': 'Cliente Nuevo',
        'cedula': '40200000000',
        'telefono': '8091111111',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
    },
  );

  test(
    'migracion v24 tambien es a prueba de colisiones para vendedores',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();

      Future<void> insertSeller({
        required int id,
        required String syncId,
        required String cedula,
        required String? deletedAt,
      }) async {
        await db.insert(DatabaseSchema.sellersTable, {
          'id': id,
          'sync_id': syncId,
          'nombre': 'Vendedor $id',
          'cedula': cedula,
          'telefono': '8092222222',
          'fecha_creacion': now,
          'fecha_actualizacion': now,
          'deleted_at': deletedAt,
          'sync_status': DatabaseSchema.syncStatusSynced,
        });
      }

      // Tombstone vendedor con prefijo obsoleto que bloquearía el canónico.
      await insertSeller(
        id: 4,
        syncId: 'seller-stale-4',
        cedula: '__DELETED__5',
        deletedAt: DateTime(2026, 5, 11).toIso8601String(),
      );
      await insertSeller(
        id: 5,
        syncId: 'seller-deleted-5',
        cedula: '99887766',
        deletedAt: DateTime(2026, 9, 9, 4, 15).toIso8601String(),
      );

      await expectLater(
        db.transaction(
          (txn) => DatabaseSchema.ensureCoreStructures(txn),
        ),
        completes,
      );

      final sellers = await db.query(
        DatabaseSchema.sellersTable,
        where: 'id IN (?, ?)',
        whereArgs: [4, 5],
        orderBy: 'id ASC',
      );
      expect(sellers, hasLength(2));

      final cedulas = <int, String>{
        for (final row in sellers) row['id'] as int: '${row['cedula']}',
      };
      expect(
        cedulas.values.every((value) => value.startsWith('__DELETED__')),
        isTrue,
      );
      expect(cedulas[5], isNot('__DELETED__5'));
      expect(cedulas[5]!.startsWith('__DELETED__5'), isTrue);
      expect(cedulas.values.toSet().length, cedulas.length);
    },
  );
}
