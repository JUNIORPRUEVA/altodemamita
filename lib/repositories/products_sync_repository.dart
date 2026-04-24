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
      where: 'sync_status = ?',
      whereArgs: [DatabaseSchema.syncStatusPending],
      orderBy: 'fecha_actualizacion ASC',
    );
    return rows.map(_toPayload).toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    await _markScopeRowsAsSynced(
      tableName: DatabaseSchema.lotsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    await _markScopeRowsAsConflict(
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
                'fecha_actualizacion': _readDate(record['updated_at']),
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
          'version': _readVersion(record),
          'manzana_numero': record['block_number'] ?? '',
          'solar_numero': record['lot_number'] ?? '',
          'metros_cuadrados': _readDouble(record['area']),
          'precio_por_metro': _readDouble(record['price_per_square_meter']),
          'estado': record['status'] ?? 'disponible',
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
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
  final db = await AppDatabase.instance.database;
  final placeholders = List.filled(ids.length, '?').join(', ');
  await db.rawUpdate(
    'UPDATE $tableName SET sync_status = ? WHERE sync_id IN ($placeholders)',
    [DatabaseSchema.syncStatusSynced, ...ids],
  );
}

Future<void> _markScopeRowsAsConflict({
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
  final db = await AppDatabase.instance.database;
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
