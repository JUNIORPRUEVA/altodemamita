import 'dart:developer' as developer;

import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class PaymentsSyncRepository implements SyncRepository {
  PaymentsSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SistemaSolares.PaymentsSyncRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

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
      WHERE p.sync_status IN (?, ?, ?, ?, ?)
      ORDER BY COALESCE(p.fecha_actualizacion, p.fecha_creacion) ASC
    ''',
      [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
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
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.paymentsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.paymentsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) {
      return;
    }

    final affectedSaleIds = <int>{};
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      for (final record in records) {
        final syncId = _readRequiredString(record['sync_id']);
        if (syncId == null) {
          continue;
        }

        final existingRows = await txn.query(
          DatabaseSchema.paymentsTable,
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (_isDeleted(record['deleted_at'])) {
          if (_hasConflictProtectedPendingLocal(existingRows)) {
            await _markFirstExistingRowAsConflict(
              txn,
              tableName: DatabaseSchema.paymentsTable,
              existingRows: existingRows,
            );
            _log(
              'payments_remote_tombstone_conflict_pending_local sync_id=$syncId',
            );
            continue;
          }
          final saleSyncId = _readRequiredString(record['sale_sync_id']);
          final clientSyncId = _readRequiredString(record['client_sync_id']);
          final installmentSyncId = _readRequiredString(
            record['installment_sync_id'],
          );
          final saleId = existingRows.isEmpty
              ? await _resolveIdBySyncId(
                  txn,
                  DatabaseSchema.salesTable,
                  saleSyncId,
                )
              : _readInt(existingRows.first['venta_id']);
          final clientId = existingRows.isEmpty
              ? await _resolveIdBySyncId(
                  txn,
                  DatabaseSchema.clientsTable,
                  clientSyncId,
                )
              : _readInt(existingRows.first['cliente_id']);
          final installmentId = existingRows.isEmpty
              ? installmentSyncId == null
                    ? null
                    : await _resolveIdBySyncId(
                        txn,
                        DatabaseSchema.installmentsTable,
                        installmentSyncId,
                      )
              : _readNullableInt(existingRows.first['cuota_id']);
          if (saleId == null || clientId == null) {
            throw RemoteSyncDependencyException(
              scope: scope,
              recordSyncId: syncId,
              missingScopes: {
                if (saleId == null && saleSyncId != null) 'sales',
                if (clientId == null && clientSyncId != null) 'clients',
                if (installmentSyncId != null && installmentId == null)
                  'installments',
              },
              message:
                  'No se pudo aplicar tombstone remoto de payments $syncId porque faltan referencias locales requeridas.',
            );
          }
          affectedSaleIds.add(saleId);

          final tombstoneValues = {
            'sync_id': syncId,
            'id_remote': record['id']?.toString().trim(),
            'id_local': existingRows.isEmpty ? null : existingRows.first['id'],
            'version': _readVersion(record),
            'venta_id': saleId,
            'cliente_id': clientId,
            'usuario_id': 1,
            'cuota_id': installmentId,
            'fecha_pago': _readDate(
              record['payment_date'] ?? record['created_at'],
            ),
            'monto_pagado': _readDouble(record['amount_paid']),
            'metodo_pago': record['payment_method'],
            'tipo_pago': record['payment_type'] ?? 'cuota',
            'referencia': record['reference'],
            'ano_a_pagar': record['year_to_pay'],
            'fecha_creacion': _readDate(record['created_at']),
            'fecha_actualizacion': _readDate(record['updated_at']),
            'last_modified_remote': _readDate(record['updated_at']),
            'deleted_at': _readNullableDate(record['deleted_at']),
            'sync_status': DatabaseSchema.syncStatusSynced,
          };
          _log('UPSERT TOMBSTONE: payments $syncId');
          await _upsertPayment(txn, tombstoneValues);
          continue;
        }

        if (_shouldKeepLocal(
          existingRows,
          record,
          updatedAtField: 'fecha_actualizacion',
        )) {
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
        affectedSaleIds.add(saleId);

        final values = {
          'sync_id': syncId,
          'id_remote': record['id']?.toString().trim(),
          'id_local': existingRows.isEmpty ? null : existingRows.first['id'],
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
          'last_modified_remote': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existingRows.isEmpty) {
          _log(
            '[SYNC] Insert new record: table=payments id=$syncId remote_delete=false',
          );
          await txn.insert(DatabaseSchema.paymentsTable, values);
        } else {
          _log(
            '[SYNC] Updating local record: table=payments id=$syncId remote_delete=false',
          );
          await txn.update(
            DatabaseSchema.paymentsTable,
            values,
            where: 'sync_id = ?',
            whereArgs: [syncId],
          );
        }
      }
    });

    if (affectedSaleIds.isNotEmpty) {
      await _reconcileSalesFromPayments(affectedSaleIds);
    }
  }

  Future<void> _reconcileSalesFromPayments(Set<int> saleIds) async {
    final db = await _appDatabase.database;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();

    await db.transaction((txn) async {
      for (final saleId in saleIds) {
        final installmentRows = await txn.query(
          DatabaseSchema.installmentsTable,
          columns: [
            'id',
            'monto_cuota',
            'monto_pagado',
            'capital_cuota',
            'interes_cuota',
            'capital_pagado',
            'interes_pagado',
            'fecha_vencimiento',
            'estado',
          ],
          where: 'venta_id = ? AND deleted_at IS NULL AND estado <> ?',
          whereArgs: [saleId, 'ajustada'],
        );

        for (final installment in installmentRows) {
          final currentStatus = (installment['estado'] as String? ?? '').trim();
          if (currentStatus == 'cancelada') {
            continue;
          }

          final installmentId = _readInt(installment['id']);
          final paidRows = await txn.rawQuery(
            '''
            SELECT COALESCE(SUM(monto_pagado), 0) AS paid_total
            FROM ${DatabaseSchema.paymentsTable}
            WHERE cuota_id = ?
              AND deleted_at IS NULL
          ''',
            [installmentId],
          );

          final paidAmount = _roundCurrency(
            _readDouble(paidRows.first['paid_total']),
          );
          final totalAmount = _readDouble(installment['monto_cuota']);
          final interestAmount = _readDouble(installment['interes_cuota']);
          final principalAmount = _readDouble(installment['capital_cuota']);
          final interestPaid = _roundCurrency(
            paidAmount > interestAmount ? interestAmount : paidAmount,
          );
          final principalPaid = _roundCurrency(
            (paidAmount - interestPaid).clamp(0, principalAmount),
          );
          final dueDate =
              _parseDate(installment['fecha_vencimiento']?.toString()) ?? now;
          final newStatus = _resolveInstallmentStatusForReconcile(
            dueDate: dueDate,
            paidAmount: paidAmount,
            totalAmount: totalAmount,
            asOf: now,
          );

          final statusChanged = currentStatus != newStatus;
          final paidChanged =
              (_readDouble(installment['monto_pagado']) - paidAmount).abs() >
              0.009;
          final principalChanged =
              (_readDouble(installment['capital_pagado']) - principalPaid)
                  .abs() >
              0.009;
          final interestChanged =
              (_readDouble(installment['interes_pagado']) - interestPaid)
                  .abs() >
              0.009;

          if (!statusChanged &&
              !paidChanged &&
              !principalChanged &&
              !interestChanged) {
            continue;
          }

          await txn.update(
            DatabaseSchema.installmentsTable,
            {
              'monto_pagado': paidAmount,
              'capital_pagado': principalPaid,
              'interes_pagado': interestPaid,
              'estado': newStatus,
              'fecha_actualizacion': nowIso,
              'sync_status': DatabaseSchema.syncStatusSynced,
            },
            where: 'id = ?',
            whereArgs: [installmentId],
          );
        }

        final pendingRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(MAX(capital_cuota - capital_pagado, 0)), 0) AS total_pendiente
          FROM ${DatabaseSchema.installmentsTable}
          WHERE venta_id = ?
            AND deleted_at IS NULL
            AND estado <> ?
        ''',
          [saleId, 'ajustada'],
        );

        final pendingBalance = _roundCurrency(
          _readDouble(pendingRows.first['total_pendiente']),
        );
        await txn.update(
          DatabaseSchema.salesTable,
          {
            'saldo_pendiente': pendingBalance,
            'estado': pendingBalance <= 0.009 ? 'pagada' : 'activa',
            'fecha_actualizacion': nowIso,
            'sync_status': DatabaseSchema.syncStatusSynced,
          },
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [saleId],
        );
      }
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
    'SET sync_status = ?, fecha_actualizacion = COALESCE(fecha_actualizacion, ?), '
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
  final localSyncStatus = (local['sync_status'] as String? ?? '')
      .trim()
      .toLowerCase();
  final remoteDeleted = _isDeleted(remoteRecord['deleted_at']);
  if (localSyncStatus == DatabaseSchema.syncStatusPendingDelete &&
      !remoteDeleted) {
    return true;
  }
  if (localSyncStatus == DatabaseSchema.syncStatusConflict) {
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

bool _hasConflictProtectedPendingLocal(
  List<Map<String, Object?>> existingRows,
) {
  if (existingRows.isEmpty) {
    return false;
  }
  final localSyncStatus = (existingRows.first['sync_status'] as String? ?? '')
      .trim()
      .toLowerCase();
  return localSyncStatus == DatabaseSchema.syncStatusPendingCreate ||
      localSyncStatus == DatabaseSchema.syncStatusPendingUpdate;
}

Future<void> _markFirstExistingRowAsConflict(
  dynamic txn, {
  required String tableName,
  required List<Map<String, Object?>> existingRows,
}) async {
  if (existingRows.isEmpty) {
    return;
  }
  final rowId = existingRows.first['id'];
  if (rowId == null) {
    return;
  }
  await txn.update(
    tableName,
    {'sync_status': DatabaseSchema.syncStatusConflict},
    where: 'id = ?',
    whereArgs: [rowId],
  );
}

Future<void> _upsertPayment(dynamic txn, Map<String, Object?> values) async {
  final updated = await txn.update(
    DatabaseSchema.paymentsTable,
    values,
    where: 'sync_id = ?',
    whereArgs: [values['sync_id']],
  );
  if (updated == 0) {
    await txn.insert(DatabaseSchema.paymentsTable, values);
  }
}

DateTime? _parseDate(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return DateTime.tryParse(normalized);
}

String _resolveInstallmentStatusForReconcile({
  required DateTime dueDate,
  required double paidAmount,
  required double totalAmount,
  required DateTime asOf,
}) {
  if (paidAmount >= totalAmount - 0.009) {
    return 'pagada';
  }
  if (paidAmount > 0.009) {
    return 'parcial';
  }
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final asOfDay = DateTime(asOf.year, asOf.month, asOf.day);
  return dueDay.isBefore(asOfDay) ? 'vencida' : 'pendiente';
}

double _roundCurrency(double value) {
  return (value * 100).roundToDouble() / 100;
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

int? _readNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
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
