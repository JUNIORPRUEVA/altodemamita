import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class RolesSyncRepository implements SyncRepository {
  RolesSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'roles';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.rolesTable,
      where: 'sync_status IN (?, ?, ?, ?, ?)',
      whereArgs: [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
      orderBy: 'updated_at ASC',
    );
    return rows
        .map(
          (row) => {
            'id': row['id'],
            'id_remote': row['id_remote'],
            'sync_id': row['sync_id'],
            'code': row['code'],
            'name': row['name'],
            'description': row['description'],
            'created_at': row['created_at'],
            'updated_at': row['updated_at'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    await _markRows(syncIds, DatabaseSchema.syncStatusSynced);
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    await _markRows(syncIds, DatabaseSchema.syncStatusConflict);
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return;
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      for (final record in records) {
        final syncId = record['sync_id']?.toString().trim() ?? '';
        if (syncId.isEmpty) continue;

        final remoteId = record['id']?.toString().trim();
        var existing = await txn.query(
          DatabaseSchema.rolesTable,
          columns: ['id'],
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existing.isEmpty && remoteId != null && remoteId.isNotEmpty) {
          existing = await txn.query(
            DatabaseSchema.rolesTable,
            columns: ['id'],
            where: 'id_remote = ?',
            whereArgs: [remoteId],
            limit: 1,
          );
        }

        final values = {
          'sync_id': syncId,
          'id_remote': remoteId,
          'id_local': existing.isEmpty ? null : existing.first['id'],
          'code': record['code']?.toString() ?? '',
          'name': record['name']?.toString() ?? '',
          'description': record['description']?.toString(),
          'created_at': record['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': record['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'last_modified_remote': record['updated_at']?.toString(),
          'deleted_at': record['deleted_at']?.toString(),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existing.isEmpty) {
          await txn.insert(DatabaseSchema.rolesTable, values);
        } else {
          await txn.update(
            DatabaseSchema.rolesTable,
            values,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }
    });
  }

  Future<void> _markRows(Iterable<String> syncIds, String status) async {
    final ids = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;
    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.rolesTable} SET sync_status = ? WHERE sync_id IN ($placeholders)',
      [status, ...ids],
    );
  }
}
