import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../database/database_schema.dart';
import '../resilience/app_storage_namespace.dart';

/// Cache de solo lectura (last-known-good) para listados de modulos.
///
/// Guarda el snapshot JSON de la ultima lista valida obtenida desde el backend
/// (PostgreSQL) para que cada modulo pueda mostrarse de inmediato (cache-first)
/// mientras refresca en segundo plano. Local = cache; nunca es autoridad.
class ListSnapshotStore {
  ListSnapshotStore(this._appDatabase, {required this.entity});

  final AppDatabase _appDatabase;
  final String entity;
  static final Map<String, String> _memoryPayloadByKey = <String, String>{};

  String get _cacheKey => '$entity:default';
  String get _preferencesKey =>
      AppStorageNamespace.scopedKey('list_snapshot.$_cacheKey');

  /// Lee el snapshot de items (lista de maps). Best-effort: null si no hay.
  Future<List<dynamic>?> read() async {
    final fastPayload = await _readFastPayload();
    final fastItems = _decodeItems(fastPayload);
    if (fastItems != null) {
      return fastItems;
    }

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
      final payload = rows.first['payload'] as String? ?? '{}';
      _rememberFastPayload(payload);
      return _decodeItems(payload);
    } catch (_) {
      return null;
    }
  }

  /// Escribe el snapshot (best-effort, nunca lanza).
  Future<void> write(List<Map<String, dynamic>> items) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({'savedAt': now, 'items': items});
    _rememberFastPayload(payload);
    _persistFastPayload(payload);
    try {
      final db = await _appDatabase.database;
      await db.insert(
        DatabaseSchema.listSnapshotsTable,
        {
          'cache_key': _cacheKey,
          'query': '',
          'payload': payload,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Best-effort: una falla de cache nunca debe romper la lectura.
    }
  }

  /// Invalida el snapshot (best-effort).
  Future<void> clear() async {
    _memoryPayloadByKey.remove(_preferencesKey);
    _removeFastPayload();
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
    final encoded = jsonEncode(payload);
    _rememberFastPayload(encoded);
    _persistFastPayload(encoded);
    try {
      final db = await _appDatabase.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(
        DatabaseSchema.listSnapshotsTable,
        {
          'cache_key': _cacheKey,
          'query': '',
          'payload': encoded,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Lee un payload JSON arbitrario (best-effort: null si no existe).
  Future<Object?> readJson() async {
    final fastPayload = await _readFastPayload();
    if (fastPayload != null) {
      try {
        return jsonDecode(fastPayload);
      } catch (_) {
        // Continua con SQLite si el snapshot rapido esta corrupto.
      }
    }

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
      final payload = rows.first['payload'] as String? ?? 'null';
      _rememberFastPayload(payload);
      return jsonDecode(payload);
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? _decodeItems(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return null;
      }
      final items = decoded['items'];
      return items is List ? items : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readFastPayload() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final payload = preferences.getString(_preferencesKey);
      if (payload != null && payload.trim().isNotEmpty) {
        _memoryPayloadByKey[_preferencesKey] = payload;
        return payload;
      }
      _memoryPayloadByKey.remove(_preferencesKey);
      return null;
    } catch (_) {
      final memory = _memoryPayloadByKey[_preferencesKey];
      return memory != null && memory.trim().isNotEmpty ? memory : null;
    }
  }

  void _rememberFastPayload(String payload) {
    if (payload.trim().isNotEmpty) {
      _memoryPayloadByKey[_preferencesKey] = payload;
    }
  }

  void _persistFastPayload(String payload) {
    Future<void>(() async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_preferencesKey, payload);
      } catch (_) {
        // Best-effort: es optimizacion de UX, no fuente de verdad.
      }
    });
  }

  void _removeFastPayload() {
    Future<void>(() async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_preferencesKey);
      } catch (_) {
        // Best-effort.
      }
    });
  }
}
