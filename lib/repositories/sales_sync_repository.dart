import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class SalesSyncRepository implements SyncRepository {
  SalesSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'sales';

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
        v.*,
        c.sync_id AS client_sync_id,
        s.sync_id AS product_sync_id,
        vd.sync_id AS seller_sync_id
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      LEFT JOIN ${DatabaseSchema.sellersTable} vd ON vd.id = v.vendedor_id
      WHERE v.sync_status = ?
      ORDER BY v.fecha_actualizacion ASC
    ''',
      [DatabaseSchema.syncStatusPending],
    );
    return rows.map(_toPayload).toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markScopeRowsAsSynced(
      tableName: DatabaseSchema.salesTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      tableName: DatabaseSchema.salesTable,
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
          DatabaseSchema.salesTable,
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
            DatabaseSchema.salesTable,
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

        final clientId = await _resolveIdBySyncId(
          txn,
          DatabaseSchema.clientsTable,
          _readRequiredString(record['client_sync_id']),
        );
        final productId = await _resolveIdBySyncId(
          txn,
          DatabaseSchema.lotsTable,
          _readRequiredString(record['product_sync_id']),
        );
        final sellerId = await _resolveIdBySyncId(
          txn,
          DatabaseSchema.sellersTable,
          _readRequiredString(record['seller_sync_id']),
        );
        if (clientId == null || productId == null) {
          continue;
        }

        final values = {
          'sync_id': syncId,
          'version': _readVersion(record),
          'cliente_id': clientId,
          'solar_id': productId,
          'usuario_id': 1,
          'vendedor_id': sellerId,
          'fecha_venta': _readDate(record['sale_date']),
          'precio_venta': _readDouble(record['sale_price']),
          'inicial_porcentaje': _readDouble(record['down_payment_percentage']),
          'inicial_monto': _readDouble(record['down_payment_amount']),
          'monto_inicial_requerido': _readDouble(
            record['required_initial_payment'],
          ),
          'monto_inicial_pagado': _readDouble(record['paid_initial_payment']),
          'monto_inicial_pendiente': _readDouble(
            record['pending_initial_payment'],
          ),
          'monto_apartado_minimo': _readNullableDouble(
            record['minimum_reserve_amount'],
          ),
          'fecha_limite_inicial': _readNullableDate(
            record['initial_payment_deadline'],
          ),
          'fecha_activacion': _readNullableDate(record['activation_date']),
          'saldo_financiado': _readDouble(record['financed_balance']),
          'saldo_pendiente': _readDouble(record['pending_balance']),
          'interes_mensual': _readDouble(record['monthly_interest']),
          'cantidad_cuotas': _readInt(record['installment_count']),
          'estado': record['status'] ?? 'apartado',
          'fecha_creacion': _readDate(record['created_at']),
          'fecha_actualizacion': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.salesTable, values);
        } else {
          await txn.update(
            DatabaseSchema.salesTable,
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
      'client_sync_id': row['client_sync_id'],
      'product_sync_id': row['product_sync_id'],
      'seller_sync_id': row['seller_sync_id'],
      'sale_date': row['fecha_venta'],
      'sale_price': row['precio_venta'],
      'down_payment_percentage': row['inicial_porcentaje'],
      'down_payment_amount': row['inicial_monto'],
      'required_initial_payment': row['monto_inicial_requerido'],
      'paid_initial_payment': row['monto_inicial_pagado'],
      'pending_initial_payment': row['monto_inicial_pendiente'],
      'minimum_reserve_amount': row['monto_apartado_minimo'],
      'initial_payment_deadline': row['fecha_limite_inicial'],
      'activation_date': row['fecha_activacion'],
      'financed_balance': row['saldo_financiado'],
      'pending_balance': row['saldo_pendiente'],
      'monthly_interest': row['interes_mensual'],
      'installment_count': row['cantidad_cuotas'],
      'status': row['estado'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
      'sync_status': row['sync_status'],
    };
  }
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

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _readNullableDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
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
