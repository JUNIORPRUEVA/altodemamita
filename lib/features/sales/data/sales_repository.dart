import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
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
    BackendApiClient? apiClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _apiClient = apiClient ?? BackendApiClient();

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;
  final BackendApiClient _apiClient;
  final BackendEntityIdRegistry _idRegistry = BackendEntityIdRegistry.instance;

  bool get _shouldRunBackgroundSync =>
      identical(_appDatabase, AppDatabase.instance);
  bool get _useBackendMode => false;

  void _log(String message) {
    developer.log(message, name: 'SistemaSolares.SalesSync');
  }

  Future<List<SaleSummary>> fetchAll({String query = ''}) async {
    if (_useBackendMode) {
      return _fetchAllFromBackend(query: query);
    }

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
    if (_useBackendMode) {
      final remoteSellerId = _idRegistry.resolveRemoteId('sellers', sellerId);
      if (remoteSellerId == null || remoteSellerId.isEmpty) {
        return const [];
      }
      return _fetchAllFromBackend(sellerRemoteId: remoteSellerId);
    }

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
    if (_useBackendMode) {
      return _fetchDetailFromBackend(saleId);
    }

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
    if (_useBackendMode) {
      return _createSaleInBackend(draft);
    }

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
        final pendingBalance = saleStatus == 'activa' || saleStatus == 'pagada'
            ? SaleCalculator.calculateTotalFinancingAmount(
                financedBalance: financedBalance,
                monthlyInterest: draft.monthlyInterest,
                installmentCount: draft.installmentCount,
              )
            : financedBalance;

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
          'id_local': null,
          'id_remote': null,
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
            'saldo_pendiente': pendingBalance,
          'interes_mensual': draft.monthlyInterest,
          'cantidad_cuotas': draft.installmentCount,
          'estado': saleStatus,
          'fecha_creacion': createdAt.toIso8601String(),
          'fecha_actualizacion': createdAt.toIso8601String(),
          'last_modified_local': createdAt.toIso8601String(),
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusPendingCreate,
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
                ..['id_local'] = null
                ..['id_remote'] = null
                ..['last_modified_local'] = createdAt.toIso8601String()
                ..['deleted_at'] = null
                ..['sync_status'] = DatabaseSchema.syncStatusPendingCreate
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
            'last_modified_local': createdAt.toIso8601String(),
            'deleted_at': null,
            'sync_status': DatabaseSchema.syncStatusPendingCreate,
          });
        }

        batch.update(
          DatabaseSchema.lotsTable,
          {
            'estado': saleStatus == 'activa' || saleStatus == 'pagada'
                ? 'vendido'
                : 'reservado',
            'fecha_actualizacion': createdAt.toIso8601String(),
            'last_modified_local': createdAt.toIso8601String(),
            'sync_status': DatabaseSchema.syncStatusPendingUpdate,
          },
          where: 'id = ?',
          whereArgs: [draft.lotId],
        );
        await batch.commit(noResult: true);

        return saleId;
      });

      _log(
        'SALE LOCAL CREATED -> saleId=$saleId syncId=$saleSyncId status=${DatabaseSchema.syncStatusPendingCreate} clientId=${draft.clientId} lotId=${draft.lotId} amount=${draft.salePrice}',
      );
      _log(
        'Guardado en local -> scope=sales operation=create saleId=$saleId sync_status=${DatabaseSchema.syncStatusPendingCreate}',
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
    if (_useBackendMode) {
      await _updateSaleInBackend(saleId, draft);
      return;
    }

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
          columns: ['id', 'solar_id', 'estado', 'version'],
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
        final nextSaleVersion = ((existingSale['version'] as int?) ?? 1) + 1;

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
        final pendingBalance = saleStatus == 'activa' || saleStatus == 'pagada'
            ? SaleCalculator.calculateTotalFinancingAmount(
                financedBalance: financedBalance,
                monthlyInterest: draft.monthlyInterest,
                installmentCount: draft.installmentCount,
              )
            : financedBalance;

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
            'version': nextSaleVersion,
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
            'saldo_pendiente': pendingBalance,
            'interes_mensual': draft.monthlyInterest,
            'cantidad_cuotas': draft.installmentCount,
            'estado': saleStatus,
            'fecha_actualizacion': updatedAt.toIso8601String(),
            'last_modified_local': updatedAt.toIso8601String(),
            'sync_status': DatabaseSchema.syncStatusPendingUpdate,
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
              'last_modified_local': updatedAt.toIso8601String(),
              'sync_status': DatabaseSchema.syncStatusPendingUpdate,
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
                ..['id_local'] = null
                ..['id_remote'] = null
                ..['last_modified_local'] = updatedAt.toIso8601String()
                ..['deleted_at'] = null
                ..['sync_status'] = DatabaseSchema.syncStatusPendingCreate
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
            'last_modified_local': updatedAt.toIso8601String(),
            'deleted_at': null,
            'sync_status': DatabaseSchema.syncStatusPendingCreate,
          });
        }

        if (isChangingLot) {
          batch.update(
            DatabaseSchema.lotsTable,
            {
              'estado': 'disponible',
              'fecha_actualizacion': updatedAt.toIso8601String(),
              'last_modified_local': updatedAt.toIso8601String(),
              'sync_status': DatabaseSchema.syncStatusPendingUpdate,
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
            'last_modified_local': updatedAt.toIso8601String(),
            'sync_status': DatabaseSchema.syncStatusPendingUpdate,
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
          triggerProcessing: false,
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
    if (_useBackendMode) {
      await _deleteSaleInBackend(saleId);
      return;
    }

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
      final blockingPaymentRows = paymentRows
          .where(_shouldBlockSaleDeletion)
          .toList(growable: false);
      if (blockingPaymentRows.isNotEmpty) {
        throw StateError(
          'No se puede eliminar una venta que ya tiene pagos registrados.',
        );
      }
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
      final nextSaleVersion = ((saleRow['version'] as int?) ?? 1) + 1;
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
          'last_modified_local': deletedAt,
          'sync_status': DatabaseSchema.syncStatusPendingDelete,
        },
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );

      await txn.rawUpdate(
        'UPDATE ${DatabaseSchema.installmentsTable} '
        'SET version = COALESCE(version, 1) + 1, '
        'deleted_at = ?, fecha_actualizacion = ?, last_modified_local = ?, sync_status = ? '
        'WHERE venta_id = ? AND deleted_at IS NULL',
        [
          deletedAt,
          deletedAt,
          deletedAt,
          DatabaseSchema.syncStatusPendingDelete,
          saleId,
        ],
      );

      await txn.update(
        DatabaseSchema.salesTable,
        {
          'version': nextSaleVersion,
          'estado': 'cancelada',
          'deleted_at': deletedAt,
          'fecha_actualizacion': deletedAt,
          'last_modified_local': deletedAt,
          'sync_status': DatabaseSchema.syncStatusPendingDelete,
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
            'last_modified_local': deletedAt,
            'sync_status': DatabaseSchema.syncStatusPendingUpdate,
          },
          where: 'id = ?',
          whereArgs: [lotId],
        );
      }
    });

    await _syncQueueService.enqueueDeleteBatch(
      items: deleteQueue
          .map(
            (item) => (
              scope: item.scope,
              recordSyncId: item.syncId,
              payload: item.payload,
            ),
          )
          .toList(growable: false),
      triggerProcessing: false,
    );
    _log('DELETE SALE -> local saleId=$saleId queued for backend deletion');
    _log(
      'Guardado en local -> scope=sales operation=delete saleId=$saleId sync_status=${DatabaseSchema.syncStatusPendingDelete}',
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

  bool _shouldBlockSaleDeletion(Map<String, Object?> paymentRow) {
    final installmentId = paymentRow['cuota_id'] as int?;
    final paymentType = paymentRow['tipo_pago']?.toString().trim().toLowerCase();
    final isEditableInitialPayment = installmentId == null &&
        (paymentType == 'apartado' || paymentType == 'abono_inicial');
    return !isEditableInitialPayment;
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
      'updated_at': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPending,
    };
  }

  Future<List<SaleSummary>> _fetchAllFromBackend({
    String query = '',
    String? sellerRemoteId,
  }) async {
    final response = await _apiClient.get(
      '/sales',
      queryParameters: {
        'page': '1',
        'limit': '100',
        if (query.trim().isNotEmpty) 'search': query.trim(),
        if (sellerRemoteId != null && sellerRemoteId.isNotEmpty)
          'sellerId': sellerRemoteId,
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    final items = (payload['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => _saleSummaryFromBackend(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<SaleDetail?> _fetchDetailFromBackend(int saleId) async {
    final remoteId = _idRegistry.resolveRemoteId('sales', saleId);
    if (remoteId == null || remoteId.isEmpty) {
      return null;
    }
    final response = await _apiClient.get('/sales/$remoteId');
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    return _saleDetailFromBackend(payload);
  }

  Future<int> _createSaleInBackend(SaleDraft draft) async {
    final clientRemoteId = _idRegistry.resolveRemoteId(
      'clients',
      draft.clientId,
    );
    final productRemoteId = _idRegistry.resolveRemoteId(
      'products',
      draft.lotId,
    );
    final sellerRemoteId = _idRegistry.resolveRemoteId(
      'sellers',
      draft.sellerId,
    );
    if (clientRemoteId == null || productRemoteId == null) {
      throw const BackendApiException(
        'No se pudieron resolver las referencias remotas de cliente y solar.',
      );
    }

    final response = await _apiClient.post(
      '/sales',
      body: {
        'clientId': clientRemoteId,
        'productId': productRemoteId,
        if (sellerRemoteId != null && sellerRemoteId.isNotEmpty)
          'sellerId': sellerRemoteId,
        'contractNumber': null,
        'saleDate': draft.saleDate.toIso8601String(),
        'principalAmount': draft.salePrice,
        'downPayment': draft.requiredInitialPayment,
        'interestRate': draft.monthlyInterest,
        'termMonths': draft.installmentCount,
        'status': _mapSaleStatusToBackend(draft.status),
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    final remoteSaleId = payload['id']?.toString().trim() ?? '';
    if (remoteSaleId.isEmpty) {
      throw const BackendApiException(
        'La API no devolvió el id de la venta creada.',
      );
    }
    return _idRegistry.register('sales', remoteSaleId);
  }

  Future<void> _updateSaleInBackend(int saleId, SaleDraft draft) async {
    final remoteSaleId = _idRegistry.resolveRemoteId('sales', saleId);
    final clientRemoteId = _idRegistry.resolveRemoteId(
      'clients',
      draft.clientId,
    );
    final productRemoteId = _idRegistry.resolveRemoteId(
      'products',
      draft.lotId,
    );
    final sellerRemoteId = _idRegistry.resolveRemoteId(
      'sellers',
      draft.sellerId,
    );
    if (remoteSaleId == null ||
        clientRemoteId == null ||
        productRemoteId == null) {
      throw const BackendApiException(
        'No se pudieron resolver las referencias remotas de la venta.',
      );
    }

    await _apiClient.patch(
      '/sales/$remoteSaleId',
      body: {
        'clientId': clientRemoteId,
        'productId': productRemoteId,
        if (sellerRemoteId != null && sellerRemoteId.isNotEmpty)
          'sellerId': sellerRemoteId,
        'saleDate': draft.saleDate.toIso8601String(),
        'principalAmount': draft.salePrice,
        'downPayment': draft.requiredInitialPayment,
        'interestRate': draft.monthlyInterest,
        'termMonths': draft.installmentCount,
        'status': _mapSaleStatusToBackend(draft.status),
      },
    );
  }

  Future<void> _deleteSaleInBackend(int saleId) async {
    final remoteSaleId = _idRegistry.resolveRemoteId('sales', saleId);
    if (remoteSaleId == null || remoteSaleId.isEmpty) {
      throw const BackendApiException(
        'No se pudo identificar la venta remota para eliminarla.',
      );
    }
    await _apiClient.delete('/sales/$remoteSaleId');
  }

  SaleSummary _saleSummaryFromBackend(Map<String, dynamic> item) {
    final remoteSaleId = item['id']?.toString().trim() ?? '';
    final localSaleId = _idRegistry.register('sales', remoteSaleId);
    final client = _asMap(item['client']);
    final product = _asMap(item['product']);
    if (client != null) {
      final clientId = client['id']?.toString().trim() ?? '';
      if (clientId.isNotEmpty) {
        _idRegistry.register('clients', clientId);
      }
    }
    if (product != null) {
      final productId = product['id']?.toString().trim() ?? '';
      if (productId.isNotEmpty) {
        _idRegistry.register('products', productId);
      }
    }
    final downPayment = _toDouble(item['downPayment']);
    final paidAmount = _toDouble(item['paidAmount']);
    return SaleSummary(
      id: localSaleId,
      syncStatus: item['syncStatus']?.toString() ?? 'synced',
      clientName: _clientName(client),
      clientDocumentId: client?['documentId']?.toString() ?? '',
      lotDisplayCode: _lotDisplayCode(product),
      saleDate:
          DateTime.tryParse(item['saleDate']?.toString() ?? '') ??
          DateTime.now(),
      salePrice: _toDouble(item['principalAmount']),
      downPaymentAmount: downPayment,
      requiredInitialPayment: downPayment,
      paidInitialPayment: paidAmount,
      pendingInitialPayment: math.max(0, downPayment - paidAmount),
      minimumReserveAmount: null,
      initialPaymentDeadline: null,
      financedBalance: _toDouble(item['financedAmount']),
      pendingBalance: _toDouble(item['outstandingBalance']),
      monthlyInterest: _toDouble(item['interestRate']),
      installmentCount: _toInt(item['termMonths']),
      status: _mapSaleStatusFromBackend(item['status']?.toString() ?? 'active'),
      generatedInstallments:
          (item['installments'] as List?)?.length ?? _toInt(item['termMonths']),
    );
  }

  SaleDetail _saleDetailFromBackend(Map<String, dynamic> item) {
    final remoteSaleId = item['id']?.toString().trim() ?? '';
    final localSaleId = _idRegistry.register('sales', remoteSaleId);
    final client = _asMap(item['client']);
    final product = _asMap(item['product']);
    final seller = _asMap(item['seller']);
    final user = _asMap(item['user']);
    final installments = ((item['installments'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (installment) => _installmentFromBackend(
            installment.map((key, value) => MapEntry(key.toString(), value)),
            saleLocalId: localSaleId,
          ),
        )
        .toList(growable: false);
    final downPayment = _toDouble(item['downPayment']);
    final paidAmount = _toDouble(item['paidAmount']);
    return SaleDetail(
      sale: Sale(
        id: localSaleId,
        clientId: _registerNestedId('clients', client),
        lotId: _registerNestedId('products', product),
        userId: _registerNestedId('users', user),
        sellerId: _registerNestedId('sellers', seller),
        saleDate:
            DateTime.tryParse(item['saleDate']?.toString() ?? '') ??
            DateTime.now(),
        salePrice: _toDouble(item['principalAmount']),
        downPaymentPercentage: 0,
        downPaymentAmount: downPayment,
        requiredInitialPayment: downPayment,
        paidInitialPayment: paidAmount,
        pendingInitialPayment: math.max(0, downPayment - paidAmount),
        minimumReserveAmount: null,
        initialPaymentDeadline: null,
        activationDate: null,
        financedBalance: _toDouble(item['financedAmount']),
        pendingBalance: _toDouble(item['outstandingBalance']),
        monthlyInterest: _toDouble(item['interestRate']),
        installmentCount: _toInt(item['termMonths']),
        status: _mapSaleStatusFromBackend(
          item['status']?.toString() ?? 'active',
        ),
        createdAt:
            DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(item['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      ),
      clientName: _clientName(client),
      clientDocumentId: client?['documentId']?.toString() ?? '',
      lotDisplayCode: _lotDisplayCode(product),
      lotArea: _lotArea(product),
      lotPricePerSquareMeter: _lotUnitPrice(product),
      userName:
          user?['fullName']?.toString() ?? user?['username']?.toString() ?? '',
      initialPaymentMethod: _mapPaymentMethod(
        ((item['payments'] as List?) ?? const []).isEmpty
            ? null
            : ((item['payments'] as List).first as Map)['method']?.toString(),
      ),
      sellerName: seller?['name']?.toString(),
      sellerDocumentId: seller?['documentId']?.toString(),
      sellerPhone: seller?['phone']?.toString(),
      installments: installments,
    );
  }

  Installment _installmentFromBackend(
    Map<String, dynamic> item, {
    required int saleLocalId,
  }) {
    final remoteInstallmentId = item['id']?.toString().trim() ?? '';
    final localInstallmentId = _idRegistry.register(
      'installments',
      remoteInstallmentId,
    );
    final paidAmount = _toDouble(item['paidAmount']);
    return Installment(
      id: localInstallmentId,
      saleId: saleLocalId,
      installmentNumber: _toInt(item['installmentNumber']),
      dueDate:
          DateTime.tryParse(item['dueDate']?.toString() ?? '') ??
          DateTime.now(),
      openingBalance: 0,
      principalAmount: _toDouble(item['principalAmount']),
      interestAmount: _toDouble(item['interestAmount']),
      totalAmount: _toDouble(item['amount']),
      paidAmount: paidAmount,
      paidPrincipalAmount: paidAmount,
      paidInterestAmount: 0,
      endingBalance: 0,
      status: item['status']?.toString() ?? 'pending',
      createdAt:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(item['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return null;
  }

  int _registerNestedId(String namespace, Map<String, dynamic>? payload) {
    final remoteId = payload?['id']?.toString().trim() ?? '';
    if (remoteId.isEmpty) {
      return 0;
    }
    return _idRegistry.register(namespace, remoteId);
  }

  String _clientName(Map<String, dynamic>? client) {
    if (client == null) {
      return '';
    }
    final firstName = client['firstName']?.toString().trim() ?? '';
    final lastName = client['lastName']?.toString().trim() ?? '';
    return [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ').trim();
  }

  String _lotDisplayCode(Map<String, dynamic>? product) {
    if (product == null) {
      return '';
    }
    final syncPayload = _asMap(product['syncPayload']);
    final blockNumber = syncPayload?['block_number']?.toString() ?? '';
    final lotNumber = syncPayload?['lot_number']?.toString() ?? '';
    if (blockNumber.isNotEmpty || lotNumber.isNotEmpty) {
      return 'M$blockNumber-S$lotNumber';
    }
    return product['code']?.toString() ?? product['name']?.toString() ?? '';
  }

  double _lotArea(Map<String, dynamic>? product) {
    final syncPayload = product == null ? null : _asMap(product['syncPayload']);
    return _toDouble(syncPayload?['area']);
  }

  double _lotUnitPrice(Map<String, dynamic>? product) {
    final syncPayload = product == null ? null : _asMap(product['syncPayload']);
    final fromPayload = _toDouble(syncPayload?['price_per_square_meter']);
    if (fromPayload > 0) {
      return fromPayload;
    }
    final area = _lotArea(product);
    if (area <= 0) {
      return 0;
    }
    return _toDouble(product?['price']) / area;
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _mapSaleStatusFromBackend(String status) {
    switch (status.trim().toLowerCase()) {
      case 'completed':
        return 'pagada';
      case 'cancelled':
        return 'cancelada';
      case 'draft':
        return 'apartado';
      case 'overdue':
        return 'atrasada';
      case 'active':
      default:
        return 'activa';
    }
  }

  String _mapSaleStatusToBackend(String status) {
    switch (status.trim().toLowerCase()) {
      case 'pagada':
        return 'completed';
      case 'cancelada':
        return 'cancelled';
      case 'apartado':
      case 'inicial_incompleto':
        return 'draft';
      default:
        return 'active';
    }
  }

  String _mapPaymentMethod(String? method) {
    switch (method?.trim().toLowerCase()) {
      case 'transfer':
        return 'transferencia';
      case 'card':
        return 'tarjeta';
      case 'check':
        return 'cheque';
      case 'cash':
      default:
        return 'efectivo';
    }
  }
}
