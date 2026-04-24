import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import '../features/auth/domain/user_model.dart';
import 'sync_repository.dart';

class UsersSyncRepository implements SyncRepository {
  UsersSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'users';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'sync_status = ?',
      whereArgs: [DatabaseSchema.syncStatusPending],
      orderBy: 'fecha_actualizacion ASC',
    );
    return rows.map(_toPayload).toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markScopeRowsAsSynced(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.usersTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.usersTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      for (final record in records) {
        final syncId = _readRequiredString(record['sync_id']);
        if (syncId == null) {
          continue;
        }

        final normalizedEmail =
            record['email']?.toString().trim().toLowerCase() ?? '';

        var existingRows = await txn.query(
          DatabaseSchema.usersTable,
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existingRows.isEmpty && normalizedEmail.isNotEmpty) {
          existingRows = await txn.query(
            DatabaseSchema.usersTable,
            where: 'LOWER(email) = ?',
            whereArgs: [normalizedEmail],
            limit: 1,
          );
        }
        if (_shouldKeepLocal(
          existingRows,
          record,
          updatedAtField: 'fecha_actualizacion',
        )) {
          continue;
        }

        if (_isDeleted(record['deleted_at'])) {
          if (existingRows.isNotEmpty) {
            await txn.update(
              DatabaseSchema.usersTable,
              {
                'version': _readVersion(record),
                'fecha_actualizacion': _readDate(record['updated_at']),
                'deleted_at': _readNullableDate(record['deleted_at']),
                'sync_status': DatabaseSchema.syncStatusSynced,
                'activo': 0,
              },
              where: 'sync_id = ?',
              whereArgs: [syncId],
            );
          }
          continue;
        }

        final values = {
          'sync_id': syncId,
          'version': _readVersion(record),
          'nombre':
              record['full_name'] ?? record['fullName'] ?? record['name'] ?? '',
          'email': record['email']?.toString().trim().toLowerCase() ?? '',
          'password_hash': record['password_hash'] ?? '',
          'password_reset_required': _readBool(record['password_reset_required'])
              ? 1
              : 0,
          'rol': _readRole(record['role']),
          'activo': _readBool(record['is_active']) ? 1 : 0,
          'telefono': record['phone']?.toString().trim(),
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
          'password_updated_at': _readNullableDate(
            record['password_updated_at'],
          ),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.usersTable, values);
        } else {
          final localId = existingRows.first['id'] as int?;
          await txn.update(
            DatabaseSchema.usersTable,
            values,
            where: localId != null ? 'id = ?' : 'sync_id = ?',
            whereArgs: localId != null ? [localId] : [syncId],
          );
        }
      }
    });
  }

  Map<String, Object?> _toPayload(Map<String, Object?> row) {
    return {
      'id': row['id'],
      'sync_id': row['sync_id'],
      'version': row['version'],
      'full_name': row['nombre'],
      'email': row['email'],
      'username': _usernameFromRow(row),
      'password_hash': row['password_hash'],
      'password_reset_required': row['password_reset_required'],
      'role': _readRole(row['rol']),
      'is_active': (row['activo'] as int? ?? 0) == 1,
      'phone': row['telefono'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'password_updated_at': row['password_updated_at'],
      'deleted_at': row['deleted_at'],
      'sync_status': row['sync_status'],
      'auth_source': row['auth_source'],
    };
  }

  String _usernameFromRow(Map<String, Object?> row) {
    final email = (row['email'] as String? ?? '').trim().toLowerCase();
    if (email.contains('@')) {
      return email.split('@').first;
    }
    final name = (row['nombre'] as String? ?? '').trim().toLowerCase();
    final normalized = name
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '.')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'^\.|\.$'), '');
    return normalized.isEmpty ? 'usuario' : normalized;
  }
}

Future<void> _markScopeRowsAsSynced({
  required AppDatabase appDatabase,
  required String tableName,
  required Iterable<String> syncIds,
}) async {
  final ids = syncIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (ids.isEmpty) {
    return;
  }
  final db = await appDatabase.database;
  final placeholders = List.filled(ids.length, '?').join(', ');
  await db.rawDelete(
    'DELETE FROM $tableName WHERE deleted_at IS NOT NULL AND sync_id IN ($placeholders)',
    ids,
  );
  await db.rawUpdate(
    'UPDATE $tableName SET sync_status = ? WHERE deleted_at IS NULL AND sync_id IN ($placeholders)',
    [DatabaseSchema.syncStatusSynced, ...ids],
  );
}

Future<void> _markScopeRowsAsConflict({
  required AppDatabase appDatabase,
  required String tableName,
  required Iterable<String> syncIds,
}) async {
  final ids = syncIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (ids.isEmpty) {
    return;
  }
  final db = await appDatabase.database;
  final placeholders = List.filled(ids.length, '?').join(', ');
  await db.rawUpdate(
    'UPDATE $tableName SET sync_status = ? WHERE sync_id IN ($placeholders)',
    [DatabaseSchema.syncStatusConflict, ...ids],
  );
}

bool _shouldKeepLocal(
  List<Map<String, Object?>> existingRows,
  Map<String, dynamic> remoteRecord, {
  required String updatedAtField,
}) {
  if (existingRows.isEmpty) {
    return false;
  }
  final local = existingRows.first;
  final localPending =
      (local['sync_status'] as String? ?? '') ==
          DatabaseSchema.syncStatusPending ||
      (local['sync_status'] as String? ?? '') ==
          DatabaseSchema.syncStatusConflict;
  final localVersion = _readVersion(local);
  final remoteVersion = _readVersion(remoteRecord);
  final localUpdated = DateTime.tryParse(
    local[updatedAtField] as String? ?? '',
  );
  final remoteUpdated = DateTime.tryParse(
    remoteRecord['updated_at']?.toString() ?? '',
  );
  return localPending &&
      ((localVersion > remoteVersion) ||
          (localVersion >= remoteVersion &&
              localUpdated != null &&
              remoteUpdated != null &&
              localUpdated.isAfter(remoteUpdated)));
}

int _readVersion(Map<Object?, Object?> map) {
  final value = map['version'];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 1;
}

String _readDate(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return (parsed ?? DateTime.now()).toIso8601String();
}

String? _readNullableDate(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String? _readRequiredString(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

bool _isDeleted(Object? value) {
  final normalized = value?.toString().trim();
  return normalized != null && normalized.isNotEmpty;
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == '1' || normalized == 'true';
}

String _readRole(Object? value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return normalized == UserRole.admin.storageValue ? 'admin' : 'vendedor';
}