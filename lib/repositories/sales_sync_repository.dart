import 'dart:developer' as developer;

import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class SalesSyncRepository implements SyncRepository {
  SalesSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SistemaSolares.SalesSyncRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

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
      WHERE v.sync_status IN (?, ?, ?, ?, ?, ?)
      ORDER BY v.fecha_actualizacion ASC
    ''',
      [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingSync,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
    );
    return rows.map(_toPayload).toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markScopeRowsAsSynced(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.salesTable,
      syncIds: syncIds,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markScopeRowsAsConflict(
      appDatabase: _appDatabase,
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
    final affectedSaleIds = <int>{};
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
        if (_isDeleted(record['deleted_at'])) {
          if (_hasConflictProtectedPendingLocal(existingRows)) {
            await _markFirstExistingRowAsConflict(
              txn,
              tableName: DatabaseSchema.salesTable,
              existingRows: existingRows,
            );
            _log(
              'sales_remote_tombstone_conflict_pending_local sync_id=$syncId',
            );
            continue;
          }
          final clientSyncId = _readRequiredString(record['client_sync_id']);
          final productSyncId = _readRequiredString(record['product_sync_id']);
          final sellerSyncId = _readRequiredString(record['seller_sync_id']);
          final resolvedProductId = existingRows.isEmpty
              ? await _resolveIdBySyncId(
                  txn,
                  DatabaseSchema.lotsTable,
                  productSyncId,
                )
              : _readInt(existingRows.first['solar_id']);
          final matchedRows = existingRows;
          final matchedRow = matchedRows.isEmpty ? null : matchedRows.first;
          final clientId = matchedRow != null
              ? _readInt(matchedRow['cliente_id'])
              : existingRows.isEmpty
              ? await _resolveIdBySyncId(
                  txn,
                  DatabaseSchema.clientsTable,
                  clientSyncId,
                )
              : _readInt(existingRows.first['cliente_id']);
          final productId = matchedRow != null
              ? _readInt(matchedRow['solar_id'])
              : resolvedProductId;
          final sellerId = matchedRow != null
              ? _readNullableInt(matchedRow['vendedor_id'])
              : existingRows.isEmpty
              ? await _resolveIdBySyncId(
                  txn,
                  DatabaseSchema.sellersTable,
                  sellerSyncId,
                )
              : _readNullableInt(existingRows.first['vendedor_id']);
          if (clientId == null || productId == null) {
            throw RemoteSyncDependencyException(
              scope: scope,
              recordSyncId: syncId,
              missingScopes: {
                if (clientId == null && clientSyncId != null) 'clients',
                if (productId == null && productSyncId != null) 'products',
              },
              message:
                  'No se pudo aplicar tombstone remoto de sales $syncId porque faltan referencias locales requeridas.',
            );
          }

          final tombstoneValues = {
            'sync_id': syncId,
            'id_remote': record['id']?.toString().trim(),
            'id_local': matchedRow?['id'],
            'version': _readVersion(record),
            'cliente_id': clientId,
            'solar_id': productId,
            'usuario_id': 1,
            'vendedor_id': sellerId,
            'fecha_venta': _readDate(record['sale_date'] ?? record['created_at']),
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
            'estado': record['status'] ?? 'cancelada',
            'fecha_creacion': _readDate(record['created_at']),
            'fecha_actualizacion': _readDate(record['updated_at']),
            'last_modified_remote': _readDate(record['updated_at']),
            'deleted_at': _readNullableDate(record['deleted_at']),
            'sync_status': DatabaseSchema.syncStatusSynced,
          };
          _log('UPSERT TOMBSTONE: sales $syncId');
          await _upsertSale(txn, tombstoneValues);
          continue;
        }

        if (_shouldKeepLocal(
          existingRows,
          record,
          updatedAtField: 'fecha_actualizacion',
        )) {
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
          throw RemoteSyncDependencyException(
            scope: scope,
            recordSyncId: syncId,
            missingScopes: {
              if (clientId == null) 'clients',
              if (productId == null) 'products',
            },
            message:
                'No se pudo aplicar sale remoto $syncId porque faltan referencias locales requeridas.',
          );
        }

        final uniqueProductRows = existingRows.isEmpty
            ? await txn.query(
                DatabaseSchema.salesTable,
                where: 'solar_id = ?',
                whereArgs: [productId],
                limit: 1,
              )
            : const <Map<String, Object?>>[];
        final matchedRows = existingRows.isNotEmpty
            ? existingRows
            : uniqueProductRows;
        if (matchedRows.isNotEmpty &&
            _shouldKeepLocal(
              matchedRows,
              record,
              updatedAtField: 'fecha_actualizacion',
            )) {
          continue;
        }
        final matchedRow = matchedRows.isEmpty ? null : matchedRows.first;

        final values = {
          'sync_id': syncId,
          'id_remote': record['id']?.toString().trim(),
          'id_local': matchedRow?['id'],
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
          'last_modified_remote': _readDate(record['updated_at']),
          'deleted_at': _readNullableDate(record['deleted_at']),
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (matchedRows.isEmpty) {
          _log('[SYNC] Insert new record: table=sales id=$syncId remote_delete=false');
          await txn.insert(DatabaseSchema.salesTable, values);
        } else {
          _log('[SYNC] Updating local record: table=sales id=$syncId remote_delete=false');
          await txn.update(
            DatabaseSchema.salesTable,
            values,
            where: 'id = ?',
            whereArgs: [matchedRow!['id']],
          );
        }
        // Track the local sale ID so we can reconcile payment state after the transaction.
        final localSaleId = matchedRow?['id'];
        if (localSaleId is int) {
          affectedSaleIds.add(localSaleId);
        }
      }
    });

    if (affectedSaleIds.isNotEmpty) {
      await _reconcileSalesFromPayments(affectedSaleIds);
    }
  }

  Future<void> _reconcileSalesFromPayments(Set<int> saleIds) async {
    if (saleIds.isEmpty) return;
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
          if (currentStatus == 'cancelada') continue;

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

          final totalAmount = _readDouble(installment['monto_cuota']);
          final rawPaid = _roundCurrency(_readDouble(paidRows.first['paid_total']));
          // Cap at totalAmount to avoid over-payment display from duplicate pagos.
          final paidAmount = rawPaid > totalAmount ? _roundCurrency(totalAmount) : rawPaid;
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
              (_readDouble(installment['capital_pagado']) - principalPaid).abs() >
              0.009;
          final interestChanged =
              (_readDouble(installment['interes_pagado']) - interestPaid).abs() >
              0.009;

          if (!statusChanged && !paidChanged && !principalChanged && !interestChanged) {
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
            // from payments after every payment upload. Marking the sale as
            // pending causes a permanent conflict loop because the server bumps
            // sale.updatedAt (via syncSaleAggregates) AFTER the client reconcile
            // timestamp, so the upload always loses the conflict check.
          },
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [saleId],
        );
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
  final remoteDeleted = _isDeleted(remoteRecord['deleted_at']);
  if (localSyncStatus == DatabaseSchema.syncStatusPendingDelete &&
      !remoteDeleted) {
    return true;
  }
  // When local is in conflict, always accept the server's authoritative version.
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

bool _hasConflictProtectedPendingLocal(List<Map<String, Object?>> existingRows) {
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

Future<void> _upsertSale(
  dynamic txn,
  Map<String, Object?> values,
) async {
  final updated = await txn.update(
    DatabaseSchema.salesTable,
    values,
    where: 'sync_id = ?',
    whereArgs: [values['sync_id']],
  );
  if (updated == 0) {
    await txn.insert(DatabaseSchema.salesTable, values);
  }
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
