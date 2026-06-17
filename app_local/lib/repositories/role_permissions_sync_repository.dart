import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class RolePermissionsSyncRepository implements SyncRepository {
  RolePermissionsSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'role_permissions';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.rolePermissionsTable,
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
            'role_id': row['role_id'],
            'permission_id': row['permission_id'],
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
          DatabaseSchema.rolePermissionsTable,
          columns: ['id'],
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existing.isEmpty && remoteId != null && remoteId.isNotEmpty) {
          existing = await txn.query(
            DatabaseSchema.rolePermissionsTable,
            columns: ['id'],
            where: 'id_remote = ?',
            whereArgs: [remoteId],
            limit: 1,
          );
        }

        final roleLocalId = await _resolveLocalId(
          txn,
          tableName: DatabaseSchema.rolesTable,
          syncId: record['role_sync_id']?.toString(),
          remoteId: record['role_id']?.toString(),
        );
        final permissionLocalId = await _resolveLocalId(
          txn,
          tableName: DatabaseSchema.permissionsTable,
          syncId: record['permission_sync_id']?.toString(),
          remoteId: record['permission_id']?.toString(),
        );
        if (roleLocalId == null || permissionLocalId == null) {
          continue;
        }

        final values = {
          'sync_id': syncId,
          'id_remote': remoteId,
          'id_local': existing.isEmpty ? null : existing.first['id'],
          'role_id': roleLocalId,
          'permission_id': permissionLocalId,
          'created_at':
              record['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at':
              record['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'last_modified_remote': record['updated_at']?.toString(),
          'deleted_at': record['deleted_at']?.toString(),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existing.isEmpty) {
          await txn.insert(DatabaseSchema.rolePermissionsTable, values);
        } else {
          await txn.update(
            DatabaseSchema.rolePermissionsTable,
            values,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }
    });
  }

  Future<int?> _resolveLocalId(
    dynamic txn, {
    required String tableName,
    String? syncId,
    String? remoteId,
  }) async {
    final normalizedSyncId = syncId?.trim() ?? '';
    if (normalizedSyncId.isNotEmpty) {
      final rows = await txn.query(
        tableName,
        columns: ['id'],
        where: 'sync_id = ?',
        whereArgs: [normalizedSyncId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['id'] as int?;
      }
    }

    final normalizedRemoteId = remoteId?.trim() ?? '';
    if (normalizedRemoteId.isEmpty) {
      return null;
    }

    final rows = await txn.query(
      tableName,
      columns: ['id'],
      where: 'id_remote = ?',
      whereArgs: [normalizedRemoteId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
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
      'UPDATE ${DatabaseSchema.rolePermissionsTable} SET sync_status = ? WHERE sync_id IN ($placeholders)',
      [status, ...ids],
    );
  }
}
