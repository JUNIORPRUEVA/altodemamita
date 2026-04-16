import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class InstallmentsSyncRepository implements SyncRepository {
  InstallmentsSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'installments';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        q.*,
        v.sync_id AS sale_sync_id
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      WHERE q.sync_status = ?
      ORDER BY q.fecha_actualizacion ASC
    ''',
      [DatabaseSchema.syncStatusPending],
    );
    return rows
        .map((row) {
          return {
            'id': row['id'],
            'sync_id': row['sync_id'],
            'version': row['version'],
            'sale_sync_id': row['sale_sync_id'],
            'installment_number': row['numero_cuota'],
            'due_date': row['fecha_vencimiento'],
            'opening_balance': row['saldo_inicial'],
            'principal_amount': row['capital_cuota'],
            'interest_amount': row['interes_cuota'],
            'total_amount': row['monto_cuota'],
            'paid_amount': row['monto_pagado'],
            'paid_principal_amount': row['capital_pagado'],
            'paid_interest_amount': row['interes_pagado'],
            'ending_balance': row['saldo_final'],
            'status': row['estado'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          };
        })
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markScopeRowsAsSynced(
      tableName: DatabaseSchema.installmentsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      tableName: DatabaseSchema.installmentsTable,
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

        if (_isDeleted(record['deleted_at'])) {
          await txn.delete(
            DatabaseSchema.installmentsTable,
            where: 'sync_id = ?',
            whereArgs: [syncId],
          );
          continue;
        }

        final saleId = await _resolveIdBySyncId(
          txn,
          DatabaseSchema.salesTable,
          _readRequiredString(record['sale_sync_id']),
        );
        if (saleId == null) {
          continue;
        }

        final existingRows = await txn.query(
          DatabaseSchema.installmentsTable,
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

        final values = {
          'sync_id': syncId,
          'version': _readVersion(record),
          'venta_id': saleId,
          'numero_cuota': _readInt(record['installment_number']),
          'fecha_vencimiento': _readDate(record['due_date']),
          'saldo_inicial': _readDouble(record['opening_balance']),
          'capital_cuota': _readDouble(record['principal_amount']),
          'interes_cuota': _readDouble(record['interest_amount']),
          'monto_cuota': _readDouble(record['total_amount']),
          'monto_pagado': _readDouble(record['paid_amount']),
          'capital_pagado': _readDouble(record['paid_principal_amount']),
          'interes_pagado': _readDouble(record['paid_interest_amount']),
          'saldo_final': _readDouble(record['ending_balance']),
          'estado': record['status'] ?? 'pendiente',
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.installmentsTable, values);
        } else {
          await txn.update(
            DatabaseSchema.installmentsTable,
            values,
            where: 'sync_id = ?',
            whereArgs: [syncId],
          );
        }
      }
    });
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

Future<int?> _resolveIdBySyncId(
  dynamic txn,
  String tableName,
  String? syncId,
) async {
  final normalized = syncId?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  final rows = await txn.query(
    tableName,
    columns: ['id'],
    where: 'sync_id = ?',
    whereArgs: [normalized],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  final value = rows.first['id'];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
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

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
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
