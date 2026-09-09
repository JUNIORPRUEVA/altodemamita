import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class CacheRepository {
  const CacheRepository(this.database);

  final Database database;

  Future<void> upsertRecord({
    required String entity,
    required String id,
    String? syncId,
    required Map<String, Object?> payload,
    String status = 'CONFIRMED',
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now().toUtc()).toIso8601String();
    await database.insert('cache_records', {
      'entity': entity,
      'id': id,
      'sync_id': syncId,
      'payload': jsonEncode(payload),
      'status': status,
      'updated_at': now,
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listEntity(String entity) async {
    final rows = await database.query(
      'cache_records',
      where: 'entity = ? AND deleted_at IS NULL',
      whereArgs: [entity],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) {
          final decoded = jsonDecode(row['payload'] as String);
          return decoded is Map
              ? decoded.map((key, value) => MapEntry(key.toString(), value))
              : <String, Object?>{};
        })
        .toList(growable: false);
  }

  Future<void> putMetadata(String key, String value) async {
    await database.insert('cache_metadata', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
