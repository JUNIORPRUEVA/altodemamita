import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../resilience/app_paths.dart';
import 'database_schema.dart';

/// Servicio de reparación automática e idempotente para solares.
///
/// Corre durante la migración v28 y también puede ejecutarse bajo demanda
/// si se detectan triggers/índices incorrectos.
///
/// Reglas:
/// - NO borra DB ni datos locales.
/// - Hace backup antes de cualquier UPDATE.
/// - Solo repara casos seguros.
/// - Idempotente: puede correr muchas veces sin dañar nada.
/// - Deja log detallado de cada paso.
class LotRepairService {
  static const String _logTag = '[LotRepair]';

  /// Punto de entrada principal para la reparación.
  ///
  /// [db] es la base de datos SQLite local.
  /// [appPaths] se usa para crear el backup.
  /// [force] si es true, repara aunque la marca de completado exista.
  static Future<void> run({
    required DatabaseExecutor db,
    AppPaths? appPaths,
    bool force = false,
  }) async {
    _log('started');

    // 1. Verificar si ya se completó (a menos que force=true)
    if (!force && await _isRepairCompleted(db)) {
      _log('already completed, skipping');
      return;
    }

    // 2. Hacer backup
    final backupPath = await _createBackup(appPaths);
    _log('backup created path=$backupPath');

    // 3. Reparar triggers
    await _repairTriggers(db);
    _log('triggers recreated');

    // 4. Reparar índice
    await _repairIndex(db);
    _log('index recreated');

    // 5. Reparar solares eliminados con estado vendido/reservado
    final deletedSoldRepaired = await _repairDeletedSoldLots(db);
    _log('deleted sold lots repaired=$deletedSoldRepaired');

    // 6. Reparar solares activos vendidos sin venta activa
    final activeSoldRepaired = await _repairActiveSoldWithoutSale(db);
    _log('active sold without active sale repaired=$activeSoldRepaired');

    // 7. Marcar como completado
    await _markRepairCompleted(db);
    _log('completed');

    // 8. Log resumen
    _log(
      'summary: triggers=recreated, index=recreated, '
      'deletedSoldFixed=$deletedSoldRepaired, '
      'activeSoldFixed=$activeSoldRepaired',
    );
  }

  /// Verifica si la reparación ya se completó revisando los triggers actuales.
  static Future<bool> _isRepairCompleted(DatabaseExecutor db) async {
    // Verificar que los triggers existan y tengan la lógica correcta
    final triggers = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' "
      "AND tbl_name = '${DatabaseSchema.lotsTable}' "
      "AND name = 'trg_solares_no_duplicate_active_insert'",
    );

    if (triggers.isEmpty) {
      return false;
    }

    final sql = triggers.first['sql'] as String? ?? '';
    // Verificar que el trigger use manzana_numero + solar_numero combinados
    if (!sql.contains('manzana_numero') || !sql.contains('solar_numero')) {
      return false;
    }

    // Verificar que el índice use ambas columnas
    final indexes = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
      "AND tbl_name = '${DatabaseSchema.lotsTable}' "
      "AND name = 'idx_solares_active_key_normalized'",
    );

    if (indexes.isEmpty) {
      return false;
    }

    final indexSql = indexes.first['sql'] as String? ?? '';
    if (!indexSql.contains('manzana_numero') ||
        !indexSql.contains('solar_numero')) {
      return false;
    }

    return true;
  }

  /// Crea un backup del archivo DB antes de cualquier modificación.
  static Future<String> _createBackup(AppPaths? appPaths) async {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';

    final dbDir = appPaths?.databaseDirectory ?? _getDefaultDatabaseDir();
    final backupDir = Directory(p.join(dbDir, 'backups'));
    await backupDir.create(recursive: true);

    final dbPath = p.join(dbDir, DatabaseSchema.databaseName);
    final backupPath = p.join(
      backupDir.path,
      'sistema_solares_before_lot_repair_$timestamp.db',
    );

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.copy(backupPath);
    }

    return backupPath;
  }

  /// Obtiene el directorio por defecto de la DB.
  static String _getDefaultDatabaseDir() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return p.join(
      home,
      'AppData',
      'Local',
      'SistemaSolares',
      'data',
      'database',
    );
  }

  /// Repara los triggers de solares.
  ///
  /// Elimina triggers viejos (que solo validaban solar_numero) y
  /// crea los nuevos que validan manzana_numero + solar_numero combinados.
  static Future<void> _repairTriggers(DatabaseExecutor db) async {
    // Eliminar triggers viejos (usando DROP IF EXISTS para ser idempotente)
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_solares_no_duplicate_active_insert',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_solares_no_duplicate_active_update',
    );

    // Crear triggers nuevos con validación correcta
    await db.execute('''
      CREATE TRIGGER trg_solares_no_duplicate_active_insert
      BEFORE INSERT ON ${DatabaseSchema.lotsTable}
      WHEN NEW.deleted_at IS NULL
        AND EXISTS (
          SELECT 1 FROM ${DatabaseSchema.lotsTable}
          WHERE deleted_at IS NULL
            AND LOWER(TRIM(manzana_numero)) = LOWER(TRIM(NEW.manzana_numero))
            AND LOWER(TRIM(solar_numero)) = LOWER(TRIM(NEW.solar_numero))
        )
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_ACTIVE_LOT');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_solares_no_duplicate_active_update
      BEFORE UPDATE OF manzana_numero, solar_numero, deleted_at
      ON ${DatabaseSchema.lotsTable}
      WHEN NEW.deleted_at IS NULL
        AND EXISTS (
          SELECT 1 FROM ${DatabaseSchema.lotsTable}
          WHERE id <> NEW.id
            AND deleted_at IS NULL
            AND LOWER(TRIM(manzana_numero)) = LOWER(TRIM(NEW.manzana_numero))
            AND LOWER(TRIM(solar_numero)) = LOWER(TRIM(NEW.solar_numero))
        )
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_ACTIVE_LOT');
      END
    ''');
  }

  /// Repara el índice idx_solares_active_key_normalized.
  ///
  /// Elimina el índice viejo (que solo indexaba solar_numero) y
  /// crea el nuevo que indexa (manzana_numero, solar_numero) combinados.
  static Future<void> _repairIndex(DatabaseExecutor db) async {
    // Eliminar índice viejo
    await db.execute(
      'DROP INDEX IF EXISTS idx_solares_active_key_normalized',
    );

    // Crear índice nuevo con ambas columnas
    await db.execute(
      'CREATE INDEX idx_solares_active_key_normalized '
      'ON ${DatabaseSchema.lotsTable}('
      'LOWER(TRIM(manzana_numero)), '
      'LOWER(TRIM(solar_numero))'
      ') '
      'WHERE deleted_at IS NULL',
    );
  }

  /// Repara solares eliminados que quedaron con estado vendido/reservado.
  ///
  /// Actualiza SOLO solares con deleted_at NOT NULL y estado en
  /// ('vendido', 'sold', 'reservado', 'reserved') a 'disponible'.
  ///
  /// Retorna la cantidad de registros actualizados.
  static Future<int> _repairDeletedSoldLots(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    final result = await db.rawUpdate('''
      UPDATE ${DatabaseSchema.lotsTable}
      SET
        estado = 'disponible',
        fecha_actualizacion = ?,
        last_modified_local = ?,
        sync_status = ?
      WHERE deleted_at IS NOT NULL
        AND LOWER(TRIM(COALESCE(estado, ''))) IN (
          'vendido', 'sold', 'reservado', 'reserved'
        )
    ''', [now, now, DatabaseSchema.syncStatusPendingUpdate]);

    return result;
  }

  /// Repara solares activos (deleted_at IS NULL) con estado vendido
  /// que NO tienen una venta activa real apuntando a ellos.
  ///
  /// No toca solares que tienen una venta activa real.
  /// Retorna la cantidad de registros actualizados.
  static Future<int> _repairActiveSoldWithoutSale(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    final result = await db.rawUpdate('''
      UPDATE ${DatabaseSchema.lotsTable}
      SET
        estado = 'disponible',
        fecha_actualizacion = ?,
        last_modified_local = ?,
        sync_status = ?
      WHERE deleted_at IS NULL
        AND LOWER(TRIM(COALESCE(estado, ''))) IN (
          'vendido', 'sold', 'reservado', 'reserved'
        )
        AND NOT EXISTS (
          SELECT 1 FROM ${DatabaseSchema.salesTable} v
          WHERE v.solar_id = ${DatabaseSchema.lotsTable}.id
            AND v.deleted_at IS NULL
            AND LOWER(TRIM(COALESCE(v.estado, ''))) NOT IN (
              'cancelada', 'cancelado',
              'anulada', 'anulado',
              'eliminada', 'eliminado'
            )
        )
    ''', [now, now, DatabaseSchema.syncStatusPendingUpdate]);

    return result;
  }

  /// Marca la reparación como completada en la tabla de configuración.
  static Future<void> _markRepairCompleted(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    // Verificar si la tabla configuracion existe
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = '${DatabaseSchema.settingsTable}'",
    );

    if (tables.isEmpty) {
      return;
    }

    // Verificar si la columna clave existe
    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseSchema.settingsTable})',
    );
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    if (!columnNames.contains('clave') || !columnNames.contains('valor')) {
      return;
    }

    await db.rawInsert(
      "INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} "
      "(clave, valor, fecha_actualizacion) "
      "VALUES (?, ?, ?)",
      ['lot_repair_v1_completed', 'true', now],
    );

    await db.rawInsert(
      "INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} "
      "(clave, valor, fecha_actualizacion) "
      "VALUES (?, ?, ?)",
      ['lot_repair_v1_completed_at', now, now],
    );
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');

  static void _log(String message) {
    print('$_logTag $message');
  }
}
