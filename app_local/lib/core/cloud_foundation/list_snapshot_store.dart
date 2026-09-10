import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../database/database_schema.dart';

/// Cache de solo lectura (last-known-good) para listados de modulos.
///
/// Guarda el snapshot JSON de la ultima lista valida obtenida desde el backend
/// (PostgreSQL) para que cada modulo pueda mostrarse de inmediato (cache-first)
/// mientras refresca en segundo plano. Local = cache; nunca es autoridad.
class ListSnapshotStore {
  ListSnapshotStore(this._appDatabase, {required this.entity});

  final AppDatabase _appDatabase;
  final String entity;

  String get _cacheKey => '$entity:default';

  /// Lee el snapshot de items (lista de maps). Best-effort: null si no hay.
  Future<List<dynamic>?> read() async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.listSnapshotsTable,
        columns: ['payload'],
        where: 'cache_key = ?',
        whereArgs: [_cacheKey],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(rows.first['payload'] as String? ?? '{}');
      if (decoded is! Map) {
        return null;
      }
      final items = decoded['items'];
      return items is List ? items : null;
    } catch (_) {
      return null;
    }
  }

  /// Escribe el snapshot (best-effort, nunca lanza).
  Future<void> write(List<Map<String, dynamic>> items) async {
    try {
      final db = await _appDatabase.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(DatabaseSchema.listSnapshotsTable, {
        'cache_key': _cacheKey,
        'query': '',
        'payload': jsonEncode({'savedAt': now, 'items': items}),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Best-effort: una falla de cache nunca debe romper la lectura.
    }
  }

  /// Invalida el snapshot (best-effort).
  Future<void> clear() async {
    try {
      final db = await _appDatabase.database;
      await db.delete(
        DatabaseSchema.listSnapshotsTable,
        where: 'cache_key = ?',
        whereArgs: [_cacheKey],
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Escribe un payload JSON arbitrario (best-effort, nunca lanza).
  Future<void> writeJson(Object? payload) async {
    try {
      final db = await _appDatabase.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(DatabaseSchema.listSnapshotsTable, {
        'cache_key': _cacheKey,
        'query': '',
        'payload': jsonEncode(payload),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Lee un payload JSON arbitrario (best-effort: null si no existe).
  Future<Object?> readJson() async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.listSnapshotsTable,
        columns: ['payload'],
        where: 'cache_key = ?',
        whereArgs: [_cacheKey],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return jsonDecode(rows.first['payload'] as String? ?? 'null');
    } catch (_) {
      return null;
    }
  }
}
