import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DeviceStateRepository {
  const DeviceStateRepository(this.database);

  final Database database;

  Future<void> put(String key, String value) async {
    await database.insert('device_state', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> get(String key) async {
    final rows = await database.query(
      'device_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> putCursor(String scope, String? cursor) async {
    await database.insert('sync_cursors', {
      'scope': scope,
      'cursor': cursor,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getCursor(String scope) async {
    final rows = await database.query(
      'sync_cursors',
      columns: ['cursor'],
      where: 'scope = ?',
      whereArgs: [scope],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['cursor'] as String?;
  }
}
