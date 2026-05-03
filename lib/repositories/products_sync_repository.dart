import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class ProductsSyncRepository implements SyncRepository {
  ProductsSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'products';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.lotsTable,
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
    return rows.map(_toPayload).toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    await _markScopeRowsAsSynced(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.lotsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    await _markScopeRowsAsConflict(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.lotsTable,
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

        final existingRows = await txn.query(
          DatabaseSchema.lotsTable,
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
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
              DatabaseSchema.lotsTable,
              {
                'version': _readVersion(record),
                'id_remote': record['id']?.toString().trim(),
                'fecha_actualizacion': _readDate(record['updated_at']),
                'last_modified_remote': _readDate(record['updated_at']),
                'deleted_at': _readNullableDate(record['deleted_at']),
                'sync_status': DatabaseSchema.syncStatusSynced,
              },
              where: 'sync_id = ?',
              whereArgs: [syncId],
            );
          }
          continue;
        }

        final values = {
          'sync_id': syncId,
          'id_remote': record['id']?.toString().trim(),
          'id_local': existingRows.isEmpty ? null : existingRows.first['id'],
          'version': _readVersion(record),
          'manzana_numero': record['block_number'] ?? '',
          'solar_numero': record['lot_number'] ?? '',
          'metros_cuadrados': _readDouble(record['area']),
          'precio_por_metro': _readDouble(record['price_per_square_meter']),
          'estado': record['status'] ?? 'disponible',
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
          'last_modified_remote': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.lotsTable, values);
        } else {
          await txn.update(
            DatabaseSchema.lotsTable,
            values,
            where: 'sync_id = ?',
            whereArgs: [syncId],
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
      'block_number': row['manzana_numero'],
      'lot_number': row['solar_numero'],
      'area': row['metros_cuadrados'],
      'price_per_square_meter': row['precio_por_metro'],
      'status': row['estado'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
      'sync_status': row['sync_status'],
    };
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
  final localSyncStatus =
      (local['sync_status'] as String? ?? '').trim().toLowerCase();
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
    local['last_modified_local']?.toString() ?? local[updatedAtField]?.toString(),
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

double _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
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
