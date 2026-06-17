import 'dart:developer' as developer;

import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class InstallmentsSyncRepository implements SyncRepository {
  InstallmentsSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SistemaSolares.InstallmentsSyncRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

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
      WHERE q.sync_status IN (?, ?, ?, ?, ?)
      ORDER BY q.fecha_actualizacion ASC
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
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.installmentsTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.installmentsTable,
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
          DatabaseSchema.installmentsTable,
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (_isDeleted(record['deleted_at'])) {
          if (_hasConflictProtectedPendingLocal(existingRows)) {
            await _markFirstExistingRowAsConflict(
              txn,
              tableName: DatabaseSchema.installmentsTable,
              existingRows: existingRows,
            );
            _log(
              'installments_remote_tombstone_conflict_pending_local sync_id=$syncId',
            );
            continue;
          }
          final saleSyncId = _readRequiredString(record['sale_sync_id']);
          final resolvedSaleId = existingRows.isEmpty
              ? await _resolveIdBySyncId(
                  txn,
                  DatabaseSchema.salesTable,
                  saleSyncId,
                )
              : _readInt(existingRows.first['venta_id']);
          final installmentNumber = _readInt(record['installment_number']);
          final matchedRows = existingRows;
          final matchedRow = matchedRows.isEmpty ? null : matchedRows.first;
          final saleId = matchedRow != null
              ? _readInt(matchedRow['venta_id'])
              : resolvedSaleId;
          if (saleId == null) {
            throw RemoteSyncDependencyException(
              scope: scope,
              recordSyncId: syncId,
              missingScopes: {if (saleSyncId != null) 'sales'},
              message:
                  'No se pudo aplicar tombstone remoto de installments $syncId porque falta la venta local requerida.',
            );
          }
          affectedSaleIds.add(saleId);

          final tombstoneValues = {
            'sync_id': syncId,
            'id_remote': record['id']?.toString().trim(),
            'id_local': matchedRow?['id'],
            'version': _readVersion(record),
            'venta_id': saleId,
            'numero_cuota': installmentNumber,
            'fecha_vencimiento': _readDate(
              record['due_date'] ?? record['created_at'],
            ),
            'saldo_inicial': _readDouble(record['opening_balance']),
            'capital_cuota': _readDouble(record['principal_amount']),
            'interes_cuota': _readDouble(record['interest_amount']),
            'monto_cuota': _readDouble(record['total_amount']),
            'monto_pagado': _readDouble(record['paid_amount']),
            'capital_pagado': _readDouble(record['paid_principal_amount']),
            'interes_pagado': _readDouble(record['paid_interest_amount']),
            'saldo_final': _readDouble(record['ending_balance']),
            'estado': record['status'] ?? 'cancelada',
            'fecha_creacion': _readDate(record['created_at']),
            'fecha_actualizacion': _readDate(record['updated_at']),
            'last_modified_remote': _readDate(record['updated_at']),
            'deleted_at': _readNullableDate(record['deleted_at']),
            'sync_status': DatabaseSchema.syncStatusSynced,
          };
          _log('UPSERT TOMBSTONE: installments $syncId');
          await _upsertInstallment(txn, tombstoneValues);
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
        affectedSaleIds.add(saleId);

        final installmentNumber = _readInt(record['installment_number']);
        final matchingSlotRows = existingRows.isEmpty
            ? await txn.query(
                DatabaseSchema.installmentsTable,
                where: 'venta_id = ? AND numero_cuota = ?',
                whereArgs: [saleId, installmentNumber],
                limit: 1,
              )
            : const <Map<String, Object?>>[];
        final resolvedExistingRows = existingRows.isEmpty
            ? matchingSlotRows
            : existingRows;

        if (_shouldKeepLocal(
          resolvedExistingRows,
          record,
          updatedAtField: 'fecha_actualizacion',
        )) {
          continue;
        }

        final values = {
          'sync_id': syncId,
          'id_remote': record['id']?.toString().trim(),
          'id_local': resolvedExistingRows.isEmpty
              ? null
              : resolvedExistingRows.first['id'],
          'version': _readVersion(record),
          'venta_id': saleId,
          'numero_cuota': installmentNumber,
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
          'last_modified_remote': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (resolvedExistingRows.isEmpty) {
          _log(
            '[SYNC] Insert new record: table=installments id=$syncId remote_delete=false',
          );
          await txn.insert(DatabaseSchema.installmentsTable, values);
        } else {
          _log(
            '[SYNC] Updating local record: table=installments id=$syncId remote_delete=false',
          );
          await txn.update(
            DatabaseSchema.installmentsTable,
            values,
            where: 'id = ?',
            whereArgs: [resolvedExistingRows.first['id']],
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
          // Cap paid amount at total to handle duplicate pagos without breaking display.
          final cappedPaidAmount = paidAmount > totalAmount ? _roundCurrency(totalAmount) : paidAmount;
          final interestAmount = _readDouble(installment['interes_cuota']);
          final principalAmount = _readDouble(installment['capital_cuota']);
          final interestPaid = _roundCurrency(
            cappedPaidAmount > interestAmount ? interestAmount : cappedPaidAmount,
          );
          final principalPaid = _roundCurrency(
            (cappedPaidAmount - interestPaid).clamp(0, principalAmount),
          );
          final dueDate =
              _parseDate(installment['fecha_vencimiento']?.toString()) ?? now;
          final newStatus = _resolveInstallmentStatusForReconcile(
            dueDate: dueDate,
            paidAmount: cappedPaidAmount,
            totalAmount: totalAmount,
            asOf: now,
          );

          final statusChanged = currentStatus != newStatus;
          final paidChanged =
              (_readDouble(installment['monto_pagado']) - cappedPaidAmount).abs() >
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
              'monto_pagado': cappedPaidAmount,
              'capital_pagado': principalPaid,
              'interes_pagado': interestPaid,
              'estado': newStatus,
              'fecha_actualizacion': nowIso,
              // Mark as pending so the corrected state is uploaded to the server.
              // This ensures syncSaleAggregates on the backend gets correct input
              // and updates syncPayload, breaking the stale-syncPayload download loop.
              'sync_status': DatabaseSchema.syncStatusPending,
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
            // Do NOT update fecha_actualizacion or sync_status here.
            // syncSaleAggregates on the server recalculates outstandingBalance
            // from payments. Marking the sale pending causes a permanent conflict
            // loop: server bumps sale.updatedAt via syncSaleAggregates (triggered
            // by payment uploads) AFTER the client reconcile timestamp.
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
  final localDeletedAt = local['deleted_at']?.toString().trim() ?? '';
  final remoteDeleted = _isDeleted(remoteRecord['deleted_at']);
  // Never revive a locally tombstoned commercial record from a non-deleted remote payload.
  if (localDeletedAt.isNotEmpty && !remoteDeleted) {
    return true;
  }
  final localSyncStatus = (local['sync_status'] as String? ?? '')
      .trim()
      .toLowerCase();
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

Future<void> _upsertInstallment(
  dynamic txn,
  Map<String, Object?> values,
) async {
  final updated = await txn.update(
    DatabaseSchema.installmentsTable,
    values,
    where: 'sync_id = ?',
    whereArgs: [values['sync_id']],
  );
  if (updated == 0) {
    await txn.insert(DatabaseSchema.installmentsTable, values);
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
