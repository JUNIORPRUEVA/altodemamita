import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/utils/sync_id_generator.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../../installments/domain/installment.dart';
import '../domain/sale.dart';
import '../domain/sale_calculator.dart';
import '../domain/sale_detail.dart';
import '../domain/sale_draft.dart';
import '../domain/sale_summary.dart';

class SalesRepository {
  SalesRepository({
    AppDatabase? appDatabase,
    SyncQueueService? syncQueueService,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncQueueService = syncQueueService ?? SyncQueueService.instance;

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;

  bool get _shouldRunBackgroundSync => identical(_appDatabase, AppDatabase.instance);

  void _log(String message) {
    developer.log(message, name: 'SistemaSolares.SalesSync');
  }

  Future<List<SaleSummary>> fetchAll({String query = ''}) async {
    final db = await _appDatabase.database;
    final normalizedQuery = query.trim();
    final whereClause = normalizedQuery.isEmpty
        ? 'WHERE v.deleted_at IS NULL AND c.deleted_at IS NULL AND s.deleted_at IS NULL'
        : '''
      WHERE v.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND s.deleted_at IS NULL
        AND (
          c.nombre LIKE ?
        OR c.cedula LIKE ?
        OR s.manzana_numero LIKE ?
        OR s.solar_numero LIKE ?
        OR v.estado LIKE ?
        )
    ''';

    final rows = await db.rawQuery(
      '''
      SELECT
        v.id,
        v.sync_status,
        v.fecha_venta,
        v.precio_venta,
        v.inicial_monto,
        v.monto_inicial_requerido,
        v.monto_inicial_pagado,
        v.monto_inicial_pendiente,
        v.monto_apartado_minimo,
        v.fecha_limite_inicial,
        v.saldo_financiado,
        v.saldo_pendiente,
        v.interes_mensual,
        v.cantidad_cuotas,
        v.estado,
        c.nombre AS cliente_nombre,
        c.cedula AS cliente_cedula,
        s.manzana_numero,
        s.solar_numero,
        COUNT(CASE WHEN q.estado <> 'ajustada' THEN 1 END) AS cuotas_generadas
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.venta_id = v.id AND q.deleted_at IS NULL
      $whereClause
      GROUP BY
        v.id,
        v.sync_status,
        v.fecha_venta,
        v.precio_venta,
        v.inicial_monto,
        v.monto_inicial_requerido,
        v.monto_inicial_pagado,
        v.monto_inicial_pendiente,
        v.monto_apartado_minimo,
        v.fecha_limite_inicial,
        v.saldo_financiado,
        v.saldo_pendiente,
        v.interes_mensual,
        v.cantidad_cuotas,
        v.estado,
        c.nombre,
        c.cedula,
        s.manzana_numero,
        s.solar_numero
      ORDER BY v.fecha_venta DESC, v.id DESC
      ''',
      normalizedQuery.isEmpty ? const [] : List.filled(5, '%$normalizedQuery%'),
    );

    return rows.map(SaleSummary.fromMap).toList();
  }

  Future<List<SaleSummary>> fetchBySellerId(int sellerId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        v.id,
        v.sync_status,
        v.fecha_venta,
        v.precio_venta,
        v.inicial_monto,
        v.monto_inicial_requerido,
        v.monto_inicial_pagado,
        v.monto_inicial_pendiente,
        v.monto_apartado_minimo,
        v.fecha_limite_inicial,
        v.saldo_financiado,
        v.saldo_pendiente,
        v.interes_mensual,
        v.cantidad_cuotas,
        v.estado,
        c.nombre AS cliente_nombre,
        c.cedula AS cliente_cedula,
        s.manzana_numero,
        s.solar_numero,
        COUNT(CASE WHEN q.estado <> 'ajustada' THEN 1 END) AS cuotas_generadas
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.venta_id = v.id AND q.deleted_at IS NULL
      WHERE v.vendedor_id = ?
        AND v.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND s.deleted_at IS NULL
      GROUP BY
        v.id,
        v.sync_status,
        v.fecha_venta,
        v.precio_venta,
        v.inicial_monto,
        v.monto_inicial_requerido,
        v.monto_inicial_pagado,
        v.monto_inicial_pendiente,
        v.monto_apartado_minimo,
        v.fecha_limite_inicial,
        v.saldo_financiado,
        v.saldo_pendiente,
        v.interes_mensual,
        v.cantidad_cuotas,
        v.estado,
        c.nombre,
        c.cedula,
        s.manzana_numero,
        s.solar_numero
      ORDER BY v.fecha_venta DESC, v.id DESC
      ''',
      [sellerId],
    );

    return rows.map(SaleSummary.fromMap).toList();
  }

  Future<SaleDetail?> fetchDetail(int saleId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        v.*,
        c.nombre AS cliente_nombre,
        c.cedula AS cliente_cedula,
        s.manzana_numero,
        s.solar_numero,
        s.metros_cuadrados,
        s.precio_por_metro,
        u.nombre AS usuario_nombre,
        vnd.nombre AS vendedor_nombre,
        vnd.cedula AS vendedor_cedula,
        vnd.telefono AS vendedor_telefono
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      INNER JOIN ${DatabaseSchema.usersTable} u ON u.id = v.usuario_id
      LEFT JOIN ${DatabaseSchema.sellersTable} vnd ON vnd.id = v.vendedor_id
      WHERE v.id = ? AND v.deleted_at IS NULL
      ''',
      [saleId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final sale = Sale.fromMap(rows.first);
    final initialPaymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      columns: ['metodo_pago'],
      where: 'venta_id = ? AND cuota_id IS NULL AND deleted_at IS NULL',
      whereArgs: [saleId],
      orderBy: 'fecha_pago ASC, id ASC',
      limit: 1,
    );
    final installmentsRows = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ? AND deleted_at IS NULL AND estado <> ?',
      whereArgs: [saleId, 'ajustada'],
      orderBy: 'numero_cuota ASC',
    );

    return SaleDetail(
      sale: sale,
      clientName: rows.first['cliente_nombre'] as String? ?? '',
      clientDocumentId: rows.first['cliente_cedula'] as String? ?? '',
      lotDisplayCode:
          'M${rows.first['manzana_numero'] as String? ?? ''}-S${rows.first['solar_numero'] as String? ?? ''}',
      lotArea: _toDouble(rows.first['metros_cuadrados']),
      lotPricePerSquareMeter: _toDouble(rows.first['precio_por_metro']),
      userName: rows.first['usuario_nombre'] as String? ?? '',
      initialPaymentMethod: initialPaymentRows.isEmpty
          ? 'efectivo'
          : _normalizeInitialPaymentMethod(
              initialPaymentRows.first['metodo_pago'] as String? ?? '',
            ),
      sellerName: rows.first['vendedor_nombre'] as String?,
      sellerDocumentId: rows.first['vendedor_cedula'] as String?,
      sellerPhone: rows.first['vendedor_telefono'] as String?,
      installments: installmentsRows.map(Installment.fromMap).toList(),
    );
  }

  Future<int> createSale(SaleDraft draft) async {
    print(
      '[SALES][DB] createSale start clientId=${draft.clientId} lotId=${draft.lotId} sellerId=${draft.sellerId} price=${draft.salePrice}',
    );
    final db = await _appDatabase.database;
    late final String saleSyncId;

    try {
      final saleId = await db.transaction<int>((txn) async {
        print('[SALES][DB] txn start -> ensure referenced rows');
        await _ensureReferencedRowsExist(txn, draft);
        print('[SALES][DB] referenced rows OK -> validating lot');

        final selectedLot = await txn.query(
          DatabaseSchema.lotsTable,
          columns: ['id', 'estado', 'metros_cuadrados', 'precio_por_metro'],
          where: 'id = ?',
          whereArgs: [draft.lotId],
        );

        if (selectedLot.isEmpty) {
          throw StateError('El solar seleccionado no existe.');
        }

        final lotStatus =
            selectedLot.first['estado'] as String? ?? 'disponible';
        if (lotStatus != 'disponible') {
          throw StateError('El solar seleccionado ya no esta disponible.');
        }

        final existingSale = await txn.query(
          DatabaseSchema.salesTable,
          columns: ['id'],
          where: 'solar_id = ?',
          whereArgs: [draft.lotId],
          limit: 1,
        );

        if (existingSale.isNotEmpty) {
          throw StateError('Ya existe una venta registrada para este solar.');
        }

        if (draft.downPaymentPercentage < 0 ||
            draft.downPaymentPercentage > 100) {
          throw StateError(
            'El porcentaje de inicial debe estar entre 0% y 100%.',
          );
        }

        if (draft.monthlyInterest < 0) {
          throw StateError('El interes mensual no puede ser negativo.');
        }

        if (draft.installmentCount <= 0) {
          throw StateError('La venta debe generar al menos una cuota.');
        }

        final currentSalePrice = draft.salePrice > 0
            ? draft.salePrice
            : _resolveLotTotalPrice(selectedLot.first);
        if (currentSalePrice <= 0) {
          throw StateError(
            'El solar seleccionado no tiene un precio total válido para registrar la venta.',
          );
        }

        final createdAt = DateTime.now();
        print('[SALES][DB] validations OK -> inserting sale row');
        saleSyncId = _newLocalSaleSyncId();
        final downPaymentAmount = _roundCurrency(draft.requiredInitialPayment);
        final initialPaidAmount = _roundCurrency(draft.initialPaymentPaid);
        final financedBalance = SaleCalculator.calculateFinancedBalance(
          salePrice: currentSalePrice,
          downPaymentAmount: initialPaidAmount,
        );
        final initialPendingAmount =
            SaleCalculator.calculatePendingInitialPayment(
              requiredInitialPayment: downPaymentAmount,
              initialPaymentPaid: initialPaidAmount,
            );
        final saleStatus = _resolveSaleStatus(
          initialRequiredAmount: downPaymentAmount,
          initialPaidAmount: initialPaidAmount,
          minimumReserveAmount: draft.minimumReserveAmount,
          financedBalance: financedBalance,
        );

        if (initialPaidAmount < 0) {
          throw StateError('El inicial pagado no puede ser negativo.');
        }
        if (initialPaidAmount + 0.009 < downPaymentAmount) {
          throw StateError(
            'El inicial pagado no puede ser menor al inicial mínimo requerido.',
          );
        }
        if (initialPaidAmount - currentSalePrice > 0.009) {
          throw StateError(
            'El inicial pagado no puede exceder el precio total del solar.',
          );
        }
        if (draft.minimumReserveAmount != null &&
            draft.minimumReserveAmount! < 0) {
          throw StateError(
            'El monto mínimo de apartado no puede ser negativo.',
          );
        }
        if (draft.minimumReserveAmount != null &&
            draft.minimumReserveAmount! - downPaymentAmount > 0.009) {
          throw StateError(
            'El monto mínimo de apartado no puede exceder el inicial requerido.',
          );
        }

        final saleId = await txn.insert(DatabaseSchema.salesTable, {
          'sync_id': saleSyncId,
          'cliente_id': draft.clientId,
          'solar_id': draft.lotId,
          'usuario_id': draft.userId,
          'vendedor_id': draft.sellerId,
          'fecha_venta': draft.saleDate.toIso8601String(),
          'precio_venta': currentSalePrice,
          'inicial_porcentaje': draft.downPaymentPercentage,
          'inicial_monto': initialPaidAmount,
          'monto_inicial_requerido': downPaymentAmount,
          'monto_inicial_pagado': initialPaidAmount,
          'monto_inicial_pendiente': initialPendingAmount,
          'monto_apartado_minimo': draft.minimumReserveAmount,
          'fecha_limite_inicial': draft.initialPaymentDeadline
              ?.toIso8601String(),
          'fecha_activacion': saleStatus == 'activa' || saleStatus == 'pagada'
              ? draft.saleDate.toIso8601String()
              : null,
          'saldo_financiado': financedBalance,
          'saldo_pendiente': financedBalance,
          'interes_mensual': draft.monthlyInterest,
          'cantidad_cuotas': draft.installmentCount,
          'estado': saleStatus,
          'fecha_creacion': createdAt.toIso8601String(),
          'fecha_actualizacion': createdAt.toIso8601String(),
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusPendingSync,
        });
        print('[SALES][DB] Venta creada -> saleId=$saleId syncId=$saleSyncId');

        final batch = txn.batch();
        if (saleStatus == 'activa') {
          final installments = SaleCalculator.buildInstallmentSchedule(
            saleId: saleId,
            saleDate: draft.saleDate,
            financedBalance: financedBalance,
            monthlyInterest: draft.monthlyInterest,
            installmentCount: draft.installmentCount,
            createdAt: createdAt,
          );
          _validateInstallmentSequence(installments, saleId: saleId);
          final deletedInstallments = await txn.delete(
            DatabaseSchema.installmentsTable,
            where: 'venta_id = ?',
            whereArgs: [saleId],
          );
          if (deletedInstallments > 0) {
            print(
              '[SALES][DB] createSale deleting stale installments saleId=$saleId count=$deletedInstallments',
            );
          }
          for (final installment in installments) {
            batch.insert(
              DatabaseSchema.installmentsTable,
              installment.toMap()
                ..['sync_id'] = _newSyncId('installment')
                ..['deleted_at'] = null
                ..['sync_status'] = DatabaseSchema.syncStatusPending
                ..remove('id'),
            );
          }
          print(
            '[SALES][DB] Cuotas generadas -> saleId=$saleId count=${installments.length}',
          );
        }

        if (initialPaidAmount > 0) {
          batch.insert(DatabaseSchema.paymentsTable, {
            'sync_id': _newSyncId('payment'),
            'venta_id': saleId,
            'cliente_id': draft.clientId,
            'usuario_id': draft.userId,
            'cuota_id': null,
            'fecha_pago': draft.saleDate.toIso8601String(),
            'monto_pagado': initialPaidAmount,
            'metodo_pago': _normalizeInitialPaymentMethod(
              draft.initialPaymentMethod,
            ),
            'tipo_pago': saleStatus == 'apartado'
                ? 'apartado'
                : 'abono_inicial',
            'referencia':
                'SALE-INIT-$saleId-${createdAt.microsecondsSinceEpoch}',
            'ano_a_pagar': null,
            'fecha_creacion': createdAt.toIso8601String(),
            'fecha_actualizacion': createdAt.toIso8601String(),
            'deleted_at': null,
            'sync_status': DatabaseSchema.syncStatusPending,
          });
        }

        batch.update(
          DatabaseSchema.lotsTable,
          {
            'estado': saleStatus == 'activa' || saleStatus == 'pagada'
                ? 'vendido'
                : 'reservado',
            'fecha_actualizacion': createdAt.toIso8601String(),
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [draft.lotId],
        );
        await batch.commit(noResult: true);

        return saleId;
      });

      _log(
        'SALE LOCAL CREATED -> saleId=$saleId syncId=$saleSyncId status=${DatabaseSchema.syncStatusPendingSync} clientId=${draft.clientId} lotId=${draft.lotId} amount=${draft.salePrice}',
      );
      _log(
        'Guardado en local -> scope=sales operation=create saleId=$saleId sync_status=${DatabaseSchema.syncStatusPendingSync}',
      );
      print(
        '[SALES][DB] createSale success -> saleId=$saleId syncId=$saleSyncId',
      );
      _scheduleCreateSaleSync(saleId: saleId, saleSyncId: saleSyncId);
      return saleId;
    } catch (error, stack) {
      print('[SALES][DB] createSale ERROR $error');
      print(stack);
      rethrow;
    }
  }

  Future<void> updateSale(int saleId, SaleDraft draft) async {
    final db = await _appDatabase.database;
    final deletedInstallmentPayloads = <Map<String, Object?>>[];

    try {
      print(
        '[SALES][DB] updateSale start saleId=$saleId clientId=${draft.clientId} lotId=${draft.lotId} installments=${draft.installmentCount}',
      );
      await db.transaction<void>((txn) async {
        await _ensureReferencedRowsExist(txn, draft);

        final existingRows = await txn.query(
          DatabaseSchema.salesTable,
          columns: ['id', 'solar_id', 'estado'],
          where: 'id = ?',
          whereArgs: [saleId],
          limit: 1,
        );

        if (existingRows.isEmpty) {
          throw StateError('La venta seleccionada no existe.');
        }

        final paymentRows = await txn.query(
          DatabaseSchema.paymentsTable,
          columns: ['id', 'monto_pagado', 'tipo_pago', 'cuota_id'],
          where: 'venta_id = ?',
          whereArgs: [saleId],
          orderBy: 'id ASC',
        );
        final editableInitialPaymentRows = paymentRows
            .where((row) {
              final paymentType = row['tipo_pago'] as String? ?? '';
              return row['cuota_id'] == null &&
                  (paymentType == 'apartado' || paymentType == 'abono_inicial');
            })
            .toList(growable: false);
        final hasLockedPayments = paymentRows.any((row) {
          final paymentType = row['tipo_pago'] as String? ?? '';
          return row['cuota_id'] != null || paymentType == 'abono_capital';
        });
        if (hasLockedPayments) {
          throw StateError(
            'No se puede editar una venta que ya tiene pagos registrados.',
          );
        }

        final existingSale = existingRows.first;
        final previousLotId = existingSale['solar_id'] as int? ?? 0;

        final selectedLot = await txn.query(
          DatabaseSchema.lotsTable,
          columns: ['id', 'estado', 'metros_cuadrados', 'precio_por_metro'],
          where: 'id = ?',
          whereArgs: [draft.lotId],
          limit: 1,
        );

        if (selectedLot.isEmpty) {
          throw StateError('El solar seleccionado no existe.');
        }

        final lotStatus =
            selectedLot.first['estado'] as String? ?? 'disponible';
        final isChangingLot = draft.lotId != previousLotId;
        if (isChangingLot && lotStatus != 'disponible') {
          throw StateError(
            'El nuevo solar seleccionado ya no esta disponible.',
          );
        }

        if (isChangingLot) {
          final existingSaleForLot = await txn.query(
            DatabaseSchema.salesTable,
            columns: ['id'],
            where: 'solar_id = ? AND id <> ?',
            whereArgs: [draft.lotId, saleId],
            limit: 1,
          );

          if (existingSaleForLot.isNotEmpty) {
            throw StateError(
              'Ya existe una venta registrada para el nuevo solar.',
            );
          }
        }

        if (draft.downPaymentPercentage < 0 ||
            draft.downPaymentPercentage > 100) {
          throw StateError(
            'El porcentaje de inicial debe estar entre 0% y 100%.',
          );
        }

        if (draft.monthlyInterest < 0) {
          throw StateError('El interes mensual no puede ser negativo.');
        }

        if (draft.installmentCount <= 0) {
          throw StateError('La venta debe generar al menos una cuota.');
        }

        final currentSalePrice = draft.salePrice > 0
            ? draft.salePrice
            : _resolveLotTotalPrice(selectedLot.first);
        if (currentSalePrice <= 0) {
          throw StateError('La venta debe tener un precio total válido.');
        }

        final updatedAt = DateTime.now();
        final downPaymentAmount = _roundCurrency(draft.requiredInitialPayment);
        final initialPaidAmount = _roundCurrency(draft.initialPaymentPaid);
        final financedBalance = SaleCalculator.calculateFinancedBalance(
          salePrice: currentSalePrice,
          downPaymentAmount: initialPaidAmount,
        );
        final initialPendingAmount =
            SaleCalculator.calculatePendingInitialPayment(
              requiredInitialPayment: downPaymentAmount,
              initialPaymentPaid: initialPaidAmount,
            );
        final saleStatus = _resolveSaleStatus(
          initialRequiredAmount: downPaymentAmount,
          initialPaidAmount: initialPaidAmount,
          minimumReserveAmount: draft.minimumReserveAmount,
          financedBalance: financedBalance,
        );

        if (initialPaidAmount < 0) {
          throw StateError('El inicial pagado no puede ser negativo.');
        }
        if (initialPaidAmount + 0.009 < downPaymentAmount) {
          throw StateError(
            'El inicial pagado no puede ser menor al inicial mínimo requerido.',
          );
        }
        if (initialPaidAmount - currentSalePrice > 0.009) {
          throw StateError(
            'El inicial pagado no puede exceder el precio total del solar.',
          );
        }

        final existingInitialPaid = editableInitialPaymentRows.fold<double>(
          0,
          (sum, row) => sum + _toDouble(row['monto_pagado']),
        );
        if (editableInitialPaymentRows.isNotEmpty &&
            (existingInitialPaid - initialPaidAmount).abs() > 0.009) {
          throw StateError(
            'No se puede cambiar el inicial pagado de una venta que ya tiene pagos iniciales registrados.',
          );
        }

        await txn.update(
          DatabaseSchema.salesTable,
          {
            'cliente_id': draft.clientId,
            'solar_id': draft.lotId,
            'usuario_id': draft.userId,
            'vendedor_id': draft.sellerId,
            'fecha_venta': draft.saleDate.toIso8601String(),
            'precio_venta': currentSalePrice,
            'inicial_porcentaje': draft.downPaymentPercentage,
            'inicial_monto': initialPaidAmount,
            'monto_inicial_requerido': downPaymentAmount,
            'monto_inicial_pagado': initialPaidAmount,
            'monto_inicial_pendiente': initialPendingAmount,
            'monto_apartado_minimo': draft.minimumReserveAmount,
            'fecha_limite_inicial': draft.initialPaymentDeadline
                ?.toIso8601String(),
            'fecha_activacion': saleStatus == 'activa' || saleStatus == 'pagada'
                ? draft.saleDate.toIso8601String()
                : null,
            'saldo_financiado': financedBalance,
            'saldo_pendiente': financedBalance,
            'interes_mensual': draft.monthlyInterest,
            'cantidad_cuotas': draft.installmentCount,
            'estado': saleStatus,
            'fecha_actualizacion': updatedAt.toIso8601String(),
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );

        final normalizedInitialPaymentMethod = _normalizeInitialPaymentMethod(
          draft.initialPaymentMethod,
        );
        if (editableInitialPaymentRows.isNotEmpty) {
          await txn.update(
            DatabaseSchema.paymentsTable,
            {
              'cliente_id': draft.clientId,
              'usuario_id': draft.userId,
              'metodo_pago': normalizedInitialPaymentMethod,
              'fecha_actualizacion': updatedAt.toIso8601String(),
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'venta_id = ? AND cuota_id IS NULL AND tipo_pago IN (?, ?)',
            whereArgs: [saleId, 'apartado', 'abono_inicial'],
          );
        }

        final existingInstallmentRows = await txn.query(
          DatabaseSchema.installmentsTable,
          where: 'venta_id = ?',
          whereArgs: [saleId],
          orderBy: 'numero_cuota ASC, id ASC',
        );
        deletedInstallmentPayloads.addAll(
          existingInstallmentRows
              .where(
                (row) =>
                    (row['sync_id']?.toString().trim().isNotEmpty ?? false),
              )
              .map((row) => _buildDeletePayload(row)),
        );

        if (existingInstallmentRows.isNotEmpty) {
          print(
            '[SALES][DB] updateSale deleting existing installments saleId=$saleId count=${existingInstallmentRows.length}',
          );
          await txn.delete(
            DatabaseSchema.installmentsTable,
            where: 'venta_id = ?',
            whereArgs: [saleId],
          );
        }

        final batch = txn.batch();
        if (saleStatus == 'activa') {
          final installments = SaleCalculator.buildInstallmentSchedule(
            saleId: saleId,
            saleDate: draft.saleDate,
            financedBalance: financedBalance,
            monthlyInterest: draft.monthlyInterest,
            installmentCount: draft.installmentCount,
            createdAt: updatedAt,
          );
          _validateInstallmentSequence(installments, saleId: saleId);
          for (final installment in installments) {
            batch.insert(
              DatabaseSchema.installmentsTable,
              installment.toMap()
                ..['sync_id'] = _newSyncId('installment')
                ..['deleted_at'] = null
                ..['sync_status'] = DatabaseSchema.syncStatusPending
                ..remove('id'),
            );
          }
        }

        if (editableInitialPaymentRows.isEmpty && initialPaidAmount > 0) {
          batch.insert(DatabaseSchema.paymentsTable, {
            'sync_id': _newSyncId('payment'),
            'venta_id': saleId,
            'cliente_id': draft.clientId,
            'usuario_id': draft.userId,
            'cuota_id': null,
            'fecha_pago': draft.saleDate.toIso8601String(),
            'monto_pagado': initialPaidAmount,
            'metodo_pago': normalizedInitialPaymentMethod,
            'tipo_pago': saleStatus == 'apartado'
                ? 'apartado'
                : 'abono_inicial',
            'referencia':
                'SALE-INIT-$saleId-${updatedAt.microsecondsSinceEpoch}',
            'ano_a_pagar': null,
            'fecha_creacion': updatedAt.toIso8601String(),
            'fecha_actualizacion': updatedAt.toIso8601String(),
            'deleted_at': null,
            'sync_status': DatabaseSchema.syncStatusPending,
          });
        }

        if (isChangingLot) {
          batch.update(
            DatabaseSchema.lotsTable,
            {
              'estado': 'disponible',
              'fecha_actualizacion': updatedAt.toIso8601String(),
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'id = ?',
            whereArgs: [previousLotId],
          );
        }

        batch.update(
          DatabaseSchema.lotsTable,
          {
            'estado': saleStatus == 'activa' || saleStatus == 'pagada'
                ? 'vendido'
                : 'reservado',
            'fecha_actualizacion': updatedAt.toIso8601String(),
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [draft.lotId],
        );

        await batch.commit(noResult: true);
      });

      for (final payload in deletedInstallmentPayloads) {
        final syncId = payload['sync_id']?.toString().trim();
        if (syncId == null || syncId.isEmpty) {
          continue;
        }
        await _syncQueueService.enqueueDelete(
          scope: 'installments',
          recordSyncId: syncId,
          payload: payload,
        );
      }
      _log(
        'SALE LOCAL UPDATED -> saleId=$saleId installments=${draft.installmentCount}',
      );
      _log(
        'Guardado en local -> scope=sales operation=update saleId=$saleId sync_status=${DatabaseSchema.syncStatusPending}',
      );
      _scheduleSaleMutationSync('update-sale:$saleId', const [
        'products',
        'sales',
        'installments',
        'payments',
      ]);
    } catch (error, stack) {
      print('[SALES][DB] updateSale ERROR $error');
      print(stack);
      rethrow;
    }
  }

  String _normalizeInitialPaymentMethod(String value) {
    const allowedMethods = {'efectivo', 'transferencia', 'cheque', 'tarjeta'};

    final normalized = value.trim().toLowerCase();
    if (allowedMethods.contains(normalized)) {
      return normalized;
    }

    return 'efectivo';
  }

  Future<void> deleteSale(int saleId) async {
    final db = await _appDatabase.database;
    final deleteQueue =
        <({String scope, String syncId, Map<String, Object?> payload})>[];

    await db.transaction<void>((txn) async {
      final deletedAt = DateTime.now().toIso8601String();
      final saleRows = await txn.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );

      if (saleRows.isEmpty) {
        throw StateError('La venta seleccionada no existe.');
      }

      final paymentRows = await txn.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      final installmentRows = await txn.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );

      for (final row in paymentRows) {
        final syncId = (row['sync_id'] as String?)?.trim();
        if (syncId == null || syncId.isEmpty) {
          continue;
        }
        deleteQueue.add((
          scope: 'payments',
          syncId: syncId,
          payload: _buildDeletePayload(
            row,
            updatedAtField: 'fecha_actualizacion',
          ),
        ));
      }
      for (final row in installmentRows) {
        final syncId = (row['sync_id'] as String?)?.trim();
        if (syncId == null || syncId.isEmpty) {
          continue;
        }
        deleteQueue.add((
          scope: 'installments',
          syncId: syncId,
          payload: _buildDeletePayload(row),
        ));
      }

      final saleRow = saleRows.first;
      final saleSyncId = (saleRow['sync_id'] as String?)?.trim();
      if (saleSyncId != null && saleSyncId.isNotEmpty) {
        deleteQueue.add((
          scope: 'sales',
          syncId: saleSyncId,
          payload: _buildDeletePayload(saleRow),
        ));
      }

      final lotId = saleRow['solar_id'] as int?;
      await txn.update(
        DatabaseSchema.paymentsTable,
        {
          'deleted_at': deletedAt,
          'fecha_actualizacion': deletedAt,
          'sync_status': DatabaseSchema.syncStatusPending,
        },
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );

      await txn.update(
        DatabaseSchema.installmentsTable,
        {
          'deleted_at': deletedAt,
          'fecha_actualizacion': deletedAt,
          'sync_status': DatabaseSchema.syncStatusPending,
        },
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );

      await txn.update(
        DatabaseSchema.salesTable,
        {
          'deleted_at': deletedAt,
          'fecha_actualizacion': deletedAt,
          'sync_status': DatabaseSchema.syncStatusPending,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      if (lotId != null) {
        await txn.update(
          DatabaseSchema.lotsTable,
          {
            'estado': 'disponible',
            'fecha_actualizacion': deletedAt,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [lotId],
        );
      }
    });

    for (final item in deleteQueue) {
      await _syncQueueService.enqueueDelete(
        scope: item.scope,
        recordSyncId: item.syncId,
        payload: item.payload,
      );
    }
    _log('DELETE SALE -> local saleId=$saleId queued for backend deletion');
    _log(
      'Guardado en local -> scope=sales operation=delete saleId=$saleId sync_status=${DatabaseSchema.syncStatusPending}',
    );
    _scheduleSaleMutationSync('delete-sale:$saleId', const [
      'products',
      'sales',
      'installments',
      'payments',
    ]);
  }

  Future<void> _ensureReferencedRowsExist(
    DatabaseExecutor txn,
    SaleDraft draft,
  ) async {
    final clientRows = await txn.query(
      DatabaseSchema.clientsTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [draft.clientId],
      limit: 1,
    );
    if (clientRows.isEmpty) {
      throw StateError('El cliente seleccionado no existe.');
    }

    final userRows = await txn.query(
      DatabaseSchema.usersTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [draft.userId],
      limit: 1,
    );
    if (userRows.isEmpty) {
      throw StateError('El usuario seleccionado no existe.');
    }
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  double _resolveLotTotalPrice(Map<String, Object?> row) {
    final area = _toDouble(row['metros_cuadrados']);
    final unitPrice = _toDouble(row['precio_por_metro']);
    return _roundCurrency(area * unitPrice);
  }

  String _resolveSaleStatus({
    required double initialRequiredAmount,
    required double initialPaidAmount,
    required double? minimumReserveAmount,
    required double financedBalance,
  }) {
    if (financedBalance <= 0) {
      return 'pagada';
    }
    if (initialPaidAmount >= initialRequiredAmount - 0.009) {
      return 'activa';
    }
    final reserveMinimum = minimumReserveAmount ?? 0;
    if (initialPaidAmount <= 0 || initialPaidAmount < reserveMinimum - 0.009) {
      return 'apartado';
    }
    return 'inicial_incompleto';
  }

  double _roundCurrency(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  void _validateInstallmentSequence(
    List<Installment> installments, {
    required int saleId,
  }) {
    final usedNumbers = <int>{};
    for (final installment in installments) {
      final number = installment.installmentNumber;
      if (!usedNumbers.add(number)) {
        throw StateError(
          'Se detectó un numero_cuota duplicado al regenerar cuotas para la venta $saleId: $number',
        );
      }
    }
  }

  void _scheduleCreateSaleSync({
    required int saleId,
    required String saleSyncId,
  }) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    unawaited(_runCreateSaleSync(saleId: saleId, saleSyncId: saleSyncId));
  }

  void _scheduleSaleMutationSync(String operationLabel, List<String> scopes) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    unawaited(_runSaleMutationSync(operationLabel, scopes));
  }

  Future<void> _runCreateSaleSync({
    required int saleId,
    required String saleSyncId,
  }) async {
    const scopes = ['products', 'sales', 'installments', 'payments'];
    _log(
      'Intentando sync -> scope=sales saleId=$saleId syncId=$saleSyncId scopes=${scopes.join(',')}',
    );

    try {
      for (final scope in scopes) {
        await _syncQueueService.refreshScope(scope);
      }

      final processed = await _syncQueueService.processQueue(
        includeDeferred: true,
      );
      final saleSyncStatus = await _readSaleSyncStatus(saleId);

      if (saleSyncStatus == DatabaseSchema.syncStatusSynced) {
        _log(
          'Sync exitoso -> scope=sales saleId=$saleId syncId=$saleSyncId processed=$processed status=$saleSyncStatus',
        );
        return;
      }

      _log(
        'Sync falló -> scope=sales saleId=$saleId syncId=$saleSyncId processed=$processed status=${saleSyncStatus ?? DatabaseSchema.syncStatusPendingSync} retry=automatico',
      );
    } catch (error) {
      _log(
        'Sync falló -> scope=sales saleId=$saleId syncId=$saleSyncId error=$error retry=automatico',
      );
    }
  }

  Future<void> _runSaleMutationSync(
    String operationLabel,
    List<String> scopes,
  ) async {
    _log(
      'Intentando sync -> scope=sales operation=$operationLabel scopes=${scopes.join(',')}',
    );
    try {
      for (final scope in scopes) {
        await _syncQueueService.refreshScope(scope);
      }
      final processed = await _syncQueueService.processQueue(
        includeDeferred: true,
      );
      _log(
        'Sync exitoso -> scope=sales operation=$operationLabel processed=$processed',
      );
    } catch (error) {
      _log(
        'Sync falló -> scope=sales operation=$operationLabel error=$error retry=automatico',
      );
    }
  }

  String _newSyncId(String scope) {
    return SyncIdGenerator.next(scope);
  }

  String _newLocalSaleSyncId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<String?> _readSaleSyncStatus(int saleId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.salesTable,
      columns: ['sync_status'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['sync_status']?.toString().trim();
  }

  Map<String, Object?> _buildDeletePayload(
    Map<String, Object?> row, {
    String updatedAtField = 'fecha_actualizacion',
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'id': row['id'],
      'sync_id': row['sync_id'],
      'version': ((row['version'] as int?) ?? 1) + 1,
      'created_at': row['fecha_creacion'],
      'updated_at': row[updatedAtField] ?? row['fecha_creacion'] ?? now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPending,
    };
  }
}
