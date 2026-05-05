import 'dart:convert';

import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import '../features/auth/domain/permission_model.dart';
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
      where: 'sync_status IN (?, ?, ?, ?, ?)',
      whereArgs: [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
      orderBy: 'fecha_actualizacion ASC',
    );
    final permissionsByUserId = await _loadPermissionCodesByUserId(db, rows);
    return rows
        .map(
          (row) => _toPayload(
            row,
            permissionCodes: permissionsByUserId[row['id']] ?? const [],
          ),
        )
        .toList(growable: false);
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

        final remoteId = _readRequiredString(record['id']);
        final normalizedEmail =
            record['email']?.toString().trim().toLowerCase() ?? '';

        var existingRows = await txn.query(
          DatabaseSchema.usersTable,
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existingRows.isEmpty && remoteId != null) {
          existingRows = await txn.query(
            DatabaseSchema.usersTable,
            where: 'id_remote = ? OR remote_auth_id = ?',
            whereArgs: [remoteId, remoteId],
            limit: 1,
          );
        }
        if (existingRows.isEmpty && normalizedEmail.isNotEmpty) {
          existingRows = await txn.query(
            DatabaseSchema.usersTable,
            where: 'LOWER(email) = ?',
            whereArgs: [normalizedEmail],
            limit: 1,
          );
        }
        final localRow = existingRows.isEmpty ? null : existingRows.first;
        final localDeletedAt = localRow?['deleted_at']?.toString().trim();
        if (localRow != null &&
            localDeletedAt != null &&
            localDeletedAt.isNotEmpty &&
            !_isDeleted(record['deleted_at'])) {
          continue;
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
            final localId = existingRows.first['id'] as int?;
            await txn.update(
              DatabaseSchema.usersTable,
              {
                'version': _readVersion(record),
                'id_remote': record['id']?.toString().trim(),
                'fecha_actualizacion': _readDate(record['updated_at']),
                'last_modified_remote': _readDate(record['updated_at']),
                'deleted_at': _readNullableDate(record['deleted_at']),
                'sync_status': DatabaseSchema.syncStatusSynced,
                'activo': 0,
              },
              where: 'sync_id = ?',
              whereArgs: [syncId],
            );
            if (localId != null) {
              await txn.delete(
                DatabaseSchema.permissionsTable,
                where: 'usuario_id = ?',
                whereArgs: [localId],
              );
            }
          }
          continue;
        }

        final existingRow = existingRows.isEmpty ? null : existingRows.first;
        final hasIncomingPasswordHash = record.containsKey('password_hash');
        final incomingPasswordHash = hasIncomingPasswordHash
            ? (record['password_hash']?.toString() ?? '').trim()
            : '';
        final existingPasswordHash =
            (existingRow?['password_hash'] as String? ?? '').trim();
        final resolvedPasswordHash = incomingPasswordHash.isNotEmpty
            ? incomingPasswordHash
            : existingPasswordHash;
        final incomingEmail =
            record['email']?.toString().trim().toLowerCase() ?? '';
        final existingEmail = (existingRow?['email'] as String? ?? '')
            .trim()
            .toLowerCase();
        final incomingNombre =
            (record['full_name'] ?? record['fullName'] ?? record['name'])
                ?.toString()
                .trim() ??
            '';
        final existingNombre = (existingRow?['nombre'] as String? ?? '').trim();
        final incomingRole = (record['role']?.toString() ?? '').trim();
        final existingRole = (existingRow?['rol'] as String? ?? '').trim();
        final hasIsActiveField = record.containsKey('is_active');
        final hasPasswordUpdatedAt = record.containsKey('password_updated_at');
        final existingPasswordUpdatedAt =
            (existingRow?['password_updated_at'] as String?)?.trim();
        final existingAuthSource =
            (existingRow?['auth_source'] as String? ?? '').trim();
        final existingLastOnlineLoginAt =
            (existingRow?['last_online_login_at'] as String?)?.trim();
        final resolvedRemoteId =
            remoteId ?? (existingRow?['id_remote'] as String?)?.trim();

        final values = {
          'sync_id': syncId,
          'id_remote': resolvedRemoteId,
          'remote_auth_id': resolvedRemoteId,
          'id_local': existingRows.isEmpty ? null : existingRows.first['id'],
          'version': _readVersion(record),
          'nombre': incomingNombre.isNotEmpty ? incomingNombre : existingNombre,
          'email': incomingEmail.isNotEmpty ? incomingEmail : existingEmail,
          'password_hash': resolvedPasswordHash,
          'password_reset_required':
              _readBool(record['password_reset_required']) ? 1 : 0,
          'rol': incomingRole.isNotEmpty
              ? _readRole(record['role'])
              : existingRole,
          'activo': hasIsActiveField
              ? (_readBool(record['is_active']) ? 1 : 0)
              : ((existingRow?['activo'] as int? ?? 1) == 1 ? 1 : 0),
          'telefono': record['phone']?.toString().trim(),
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
          'last_modified_remote': _readDate(record['updated_at']),
          'password_updated_at': hasPasswordUpdatedAt
              ? _readNullableDate(record['password_updated_at'])
              : existingPasswordUpdatedAt,
          'auth_source': existingAuthSource.isNotEmpty
              ? existingAuthSource
              : 'local',
          'last_online_login_at': existingLastOnlineLoginAt,
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          final localId = await txn.insert(DatabaseSchema.usersTable, values);
          await _replacePermissionsFromRemoteRecord(
            txn,
            userId: localId,
            record: record,
          );
        } else {
          final localId = existingRows.first['id'] as int?;
          await txn.update(
            DatabaseSchema.usersTable,
            values,
            where: localId != null ? 'id = ?' : 'sync_id = ?',
            whereArgs: localId != null ? [localId] : [syncId],
          );
          if (localId != null) {
            await _replacePermissionsFromRemoteRecord(
              txn,
              userId: localId,
              record: record,
            );
          }
        }
      }
    });
  }

  Map<String, Object?> _toPayload(
    Map<String, Object?> row, {
    required List<String> permissionCodes,
  }) {
    return {
      'id': row['id'],
      'id_remote': row['id_remote'],
      'remote_auth_id': row['remote_auth_id'],
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
      'permissions': permissionCodes,
    };
  }

  Future<Map<Object?, List<String>>> _loadPermissionCodesByUserId(
    dynamic db,
    List<Map<String, Object?>> userRows,
  ) async {
    final userIds = userRows
        .map((row) => row['id'])
        .whereType<int>()
        .toList(growable: false);
    if (userIds.isEmpty) {
      return const {};
    }

    final placeholders = List.filled(userIds.length, '?').join(', ');
    final permissionRows = await db.query(
      DatabaseSchema.permissionsTable,
      columns: ['usuario_id', 'modulo', 'acciones'],
      where: 'usuario_id IN ($placeholders)',
      whereArgs: userIds,
      orderBy: 'usuario_id ASC, modulo ASC',
    );

    final permissionsByUserId = <Object?, List<String>>{};
    for (final row in permissionRows) {
      final userId = row['usuario_id'];
      final module = row['modulo']?.toString().trim() ?? '';
      if (module.isEmpty || userId == null) {
        continue;
      }
      final actions = _readLegacyActions(row['acciones']);
      final permission = PermissionModel.fromLegacy(
        module: module,
        actions: actions,
      );
      permissionsByUserId
          .putIfAbsent(userId, () => <String>[])
          .addAll(_permissionCodesFromLocal(permission));
    }

    for (final entry in permissionsByUserId.entries) {
      entry.value.sort();
    }
    return permissionsByUserId;
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

Future<void> _replacePermissionsFromRemoteRecord(
  dynamic txn, {
  required int userId,
  required Map<String, dynamic> record,
}) async {
  final permissionCodes = _readRemotePermissionCodes(record['permissions']);
  if (permissionCodes == null) {
    return;
  }

  final now = DateTime.now().toIso8601String();
  final updatedAt = _readNullableDate(record['updated_at']) ?? now;
  final permissions = _permissionModelsFromCodes(permissionCodes);

  await txn.delete(
    DatabaseSchema.permissionsTable,
    where: 'usuario_id = ?',
    whereArgs: [userId],
  );

  for (final permission in permissions) {
    await txn.insert(DatabaseSchema.permissionsTable, {
      'sync_id': 'user-permission-$userId-${permission.module}',
      'id_remote': null,
      'id_local': null,
      'version': 1,
      'usuario_id': userId,
      'modulo': permission.module,
      'acciones': jsonEncode(permission.toLegacyActions()),
      'fecha_creacion': updatedAt,
      'last_modified_remote': updatedAt,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
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
  final now = DateTime.now().toIso8601String();
  await db.rawUpdate(
    'UPDATE $tableName '
    'SET sync_status = ?, fecha_actualizacion = ?, '
    'last_modified_local = COALESCE(last_modified_local, ?) '
    'WHERE sync_id IN ($placeholders)',
    [DatabaseSchema.syncStatusSynced, now, now, ...ids],
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
  final localSyncStatus = (local['sync_status'] as String? ?? '')
      .trim()
      .toLowerCase();
  final localPending = DatabaseSchema.writableSyncStatuses.contains(
    localSyncStatus,
  );
  if (!localPending) {
    return false;
  }

  final localVersion = _readVersion(local);
  final remoteVersion = _readVersion(remoteRecord);
  if (localVersion > remoteVersion) {
    return true;
  }
  if (localVersion < remoteVersion) {
    return false;
  }

  final localUpdated = _parseDate(
    local['last_modified_local']?.toString() ??
        local[updatedAtField]?.toString(),
  );
  final remoteUpdated = _parseDate(
    remoteRecord['last_modified_remote']?.toString() ??
        remoteRecord['updated_at']?.toString(),
  );
  return localUpdated != null &&
      remoteUpdated != null &&
      localUpdated.isAfter(remoteUpdated);
}

DateTime? _parseDate(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return DateTime.tryParse(normalized);
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

List<String> _readLegacyActions(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList(growable: false);
    }
  } catch (_) {
    return const [];
  }
  return const [];
}

List<String>? _readRemotePermissionCodes(Object? value) {
  if (value is! List) {
    return null;
  }
  final codes = value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
  codes.sort();
  return codes;
}

List<PermissionModel> _permissionModelsFromCodes(List<String> permissionCodes) {
  final buckets = <String, Set<PermissionAction>>{};

  void grant(String module, Iterable<PermissionAction> actions) {
    buckets.putIfAbsent(module, () => <PermissionAction>{}).addAll(actions);
  }

  for (final rawCode in permissionCodes) {
    switch (rawCode.trim().toLowerCase()) {
      case 'clients.read':
        grant(PermissionCatalog.clients, [PermissionAction.read]);
        break;
      case 'clients.write':
        grant(PermissionCatalog.clients, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'products.read':
        grant(PermissionCatalog.lots, [PermissionAction.read]);
        break;
      case 'products.write':
        grant(PermissionCatalog.lots, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'sellers.read':
        grant(PermissionCatalog.sellers, [PermissionAction.read]);
        break;
      case 'sellers.write':
        grant(PermissionCatalog.sellers, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'sales.read':
        grant(PermissionCatalog.sales, [PermissionAction.read]);
        break;
      case 'sales.write':
        grant(PermissionCatalog.sales, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'payments.read':
        grant(PermissionCatalog.payments, [PermissionAction.read]);
        break;
      case 'payments.write':
        grant(PermissionCatalog.payments, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'installments.read':
        grant(PermissionCatalog.installments, [PermissionAction.read]);
        break;
      case 'installments.write':
        grant(PermissionCatalog.installments, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'users.read':
      case 'auth.manage':
        grant(PermissionCatalog.settings, [PermissionAction.read]);
        break;
      case 'users.write':
        grant(PermissionCatalog.settings, const [
          PermissionAction.create,
          PermissionAction.update,
          PermissionAction.delete,
        ]);
        break;
      case 'reports.read':
        grant(PermissionCatalog.dashboard, [PermissionAction.read]);
        grant(PermissionCatalog.search, [PermissionAction.read]);
        break;
    }
  }

  return PermissionCatalog.modules
      .map((module) {
        final actions = buckets[module.key] ?? const <PermissionAction>{};
        return PermissionModel(
          module: module.key,
          read: actions.contains(PermissionAction.read),
          create: actions.contains(PermissionAction.create),
          update: actions.contains(PermissionAction.update),
          delete: actions.contains(PermissionAction.delete),
        );
      })
      .where(
        (permission) =>
            permission.read ||
            permission.create ||
            permission.update ||
            permission.delete,
      )
      .toList(growable: false);
}

List<String> _permissionCodesFromLocal(PermissionModel permission) {
  final codes = <String>[];
  switch (permission.module) {
    case PermissionCatalog.clients:
      if (permission.read) {
        codes.add('clients.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('clients.write');
      }
      break;
    case PermissionCatalog.lots:
      if (permission.read) {
        codes.add('products.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('products.write');
      }
      break;
    case PermissionCatalog.sellers:
      if (permission.read) {
        codes.add('sellers.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('sellers.write');
      }
      break;
    case PermissionCatalog.sales:
      if (permission.read) {
        codes.add('sales.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('sales.write');
      }
      break;
    case PermissionCatalog.payments:
      if (permission.read) {
        codes.add('payments.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('payments.write');
      }
      break;
    case PermissionCatalog.installments:
      if (permission.read) {
        codes.add('installments.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('installments.write');
      }
      break;
    case PermissionCatalog.settings:
      if (permission.read) {
        codes.add('users.read');
      }
      if (permission.create || permission.update || permission.delete) {
        codes.add('users.write');
      }
      break;
    case PermissionCatalog.dashboard:
    case PermissionCatalog.search:
      if (permission.read) {
        codes.add('reports.read');
      }
      break;
  }
  return codes;
}
