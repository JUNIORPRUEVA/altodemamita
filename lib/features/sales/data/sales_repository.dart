import 'dart:developer' as developer;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/system/system_config_service.dart';
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
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;

    final saleId = await db.transaction<int>((txn) async {
      await _ensureReferencedRowsExist(txn, draft);

      final selectedLot = await txn.query(
        DatabaseSchema.lotsTable,
        columns: ['id', 'estado', 'metros_cuadrados', 'precio_por_metro'],
        where: 'id = ?',
        whereArgs: [draft.lotId],
      );

      if (selectedLot.isEmpty) {
        throw StateError('El solar seleccionado no existe.');
      }

      final lotStatus = selectedLot.first['estado'] as String? ?? 'disponible';
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
        throw StateError('El monto mínimo de apartado no puede ser negativo.');
      }
      if (draft.minimumReserveAmount != null &&
          draft.minimumReserveAmount! - downPaymentAmount > 0.009) {
        throw StateError(
          'El monto mínimo de apartado no puede exceder el inicial requerido.',
        );
      }

      final saleId = await txn.insert(DatabaseSchema.salesTable, {
        'sync_id': _newSyncId('sale'),
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
        'fecha_limite_inicial': draft.initialPaymentDeadline?.toIso8601String(),
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
        'sync_status': DatabaseSchema.syncStatusPending,
      });

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
          'tipo_pago': saleStatus == 'apartado' ? 'apartado' : 'abono_inicial',
          'referencia': 'SALE-INIT-$saleId-${createdAt.microsecondsSinceEpoch}',
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
      'CREATE SALE -> local saleId=$saleId clientId=${draft.clientId} lotId=${draft.lotId} amount=${draft.salePrice}',
    );
    await _confirmSalesMutation(
      'create-sale:$saleId',
      const ['products', 'sales', 'installments', 'payments'],
    );
    _log('CREATE SALE FINAL -> saleId=$saleId confirmado por backend');
    return saleId;
  }

  Future<void> updateSale(int saleId, SaleDraft draft) async {
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    final deletedInstallmentPayloads = <Map<String, Object?>>[];

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

      final lotStatus = selectedLot.first['estado'] as String? ?? 'disponible';
      final isChangingLot = draft.lotId != previousLotId;
      if (isChangingLot && lotStatus != 'disponible') {
        throw StateError('El nuevo solar seleccionado ya no esta disponible.');
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
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      deletedInstallmentPayloads.addAll(
        existingInstallmentRows.map((row) => _buildDeletePayload(row)),
      );

      await txn.update(
        DatabaseSchema.installmentsTable,
        {
          'deleted_at': updatedAt.toIso8601String(),
          'fecha_actualizacion': updatedAt.toIso8601String(),
          'sync_status': DatabaseSchema.syncStatusPending,
        },
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );

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
          'tipo_pago': saleStatus == 'apartado' ? 'apartado' : 'abono_inicial',
          'referencia': 'SALE-INIT-$saleId-${updatedAt.microsecondsSinceEpoch}',
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
    await _confirmSalesMutation(
      'update-sale:$saleId',
      const ['products', 'sales', 'installments', 'payments'],
    );
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
    SystemConfigService.instance.ensureWritable();

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
    await _confirmSalesMutation(
      'delete-sale:$saleId',
      const ['products', 'sales', 'installments', 'payments'],
    );
    _log('DELETE SALE FINAL -> saleId=$saleId confirmado por backend');
  }

  Future<void> _confirmSalesMutation(
    String operationLabel,
    List<String> scopes,
  ) async {
    for (final scope in scopes) {
      await _syncQueueService.refreshScope(scope);
    }
    await _syncQueueService.syncScopesNowOrThrow(
      scopes,
      operationLabel: operationLabel,
    );
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

  String _newSyncId(String scope) {
    return SyncIdGenerator.next(scope);
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
