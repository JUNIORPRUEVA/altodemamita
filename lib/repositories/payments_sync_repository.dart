import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class PaymentsSyncRepository implements SyncRepository {
  PaymentsSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'payments';

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
        p.*,
        v.sync_id AS sale_sync_id,
        c.sync_id AS client_sync_id,
        q.sync_id AS installment_sync_id
      FROM ${DatabaseSchema.paymentsTable} p
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = p.venta_id
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = p.cliente_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
      WHERE p.sync_status = ?
      ORDER BY COALESCE(p.fecha_actualizacion, p.fecha_creacion) ASC
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
            'client_sync_id': row['client_sync_id'],
            'installment_sync_id': row['installment_sync_id'],
            'payment_date': row['fecha_pago'],
            'amount_paid': row['monto_pagado'],
            'payment_method': row['metodo_pago'],
            'payment_type': row['tipo_pago'],
            'reference': row['referencia'],
            'year_to_pay': row['ano_a_pagar'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'] ?? row['fecha_creacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          };
        })
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markScopeRowsAsSynced(
      tableName: DatabaseSchema.paymentsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      tableName: DatabaseSchema.paymentsTable,
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
            DatabaseSchema.paymentsTable,
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
        final clientId = await _resolveIdBySyncId(
          txn,
          DatabaseSchema.clientsTable,
          _readRequiredString(record['client_sync_id']),
        );
        final installmentSyncId = _readRequiredString(
          record['installment_sync_id'],
        );
        final installmentId = installmentSyncId == null
            ? null
            : await _resolveIdBySyncId(
                txn,
                DatabaseSchema.installmentsTable,
                installmentSyncId,
              );
        if (saleId == null || clientId == null) {
          continue;
        }

        final existingRows = await txn.query(
          DatabaseSchema.paymentsTable,
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
          'cliente_id': clientId,
          'usuario_id': 1,
          'cuota_id': installmentId,
          'fecha_pago': _readDate(record['payment_date']),
          'monto_pagado': _readDouble(record['amount_paid']),
          'metodo_pago': record['payment_method'],
          'tipo_pago': record['payment_type'] ?? 'cuota',
          'referencia': record['reference'],
          'ano_a_pagar': record['year_to_pay'],
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.paymentsTable, values);
        } else {
          await txn.update(
            DatabaseSchema.paymentsTable,
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
