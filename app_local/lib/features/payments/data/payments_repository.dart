import 'dart:async';
import 'dart:developer' as developer;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/cloud_foundation/list_snapshot_store.dart';
import '../../../core/config/app_flags.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/utils/sync_id_generator.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../../installments/domain/installment.dart';
import '../../sales/domain/sale_calculator.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/payment_draft.dart';
import '../domain/payment_history_item.dart';
import '../domain/client_pagare_report.dart';
import '../domain/payment_sale_context.dart';
import '../domain/payment_sale_option.dart';
import '../domain/payment_work_queue.dart';

class PaymentsRepository {
  PaymentsRepository({
    AppDatabase? appDatabase,
    SettingsRepository? settingsRepository,
    SyncQueueService? syncQueueService,
    SystemConfigService? systemConfigService,
    BackendApiClient? apiClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _settingsRepository = settingsRepository ?? SettingsRepository(),
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _systemConfigService =
           systemConfigService ?? SystemConfigService.instance,
       _apiClient = apiClient ?? BackendApiClient();

  final AppDatabase _appDatabase;
  final SettingsRepository _settingsRepository;
  final SyncQueueService _syncQueueService;
  final SystemConfigService _systemConfigService;
  final BackendApiClient _apiClient;
  final BackendEntityIdRegistry _idRegistry = BackendEntityIdRegistry.instance;
  late final ListSnapshotStore _queueSnapshot = ListSnapshotStore(
    _appDatabase,
    entity: 'payments-work-queue',
  );

  bool get _shouldRunBackgroundSync =>
      identical(_appDatabase, AppDatabase.instance);
  bool get _useBackendMode => cloudCutoverMode.usesAuthoritativeBusinessWrites;
  bool get usesBackendMode => _useBackendMode;

  void _log(String message) {
    developer.log(message, name: 'SistemaSolares.PaymentsSync');
  }

  Future<T> _runWithDatabaseRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DatabaseException catch (error) {
      if (!_isDatabaseClosedError(error)) {
        rethrow;
      }

      await _appDatabase.close();
      return action();
    }
  }

  Future<List<PaymentSaleOption>> fetchActiveSales() async {
    if (_useBackendMode) {
      final sales = await _fetchOwnerItems('/owner/sales');
      return sales
          .map(_paymentSaleOptionFromBackend)
          .where(
            (sale) =>
                const {
                  'apartado',
                  'inicial_incompleto',
                  'activa',
                }.contains(sale.status) &&
                (sale.pendingInitialPayment > 0.009 ||
                    sale.pendingBalance > 0.009),
          )
          .toList(growable: false);
    }

    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT
        v.id,
        v.cliente_id,
        v.solar_id,
        v.saldo_pendiente,
        v.monto_inicial_requerido,
        v.monto_inicial_pagado,
        v.monto_inicial_pendiente,
        v.monto_apartado_pagado,
        v.estado,
        c.nombre AS cliente_nombre,
        c.cedula AS cliente_cedula,
        c.telefono AS cliente_telefono,
        s.manzana_numero,
        s.solar_numero
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE v.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND s.deleted_at IS NULL
        AND v.estado IN ('apartado', 'inicial_incompleto', 'activa')
        AND (v.monto_inicial_pendiente > 0 OR v.saldo_pendiente > 0)
      ORDER BY c.nombre COLLATE NOCASE ASC, v.id ASC
    ''');

    return rows.map(PaymentSaleOption.fromMap).toList();
  }

  Future<String> fetchDefaultPaymentMethod() async {
    final settings = await _settingsRepository.fetchByKeysWithDefaults({
      SettingsRepository.defaultPaymentMethodKey: 'efectivo',
    });
    return settings[SettingsRepository.defaultPaymentMethodKey]?.value ??
        'efectivo';
  }

  Future<PaymentWorkQueue?> fetchWorkQueue({
    String state = 'collectible',
    String search = '',
    int page = 1,
    int pageSize = 100,
  }) async {
    if (!_useBackendMode) {
      return null;
    }

    final response = await _apiClient.get(
      '/owner/payments/work-queue',
      queryParameters: {
        'state': state,
        'page': '$page',
        'pageSize': '$pageSize',
        if (search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    final data = payload['data'];
    final dataMap = data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : payload;
    // Snapshot cache-first de la vista por defecto de la cola de pagos.
    if (state == 'collectible' && search.trim().isEmpty && page == 1) {
      await _queueSnapshot.writeJson(dataMap);
    }
    return _workQueueFromDataMap(dataMap, page: page, pageSize: pageSize);
  }

  PaymentWorkQueue _workQueueFromDataMap(
    Map<String, dynamic> dataMap, {
    required int page,
    required int pageSize,
  }) {
    final entries = <PaymentWorkQueueEntry>[];
    for (final raw in (dataMap['items'] as List?) ?? const []) {
      if (raw is! Map) {
        continue;
      }
      final item = raw.map((key, value) => MapEntry(key.toString(), value));
      final rawSale = item['sale'];
      final rawInstallment = item['installment'];
      if (rawSale is! Map || rawInstallment is! Map) {
        continue;
      }
      final sale = rawSale.map((key, value) => MapEntry(key.toString(), value));
      final saleOption = _paymentSaleOptionFromBackend(sale);
      final installment = _installmentFromBackend(
        rawInstallment.map((key, value) => MapEntry(key.toString(), value)),
        saleId: saleOption.saleId,
      );
      entries.add(
        PaymentWorkQueueEntry(sale: saleOption, installment: installment),
      );
    }

    final counts = dataMap['counts'] is Map
        ? (dataMap['counts'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    return PaymentWorkQueue(
      entries: entries,
      total: _toInt(dataMap['total']),
      page: _toInt(dataMap['page']) == 0 ? page : _toInt(dataMap['page']),
      pageSize: _toInt(dataMap['pageSize']) == 0
          ? pageSize
          : _toInt(dataMap['pageSize']),
      counts: PaymentWorkQueueCounts(
        overdue: _toInt(counts['overdue']),
        dueToday: _toInt(counts['dueToday']),
        pending: _toInt(counts['pending']),
        partial: _toInt(counts['partial']),
      ),
    );
  }

  /// Ultima cola de pagos valida guardada en cache local (best-effort: null si
  /// no existe o falla la lectura).
  Future<PaymentWorkQueue?> fetchCachedWorkQueue() async {
    if (!_useBackendMode) {
      return null;
    }
    final payload = await _queueSnapshot.readJson();
    if (payload is! Map) {
      return null;
    }
    try {
      final map = payload.map((key, value) => MapEntry(key.toString(), value));
      return _workQueueFromDataMap(
        map,
        page: _toInt(map['page']) == 0 ? 1 : _toInt(map['page']),
        pageSize: _toInt(map['pageSize']) == 0 ? 100 : _toInt(map['pageSize']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<PaymentSaleContext?> fetchSaleContext(int saleId) async {
    if (_useBackendMode) {
      return _fetchSaleContextFromBackend(saleId);
    }

    return _runWithDatabaseRetry(() async {
      final db = await _appDatabase.database;
      final saleRows = await db.rawQuery(
        '''
      SELECT
        v.id,
        v.cliente_id,
        v.solar_id,
        v.saldo_pendiente,
        v.estado,
        v.fecha_venta,
        v.interes_mensual,
        v.cantidad_cuotas,
        v.monto_inicial_requerido,
        v.monto_inicial_pagado,
        v.monto_inicial_pendiente,
        v.monto_apartado_pagado,
        c.nombre AS cliente_nombre,
        c.cedula AS cliente_cedula,
        s.manzana_numero,
        s.solar_numero
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE v.id = ?
        AND v.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND s.deleted_at IS NULL
      LIMIT 1
    ''',
        [saleId],
      );

      if (saleRows.isEmpty) {
        return null;
      }

      final installmentRows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL AND estado <> ?',
        whereArgs: [saleId, 'ajustada'],
        orderBy: 'numero_cuota ASC',
      );
      final installments = installmentRows.map(Installment.fromMap).toList();

      final historyRows = await db.rawQuery(
        '''
      SELECT
        p.*,
        q.numero_cuota
      FROM ${DatabaseSchema.paymentsTable} p
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
      WHERE p.venta_id = ? AND p.deleted_at IS NULL
      ORDER BY p.fecha_pago DESC, p.id DESC
    ''',
        [saleId],
      );

      return PaymentSaleContext(
        sale: PaymentSaleOption.fromMap(saleRows.first),
        monthlyInterest: _toDouble(saleRows.first['interes_mensual']),
        installments: installments,
        history: historyRows.map(PaymentHistoryItem.fromMap).toList(),
        actionableInstallment: _findActionableInstallment(
          installments,
          DateTime.now(),
        ),
      );
    });
  }

  Future<ClientPagareReport> fetchClientPagareReport(int clientId) async {
    final db = await _appDatabase.database;

    final clientRows = await db.query(
      DatabaseSchema.clientsTable,
      columns: ['id', 'nombre', 'cedula'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (clientRows.isEmpty) {
      throw StateError('No se encontro el cliente seleccionado.');
    }

    final client = clientRows.first;
    final historyRows = await db.rawQuery(
      '''
      SELECT
        p.id,
        p.venta_id,
        p.fecha_pago,
        p.monto_pagado,
        p.metodo_pago,
        p.tipo_pago,
        p.referencia,
        q.numero_cuota,
        s.manzana_numero,
        s.solar_numero
      FROM ${DatabaseSchema.paymentsTable} p
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = p.venta_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE p.cliente_id = ?
        AND p.deleted_at IS NULL
        AND v.deleted_at IS NULL
      ORDER BY p.fecha_pago DESC, p.id DESC
    ''',
      [clientId],
    );

    return ClientPagareReport(
      clientId: clientId,
      clientName: client['nombre'] as String? ?? 'Cliente',
      clientDocumentId: client['cedula'] as String? ?? 'N/A',
      items: historyRows.map(ClientPagareItem.fromMap).toList(growable: false),
    );
  }

  Future<void> registerPayment(PaymentDraft draft) async {
    _systemConfigService.ensureWritable();
    if (_useBackendMode) {
      await _registerPaymentInBackend(draft);
      await _queueSnapshot.clear();
      return;
    }

    // Reconcile installment states from actual pagos before applying this
    // payment. This guards against sync race conditions where conflict recovery
    // temporarily resets installment monto_pagado to server state (which may
    // not yet reflect local payments), causing duplicate payment targets.
    await _reconcileSaleInstallmentsBeforePayment(draft.saleId);

    final deletedInstallmentPayloads = <Map<String, Object?>>[];

    await _runWithDatabaseRetry(() async {
      final db = await _appDatabase.database;
      await db.transaction<void>((txn) async {
        await _registerPaymentInTransaction(
          txn,
          draft,
          deletedInstallmentPayloads,
        );
      });
    });
    _log(
      'Guardado en local -> scope=payments operation=create saleId=${draft.saleId} sync_status=${DatabaseSchema.syncStatusPending}',
    );

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

    _scheduleBackgroundSync('register-payment:${draft.saleId}', const [
      'products',
      'sales',
      'installments',
      'payments',
    ]);
    // Garantizar sync inmediato tras registrar pago para todos los usuarios
    _scheduleExplicitSync('register-payment:${draft.saleId}', const [
      'products',
      'sales',
      'installments',
      'payments',
    ]);
  }

  Future<void> deletePayment(
    int paymentId, {
    String? reason,
    String? adminAuthorizationId,
  }) async {
    _systemConfigService.ensureWritable();
    if (_useBackendMode) {
      await _annulPaymentInBackend(
        paymentId,
        reason: reason,
        adminAuthorizationId: adminAuthorizationId,
      );
      await _queueSnapshot.clear();
      return;
    }
    final deleteQueue =
        <({String scope, String syncId, Map<String, Object?> payload})>[];

    await _runWithDatabaseRetry(() async {
      final db = await _appDatabase.database;
      await db.transaction<void>((txn) async {
        final paymentRows = await txn.query(
          DatabaseSchema.paymentsTable,
          where: 'id = ?',
          whereArgs: [paymentId],
          limit: 1,
        );
        if (paymentRows.isEmpty) {
          throw StateError('El pago seleccionado ya no existe.');
        }

        final paymentRow = paymentRows.first;
        final paymentSyncId = (paymentRow['sync_id'] as String?)?.trim();
        if (paymentSyncId != null && paymentSyncId.isNotEmpty) {
          deleteQueue.add((
            scope: 'payments',
            syncId: paymentSyncId,
            payload: _buildDeletePayload(
              paymentRow,
              updatedAtField: 'fecha_actualizacion',
            ),
          ));
        }
        final saleId = _toInt(paymentRow['venta_id']);
        final latestRows = await txn.query(
          DatabaseSchema.paymentsTable,
          columns: ['id'],
          where: 'venta_id = ? AND deleted_at IS NULL',
          whereArgs: [saleId],
          orderBy: 'fecha_pago DESC, id DESC',
          limit: 1,
        );
        if (latestRows.isEmpty || _toInt(latestRows.first['id']) != paymentId) {
          throw StateError(
            'Por seguridad solo se puede anular el ultimo pago registrado de la venta.',
          );
        }

        final saleRows = await txn.query(
          DatabaseSchema.salesTable,
          where: 'id = ?',
          whereArgs: [saleId],
          limit: 1,
        );
        if (saleRows.isEmpty) {
          throw StateError('La venta asociada al pago ya no existe.');
        }

        final saleRow = saleRows.first;
        final paymentType = paymentRow['tipo_pago'] as String? ?? 'cuota';
        final paymentAmount = _roundCurrency(
          _toDouble(paymentRow['monto_pagado']),
        );
        final currentInitialPaid = _roundCurrency(
          _toDouble(saleRow['monto_inicial_pagado']),
        );
        final requiredInitial = _roundCurrency(
          _toDouble(saleRow['monto_inicial_requerido']),
        );
        final salePrice = _roundCurrency(_toDouble(saleRow['precio_venta']));
        final financedBalance = _roundCurrency(
          _toDouble(saleRow['saldo_financiado']),
        );
        final monthlyInterest = _toDouble(saleRow['interes_mensual']);
        final installmentCount = _toInt(saleRow['cantidad_cuotas']);
        final lotId = _toInt(saleRow['solar_id']);
        final installmentId = paymentRow['cuota_id'] as int?;
        final paymentDate = DateTime.tryParse(
          paymentRow['fecha_pago'] as String? ?? '',
        );
        final saleDate = DateTime.tryParse(
          saleRow['fecha_venta'] as String? ?? '',
        );
        final existingActivationDate = saleRow['fecha_activacion'] as String?;
        final updatedAt = DateTime.now().toIso8601String();

        await txn.update(
          DatabaseSchema.paymentsTable,
          {
            'deleted_at': updatedAt,
            'fecha_actualizacion': updatedAt,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [paymentId],
        );

        if (paymentType == 'apartado' || paymentType == 'abono_inicial') {
          final updatedInitialPaid = _roundCurrency(
            (currentInitialPaid - paymentAmount).clamp(0, salePrice),
          );
          final updatedInitialPending =
              SaleCalculator.calculatePendingInitialPayment(
                requiredInitialPayment: requiredInitial,
                initialPaymentPaid: updatedInitialPaid,
              );
          final updatedFinancedBalance =
              SaleCalculator.calculateFinancedBalance(
                salePrice: salePrice,
                downPaymentAmount: updatedInitialPaid,
              );
          final newSaleStatus = _resolveUpfrontSaleStatus(
            initialRequiredAmount: requiredInitial,
            initialPaidAmount: updatedInitialPaid,
            financedBalance: updatedFinancedBalance,
          );

          final deletedInstallmentRows = await txn.query(
            DatabaseSchema.installmentsTable,
            where: 'venta_id = ? AND deleted_at IS NULL',
            whereArgs: [saleId],
          );
          for (final row in deletedInstallmentRows) {
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

          await txn.update(
            DatabaseSchema.installmentsTable,
            {
              'deleted_at': updatedAt,
              'fecha_actualizacion': updatedAt,
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'venta_id = ? AND deleted_at IS NULL',
            whereArgs: [saleId],
          );

          await txn.update(
            DatabaseSchema.salesTable,
            {
              'inicial_monto': updatedInitialPaid,
              'monto_inicial_pagado': updatedInitialPaid,
              'monto_inicial_pendiente': updatedInitialPending,
              'saldo_financiado': updatedFinancedBalance,
              'estado': newSaleStatus,
              'fecha_activacion':
                  newSaleStatus == 'activa' || newSaleStatus == 'pagada'
                  ? (existingActivationDate ??
                        (saleDate ?? paymentDate ?? DateTime.now())
                            .toIso8601String())
                  : null,
              'saldo_pendiente': _resolveSalePendingBalance(
                saleStatus: newSaleStatus,
                financedBalance: updatedFinancedBalance,
                monthlyInterest: monthlyInterest,
                installmentCount: installmentCount,
              ),
              'fecha_actualizacion': updatedAt,
            },
            where: 'id = ?',
            whereArgs: [saleId],
          );

          if (newSaleStatus == 'activa' && saleDate != null) {
            final generatedInstallments =
                SaleCalculator.buildInstallmentSchedule(
                  saleId: saleId,
                  saleDate: saleDate,
                  financedBalance: updatedFinancedBalance,
                  monthlyInterest: monthlyInterest,
                  installmentCount: installmentCount,
                  createdAt: DateTime.parse(updatedAt),
                  statusAsOf: DateTime.parse(updatedAt),
                );
            final batch = txn.batch();
            for (final installment in generatedInstallments) {
              batch.insert(
                DatabaseSchema.installmentsTable,
                installment.toMap()
                  ..['sync_id'] = _newSyncId('installment')
                  ..['deleted_at'] = null
                  ..['sync_status'] = DatabaseSchema.syncStatusPending
                  ..remove('id'),
              );
            }
            await batch.commit(noResult: true);
          }

          await txn.update(
            DatabaseSchema.lotsTable,
            {
              'estado': newSaleStatus == 'activa' || newSaleStatus == 'pagada'
                  ? 'vendido'
                  : 'reservado',
              'fecha_actualizacion': updatedAt,
            },
            where: 'id = ?',
            whereArgs: [lotId],
          );
          return;
        }

        if (paymentType == 'cuota') {
          if (installmentId == null) {
            throw StateError(
              'El pago de cuota no tiene una cuota asociada valida.',
            );
          }

          final installmentRows = await txn.query(
            DatabaseSchema.installmentsTable,
            where: 'id = ?',
            whereArgs: [installmentId],
            limit: 1,
          );
          if (installmentRows.isEmpty) {
            throw StateError('La cuota asociada al pago ya no existe.');
          }

          final installment = Installment.fromMap(installmentRows.first);
          final principalReversal =
              paymentAmount > installment.paidPrincipalAmount
              ? installment.paidPrincipalAmount
              : paymentAmount;
          final interestReversal = _roundCurrency(
            paymentAmount - principalReversal,
          );
          final updatedPaidAmount = _roundCurrency(
            (installment.paidAmount - paymentAmount).clamp(
              0,
              installment.totalAmount,
            ),
          );
          final updatedPrincipalPaid = _roundCurrency(
            (installment.paidPrincipalAmount - principalReversal).clamp(
              0,
              installment.principalAmount,
            ),
          );
          final updatedInterestPaid = _roundCurrency(
            (installment.paidInterestAmount - interestReversal).clamp(
              0,
              installment.interestAmount,
            ),
          );
          final updatedStatus = updatedPaidAmount <= 0.009
              ? SaleCalculator.resolveInstallmentStatus(
                  dueDate: installment.dueDate,
                  paidAmount: updatedPaidAmount,
                  totalAmount: installment.totalAmount,
                  asOf: paymentDate ?? DateTime.parse(updatedAt),
                )
              : updatedPaidAmount >= installment.totalAmount - 0.009
              ? 'pagada'
              : 'parcial';

          await txn.update(
            DatabaseSchema.installmentsTable,
            {
              'monto_pagado': updatedPaidAmount,
              'capital_pagado': updatedPrincipalPaid,
              'interes_pagado': updatedInterestPaid,
              'estado': updatedStatus,
              'fecha_actualizacion': updatedAt,
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'id = ?',
            whereArgs: [installmentId],
          );

          final newPendingBalance = await _loadOutstandingContractBalance(
            txn,
            saleId,
          );

          await txn.update(
            DatabaseSchema.salesTable,
            {
              'saldo_pendiente': newPendingBalance,
              'estado': newPendingBalance <= 0.009 ? 'pagada' : 'activa',
              'fecha_actualizacion': updatedAt,
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'id = ?',
            whereArgs: [saleId],
          );
          return;
        }

        if (paymentType == 'abono_capital') {
          final installmentRows = await txn.query(
            DatabaseSchema.installmentsTable,
            where: 'venta_id = ? AND deleted_at IS NULL',
            whereArgs: [saleId],
            orderBy: 'numero_cuota ASC',
          );
          final installments = installmentRows
              .map(Installment.fromMap)
              .toList();
          final outstandingPrincipal = _calculateOutstandingPrincipal(
            installments,
          );
          final lastPaidInstallmentNumber = installments
              .where(
                (item) => item.paidAmount > 0.009 || item.status == 'pagada',
              )
              .fold<int>(0, (current, item) {
                return item.installmentNumber > current
                    ? item.installmentNumber
                    : current;
              });

          await _recalculateFutureInstallments(
            txn: txn,
            installments: installments,
            paymentDate: paymentDate ?? DateTime.now(),
            currentInstallmentNumber: lastPaidInstallmentNumber,
            monthlyInterest: monthlyInterest,
            fixedInstallmentAmount: _resolveContractFixedInstallmentAmount(
              financedBalance: financedBalance,
              monthlyInterest: monthlyInterest,
              installmentCount: installmentCount,
            ),
            remainingPrincipalBalance: _roundCurrency(
              (outstandingPrincipal + paymentAmount).clamp(0, financedBalance),
            ),
            updatedAt: updatedAt,
            shouldRecalculate: true,
          );

          final newPendingBalance = await _loadOutstandingContractBalance(
            txn,
            saleId,
          );

          await txn.update(
            DatabaseSchema.salesTable,
            {
              'saldo_pendiente': newPendingBalance,
              'estado': newPendingBalance <= 0.009 ? 'pagada' : 'activa',
              'fecha_actualizacion': updatedAt,
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'id = ?',
            whereArgs: [saleId],
          );
          return;
        }

        throw StateError('El tipo de pago no admite anulacion automatica.');
      });
    });

    for (final item in deleteQueue) {
      await _syncQueueService.enqueueDelete(
        scope: item.scope,
        recordSyncId: item.syncId,
        payload: item.payload,
      );
    }
    _log(
      'REFUND PAYMENT -> local paymentId=$paymentId queued for backend delete',
    );
    _log(
      'Guardado en local -> scope=payments operation=delete paymentId=$paymentId sync_status=${DatabaseSchema.syncStatusPending}',
    );
    _scheduleBackgroundSync('refund-payment:$paymentId', const [
      'products',
      'sales',
      'installments',
      'payments',
    ]);
    // Garantizar sync inmediato tras reembolsar pago para todos los usuarios
    _scheduleExplicitSync('refund-payment:$paymentId', const [
      'products',
      'sales',
      'installments',
      'payments',
    ]);
  }

  Future<void> _registerPaymentInTransaction(
    DatabaseExecutor txn,
    PaymentDraft draft,
    List<Map<String, Object?>> deletedInstallmentPayloads,
  ) async {
    final paymentReference = _generatePaymentReference(draft);
    final saleRows = await txn.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [draft.saleId],
      limit: 1,
    );
    if (saleRows.isEmpty) {
      throw StateError('La venta seleccionada no existe.');
    }

    final saleRow = saleRows.first;
    final saleStatus = saleRow['estado'] as String? ?? 'apartado';
    final clientId = saleRow['cliente_id'] as int? ?? 0;
    final registeredByUserId =
        draft.registeredByUserId ?? (saleRow['usuario_id'] as int?);
    final monthlyInterest = _toDouble(saleRow['interes_mensual']);
    final pendingBalance = _toDouble(saleRow['saldo_pendiente']);
    final financedBalance = _toDouble(saleRow['saldo_financiado']);
    final salePrice = _toDouble(saleRow['precio_venta']);
    final requiredInitial = _toDouble(saleRow['monto_inicial_requerido']);
    final paidInitial = _toDouble(saleRow['monto_inicial_pagado']);
    final pendingInitial = _toDouble(saleRow['monto_inicial_pendiente']);
    final saleDate =
        DateTime.tryParse(saleRow['fecha_venta'] as String? ?? '') ??
        draft.paymentDate;
    final installmentCount = _toInt(saleRow['cantidad_cuotas']);
    final fixedInstallmentAmount = _resolveContractFixedInstallmentAmount(
      financedBalance: _toDouble(saleRow['saldo_financiado']),
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );

    if (pendingInitial <= 0.009 && pendingBalance <= 0.009) {
      throw StateError('La venta seleccionada ya no tiene saldo pendiente.');
    }
    if (draft.amountPaid <= 0) {
      throw StateError('El monto pagado debe ser mayor que cero.');
    }

    final timestamp = draft.paymentDate.toIso8601String();
    // Block capital payment when conditions prevent it.
    if (draft.paymentTypeOverride == 'abono_capital') {
      if (pendingInitial > 0.009) {
        throw StateError(
          'No puedes aplicar pago a capital porque este cliente tiene un inicial pendiente. Primero debes completar el pago inicial.',
        );
      }

      final overdueCheck = await txn.rawQuery(
        '''
        SELECT id
        FROM ${DatabaseSchema.installmentsTable}
        WHERE venta_id = ?
          AND deleted_at IS NULL
          AND estado NOT IN ('pagada', 'ajustada', 'cancelada')
          AND (monto_cuota - monto_pagado) > 0.009
          AND date(fecha_vencimiento) < date(?)
        LIMIT 1
      ''',
        [draft.saleId, timestamp],
      );

      if (overdueCheck.isNotEmpty) {
        throw StateError(
          'No puedes aplicar pago a capital porque este cliente tiene cuotas vencidas. Primero debes saldar las cuotas atrasadas.',
        );
      }
    }

    var remainingAmount = _roundCurrency(draft.amountPaid);

    if (saleStatus == 'apartado' || saleStatus == 'inicial_incompleto') {
      final saleAmountRemaining = _roundCurrency(
        (salePrice - paidInitial).clamp(0, double.infinity),
      );
      final initialPaymentApplied = remainingAmount > saleAmountRemaining
          ? saleAmountRemaining
          : remainingAmount;

      if (initialPaymentApplied > 0) {
        final updatedInitialPaid = _roundCurrency(
          paidInitial + initialPaymentApplied,
        );
        final updatedInitialPending =
            SaleCalculator.calculatePendingInitialPayment(
              requiredInitialPayment: requiredInitial,
              initialPaymentPaid: updatedInitialPaid,
            );
        final updatedFinancedBalance = SaleCalculator.calculateFinancedBalance(
          salePrice: salePrice,
          downPaymentAmount: updatedInitialPaid,
        );
        final newStatus = _resolveUpfrontSaleStatus(
          initialRequiredAmount: requiredInitial,
          initialPaidAmount: updatedInitialPaid,
          financedBalance: updatedFinancedBalance,
        );

        await txn.insert(DatabaseSchema.paymentsTable, {
          'sync_id': _newSyncId('payment'),
          'venta_id': draft.saleId,
          'cliente_id': clientId,
          'usuario_id': registeredByUserId,
          'cuota_id': null,
          'fecha_pago': timestamp,
          'monto_pagado': initialPaymentApplied,
          'metodo_pago': draft.paymentMethod,
          'tipo_pago': paidInitial <= 0.009 ? 'apartado' : 'abono_inicial',
          'referencia': paymentReference,
          'ano_a_pagar': draft.yearToPay,
          'fecha_creacion': timestamp,
          'fecha_actualizacion': timestamp,
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusPending,
        });

        await txn.update(
          DatabaseSchema.salesTable,
          {
            'inicial_monto': updatedInitialPaid,
            'monto_inicial_pagado': updatedInitialPaid,
            'monto_inicial_pendiente': updatedInitialPending,
            'saldo_financiado': updatedFinancedBalance,
            'saldo_pendiente': _resolveSalePendingBalance(
              saleStatus: newStatus,
              financedBalance: updatedFinancedBalance,
              monthlyInterest: monthlyInterest,
              installmentCount: installmentCount,
            ),
            'estado': newStatus,
            'fecha_activacion': newStatus == 'activa' || newStatus == 'pagada'
                ? timestamp
                : null,
            'fecha_actualizacion': timestamp,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [draft.saleId],
        );

        await txn.update(
          DatabaseSchema.lotsTable,
          {
            'estado': newStatus == 'activa' || newStatus == 'pagada'
                ? 'vendido'
                : 'reservado',
            'fecha_actualizacion': timestamp,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [saleRow['solar_id']],
        );

        final previousInstallmentRows = await txn.query(
          DatabaseSchema.installmentsTable,
          where: 'venta_id = ? AND deleted_at IS NULL',
          whereArgs: [draft.saleId],
        );
        deletedInstallmentPayloads.addAll(
          previousInstallmentRows.map((row) => _buildDeletePayload(row)),
        );

        await txn.update(
          DatabaseSchema.installmentsTable,
          {
            'deleted_at': timestamp,
            'fecha_actualizacion': timestamp,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'venta_id = ? AND deleted_at IS NULL',
          whereArgs: [draft.saleId],
        );

        if (newStatus == 'activa') {
          final generatedInstallments = SaleCalculator.buildInstallmentSchedule(
            saleId: draft.saleId,
            saleDate: saleDate,
            financedBalance: updatedFinancedBalance,
            monthlyInterest: monthlyInterest,
            installmentCount: installmentCount,
            createdAt: draft.paymentDate,
            statusAsOf: draft.paymentDate,
          );
          final batch = txn.batch();
          for (final installment in generatedInstallments) {
            batch.insert(
              DatabaseSchema.installmentsTable,
              installment.toMap()
                ..['sync_id'] = _newSyncId('installment')
                ..['deleted_at'] = null
                ..['sync_status'] = DatabaseSchema.syncStatusPending
                ..remove('id'),
            );
          }
          await batch.commit(noResult: true);
        }

        remainingAmount = _roundCurrency(
          remainingAmount - initialPaymentApplied,
        );
      }

      if (remainingAmount > 0.009) {
        throw StateError('El pago excede el monto restante de la venta.');
      }

      return;
    }

    if (saleStatus != 'activa' && saleStatus != 'pagada') {
      throw StateError(
        'La venta seleccionada no admite pagos en su estado actual.',
      );
    }
    if (pendingBalance <= 0.009) {
      throw StateError(
        'La venta seleccionada ya no tiene saldo pendiente del plan.',
      );
    }

    final installmentRows = await txn.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ? AND deleted_at IS NULL',
      whereArgs: [draft.saleId],
      orderBy: 'numero_cuota ASC',
    );
    final installments = installmentRows.map(Installment.fromMap).toList();
    final outstandingPrincipal = _calculateOutstandingPrincipal(installments);

    var totalPrincipalReduction = 0.0;
    var currentInstallmentNumber = 0;

    // Resolve which installments to process based on the user's payment type choice.
    final installmentsToProcess = _resolveInstallmentsToProcess(
      installments: installments,
      paymentDate: draft.paymentDate,
      paymentTypeOverride: draft.paymentTypeOverride,
      targetInstallmentId: draft.targetInstallmentId,
      targetInstallmentNumber: draft.targetInstallmentNumber,
    );
    final requiresInstallmentImpact =
        draft.paymentTypeOverride == 'cuota' ||
        draft.paymentTypeOverride == 'cuota_vencida' ||
        draft.paymentTypeOverride == 'todas_cuotas_vencidas';
    final openInstallmentIds = installments
        .where((installment) {
          if (_isClosedStatus(installment.status)) {
            return false;
          }
          return installment.remainingAmount > 0.009;
        })
        .map((installment) => installment.id)
        .whereType<int>()
        .toSet();
    final selectedInstallmentIds = installmentsToProcess
        .map((installment) => installment.id)
        .whereType<int>()
        .toSet();
    var installmentAppliedTotal = 0.0;

    for (final installment in installmentsToProcess) {
      if (remainingAmount <= 0.009) break;
      currentInstallmentNumber = installment.installmentNumber;
      final installmentOutcome = _applyToInstallment(
        installment: installment,
        amount: remainingAmount,
      );

      if (installmentOutcome.appliedAmount > 0) {
        await txn.update(
          DatabaseSchema.installmentsTable,
          {
            'monto_pagado': installmentOutcome.newPaidAmount,
            'capital_pagado': installmentOutcome.newPrincipalPaid,
            'interes_pagado': installmentOutcome.newInterestPaid,
            'estado': installmentOutcome.newStatus,
            'fecha_actualizacion': timestamp,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [installment.id],
        );

        await txn.insert(DatabaseSchema.paymentsTable, {
          'sync_id': _newSyncId('payment'),
          'venta_id': draft.saleId,
          'cliente_id': clientId,
          'usuario_id': registeredByUserId,
          'cuota_id': installment.id,
          'fecha_pago': timestamp,
          'monto_pagado': installmentOutcome.appliedAmount,
          'metodo_pago': draft.paymentMethod,
          'tipo_pago': 'cuota',
          'referencia': paymentReference,
          'ano_a_pagar': draft.yearToPay,
          'fecha_creacion': timestamp,
          'fecha_actualizacion': timestamp,
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusPending,
        });

        remainingAmount = installmentOutcome.remainingAmount;
        installmentAppliedTotal = _roundCurrency(
          installmentAppliedTotal + installmentOutcome.appliedAmount,
        );
        totalPrincipalReduction += installmentOutcome.principalPaidNow;
      }
    }

    if (requiresInstallmentImpact && installmentAppliedTotal <= 0.009) {
      throw StateError(
        'El pago no impactó ninguna cuota elegible. Ajuste la cuota o el monto e intente nuevamente.',
      );
    }

    var capitalPrepayment = 0.0;
    if (remainingAmount > 0) {
      final maxCapitalPayment = outstandingPrincipal - totalPrincipalReduction;
      if (maxCapitalPayment <= 0) {
        throw StateError('El pago excede el saldo pendiente disponible.');
      }

      capitalPrepayment = remainingAmount > maxCapitalPayment
          ? maxCapitalPayment
          : remainingAmount;

      await txn.insert(DatabaseSchema.paymentsTable, {
        'sync_id': _newSyncId('payment'),
        'venta_id': draft.saleId,
        'cliente_id': clientId,
        'usuario_id': registeredByUserId,
        'cuota_id': null,
        'fecha_pago': timestamp,
        'monto_pagado': capitalPrepayment,
        'metodo_pago': draft.paymentMethod,
        'tipo_pago': 'abono_capital',
        'referencia': paymentReference,
        'ano_a_pagar': draft.yearToPay,
        'fecha_creacion': timestamp,
        'fecha_actualizacion': timestamp,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPending,
      });

      remainingAmount = _roundCurrency(remainingAmount - capitalPrepayment);
      totalPrincipalReduction += capitalPrepayment;
    }

    if (remainingAmount > 0.009) {
      throw StateError('El pago excede el saldo pendiente de la venta.');
    }

    final settlesDisplayedBalance =
        draft.paymentTypeOverride == 'abono_capital' &&
        draft.amountPaid >= pendingBalance - 0.009;
    final settlesAllInstallments =
        requiresInstallmentImpact &&
        remainingAmount <= 0.009 &&
        openInstallmentIds.isNotEmpty &&
        selectedInstallmentIds.containsAll(openInstallmentIds);

    await _recalculateFutureInstallments(
      txn: txn,
      installments: installments,
      paymentDate: draft.paymentDate,
      currentInstallmentNumber: currentInstallmentNumber,
      monthlyInterest: monthlyInterest,
      fixedInstallmentAmount: fixedInstallmentAmount,
      remainingPrincipalBalance: settlesDisplayedBalance
          ? 0
          : _roundCurrency(
              (outstandingPrincipal - totalPrincipalReduction).clamp(
                0,
                financedBalance,
              ),
            ),
      updatedAt: timestamp,
      shouldRecalculate: capitalPrepayment > 0 || settlesDisplayedBalance,
    );

    final hasOpenInstallments = await _hasOpenInstallmentBalance(
      txn,
      draft.saleId,
    );
    if (settlesAllInstallments) {
      await txn.rawUpdate(
        '''
        UPDATE ${DatabaseSchema.installmentsTable}
        SET monto_pagado = monto_cuota,
            capital_pagado = capital_cuota,
            interes_pagado = interes_cuota,
            estado = ?,
            fecha_actualizacion = ?,
            sync_status = ?
        WHERE venta_id = ?
          AND deleted_at IS NULL
          AND estado NOT IN ('pagada', 'ajustada', 'cancelada')
        ''',
        ['pagada', timestamp, DatabaseSchema.syncStatusPending, draft.saleId],
      );
    }
    final newPendingBalance =
        (settlesDisplayedBalance ||
            settlesAllInstallments ||
            !hasOpenInstallments)
        ? 0.0
        : await _loadOutstandingContractBalance(txn, draft.saleId);

    await txn.update(
      DatabaseSchema.salesTable,
      {
        'saldo_pendiente': newPendingBalance,
        'estado': newPendingBalance <= 0.009 ? 'pagada' : 'activa',
        'fecha_actualizacion': timestamp,
        'sync_status': DatabaseSchema.syncStatusPending,
      },
      where: 'id = ?',
      whereArgs: [draft.saleId],
    );
  }

  Installment? _findActionableInstallment(
    List<Installment> installments,
    DateTime paymentDate,
  ) {
    // Prioridad financiera: la cuota exigible es la MÁS ANTIGUA sin pagar cuyo
    // vencimiento ya ocurrió (<= hoy), sin importar el orden en que llegó la
    // lista desde el backend.
    final candidates =
        installments.where((installment) {
          if (_isClosedStatus(installment.status)) {
            return false;
          }
          if (installment.remainingAmount <= 0.009) {
            return false;
          }
          return !installment.dueDate.isAfter(paymentDate);
        }).toList()..sort((left, right) {
          final byDate = left.dueDate.compareTo(right.dueDate);
          if (byDate != 0) {
            return byDate;
          }
          return left.installmentNumber.compareTo(right.installmentNumber);
        });
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Returns the list of installments to process for a given payment type.
  /// - 'abono_capital'        → [] (skip all, apply to capital)
  /// - 'todas_cuotas_vencidas' → all overdue installments in order
  /// - everything else        → [first actionable installment] or []
  List<Installment> _resolveInstallmentsToProcess({
    required List<Installment> installments,
    required DateTime paymentDate,
    required String? paymentTypeOverride,
    required int? targetInstallmentId,
    required int? targetInstallmentNumber,
  }) {
    if (paymentTypeOverride == 'abono_capital') return const [];

    bool isEligible(Installment installment) {
      if (_isClosedStatus(installment.status)) {
        return false;
      }
      return installment.remainingAmount > 0.009;
    }

    if (targetInstallmentId != null) {
      final target = installments.where((i) {
        if (i.id != targetInstallmentId) return false;
        return isEligible(i);
      }).toList();
      if (target.isNotEmpty) {
        return target;
      }
    }

    if (targetInstallmentNumber != null) {
      final byNumber = installments.where((i) {
        if (i.installmentNumber != targetInstallmentNumber) return false;
        return isEligible(i);
      }).toList();
      if (byNumber.isNotEmpty) {
        return byNumber;
      }
    }

    if (paymentTypeOverride == 'todas_cuotas_vencidas') {
      return installments.where((i) {
        if (_isClosedStatus(i.status)) return false;
        if (i.remainingAmount <= 0.009) return false;
        return !i.dueDate.isAfter(paymentDate);
      }).toList();
    }
    final actionable = _findActionableInstallment(installments, paymentDate);
    return actionable == null ? const [] : [actionable];
  }

  _InstallmentPaymentOutcome _applyToInstallment({
    required Installment installment,
    required double amount,
  }) {
    final installmentRemaining = installment.remainingAmount;
    final appliedAmount = amount > installmentRemaining
        ? installmentRemaining
        : amount;
    final interestRemaining =
        installment.interestAmount - installment.paidInterestAmount;
    final interestPaidNow = appliedAmount > interestRemaining
        ? interestRemaining
        : appliedAmount;
    final principalPaidNow = _roundCurrency(appliedAmount - interestPaidNow);
    final newPaidAmount = _roundCurrency(
      installment.paidAmount + appliedAmount,
    );
    final newInterestPaid = _roundCurrency(
      installment.paidInterestAmount + interestPaidNow,
    );
    final newPrincipalPaid = _roundCurrency(
      installment.paidPrincipalAmount + principalPaidNow,
    );

    return _InstallmentPaymentOutcome(
      appliedAmount: _roundCurrency(appliedAmount),
      principalPaidNow: principalPaidNow,
      newPaidAmount: newPaidAmount,
      newInterestPaid: newInterestPaid,
      newPrincipalPaid: newPrincipalPaid,
      remainingAmount: _roundCurrency(amount - appliedAmount),
      newStatus: newPaidAmount >= installment.totalAmount - 0.009
          ? 'pagada'
          : newPaidAmount > 0
          ? 'parcial'
          : installment.status == 'vencida'
          ? 'vencida'
          : 'pendiente',
    );
  }

  void _scheduleBackgroundSync(String operationLabel, List<String> scopes) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    unawaited(_runBackgroundSync(operationLabel, scopes));
  }

  void _scheduleExplicitSync(String operationLabel, List<String> scopes) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    // Intenta sincronizar inmediatamente sin esperar (fire-and-forget)
    // para garantizar que cambios se suban a la nube SIEMPRE, no solo en background
    unawaited(_runBackgroundSync(operationLabel, scopes));
  }

  Future<void> _runBackgroundSync(
    String operationLabel,
    List<String> scopes,
  ) async {
    _log('Intentando sync -> scope=payments operation=$operationLabel');
    try {
      await Future.wait(
        scopes.map((scope) => _syncQueueService.refreshScope(scope)),
      );
      final processed = await _syncQueueService.processQueue(
        includeDeferred: true,
      );
      _log(
        'Sync exitoso -> scope=payments operation=$operationLabel processed=$processed',
      );
    } catch (error, stackTrace) {
      _log(
        'Sync fallo -> scope=payments operation=$operationLabel error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _recalculateFutureInstallments({
    required DatabaseExecutor txn,
    required List<Installment> installments,
    required DateTime paymentDate,
    required int currentInstallmentNumber,
    required double monthlyInterest,
    required double fixedInstallmentAmount,
    required double remainingPrincipalBalance,
    required String updatedAt,
    required bool shouldRecalculate,
  }) async {
    if (!shouldRecalculate) {
      return;
    }

    final futureInstallments = installments.where((installment) {
      if (_isClosedStatus(installment.status)) {
        return false;
      }
      if (remainingPrincipalBalance <= 0) {
        return true;
      }
      if (currentInstallmentNumber > 0) {
        return installment.installmentNumber > currentInstallmentNumber;
      }
      return installment.dueDate.isAfter(paymentDate);
    }).toList();

    if (futureInstallments.isEmpty) {
      return;
    }

    if (remainingPrincipalBalance <= 0) {
      for (final installment in futureInstallments) {
        await txn.update(
          DatabaseSchema.installmentsTable,
          {
            'saldo_inicial': 0,
            'capital_cuota': 0,
            'interes_cuota': 0,
            'monto_cuota': 0,
            'monto_pagado': 0,
            'capital_pagado': 0,
            'interes_pagado': 0,
            'saldo_final': 0,
            'estado': 'ajustada',
            'fecha_actualizacion': updatedAt,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [installment.id],
        );
      }
      return;
    }

    final schedule = _rebuildSchedule(
      startingPrincipal: remainingPrincipalBalance,
      monthlyInterest: monthlyInterest,
      fixedInstallmentAmount: fixedInstallmentAmount,
      futureInstallments: futureInstallments,
      updatedAt: DateTime.parse(updatedAt),
    );

    for (var index = 0; index < futureInstallments.length; index++) {
      final current = futureInstallments[index];
      if (index < schedule.length) {
        final recalculated = schedule[index];
        await txn.update(
          DatabaseSchema.installmentsTable,
          {
            'saldo_inicial': recalculated.openingBalance,
            'capital_cuota': recalculated.principalAmount,
            'interes_cuota': recalculated.interestAmount,
            'monto_cuota': recalculated.totalAmount,
            'monto_pagado': 0,
            'capital_pagado': 0,
            'interes_pagado': 0,
            'saldo_final': recalculated.endingBalance,
            'estado': 'pendiente',
            'fecha_actualizacion': updatedAt,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [current.id],
        );
        continue;
      }

      await txn.update(
        DatabaseSchema.installmentsTable,
        {
          'saldo_inicial': 0,
          'capital_cuota': 0,
          'interes_cuota': 0,
          'monto_cuota': 0,
          'monto_pagado': 0,
          'capital_pagado': 0,
          'interes_pagado': 0,
          'saldo_final': 0,
          'estado': 'ajustada',
          'fecha_actualizacion': updatedAt,
          'sync_status': DatabaseSchema.syncStatusPending,
        },
        where: 'id = ?',
        whereArgs: [current.id],
      );
    }
  }

  List<Installment> _rebuildSchedule({
    required double startingPrincipal,
    required double monthlyInterest,
    required double fixedInstallmentAmount,
    required List<Installment> futureInstallments,
    required DateTime updatedAt,
  }) {
    if (futureInstallments.isEmpty) {
      return const [];
    }

    return SaleCalculator.buildInstallmentScheduleForDueDatesWithFixedPayment(
      saleId: futureInstallments.first.saleId,
      dueDates: futureInstallments.map((item) => item.dueDate).toList(),
      financedBalance: startingPrincipal,
      monthlyInterest: monthlyInterest,
      fixedPaymentAmount: fixedInstallmentAmount,
      createdAt: futureInstallments.first.createdAt,
      updatedAt: updatedAt,
      startingInstallmentNumber: futureInstallments.first.installmentNumber,
      installmentIds: futureInstallments.map((item) => item.id).toList(),
    );
  }

  double _resolveContractFixedInstallmentAmount({
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    return SaleCalculator.calculateEstimatedInstallmentAmount(
      financedBalance: financedBalance,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    );
  }

  bool _isClosedStatus(String status) {
    return status == 'pagada' || status == 'ajustada' || status == 'cancelada';
  }

  bool _isDatabaseClosedError(DatabaseException error) {
    return error.toString().toLowerCase().contains('database_closed');
  }

  double _resolveSalePendingBalance({
    required String saleStatus,
    required double financedBalance,
    required double monthlyInterest,
    required int installmentCount,
  }) {
    return _roundCurrency(financedBalance);
  }

  double _calculateOutstandingPrincipal(List<Installment> installments) {
    return _roundCurrency(
      installments
          .where(
            (item) => item.status != 'ajustada' && item.status != 'cancelada',
          )
          .fold<double>(0, (sum, item) {
            return sum +
                (item.principalAmount - item.paidPrincipalAmount).clamp(
                  0,
                  item.principalAmount,
                );
          }),
    );
  }

  Future<double> _loadOutstandingContractBalance(
    DatabaseExecutor txn,
    int saleId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT
        COALESCE(SUM(MAX(capital_cuota - capital_pagado, 0)), 0) AS total_pendiente
      FROM ${DatabaseSchema.installmentsTable}
      WHERE venta_id = ?
        AND deleted_at IS NULL
        AND estado <> ?
      ''',
      [saleId, 'ajustada'],
    );

    if (rows.isEmpty) {
      return 0;
    }

    return _roundCurrency(_toDouble(rows.first['total_pendiente']));
  }

  Future<bool> _hasOpenInstallmentBalance(
    DatabaseExecutor txn,
    int saleId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT id
      FROM ${DatabaseSchema.installmentsTable}
      WHERE venta_id = ?
        AND deleted_at IS NULL
        AND estado NOT IN ('pagada', 'ajustada', 'cancelada')
        AND (capital_cuota - capital_pagado) > 0.009
      LIMIT 1
      ''',
      [saleId],
    );

    return rows.isNotEmpty;
  }

  /// Reconciles installment states for [saleId] from the actual pagos table
  /// before applying a new payment. Guards against sync race conditions where
  /// conflict recovery may have temporarily reset installment monto_pagado.
  Future<void> _reconcileSaleInstallmentsBeforePayment(int saleId) async {
    final db = await _appDatabase.database;
    final repairAsOf = DateTime.now();
    final nowIso = repairAsOf.toIso8601String();

    await db.transaction<void>((txn) async {
      final installmentRows = await txn.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL AND estado <> ?',
        whereArgs: [saleId, 'ajustada'],
      );

      var anyFixed = false;
      for (final row in installmentRows) {
        if ((row['estado'] as String? ?? '') == 'cancelada') continue;
        final installmentId = _toInt(row['id']);
        final totalAmount = _toDouble(row['monto_cuota']);

        final paymentSumRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(monto_pagado), 0) AS paid_total
          FROM ${DatabaseSchema.paymentsTable}
          WHERE cuota_id = ? AND deleted_at IS NULL
          ''',
          [installmentId],
        );

        final rawPaid = _roundCurrency(
          _toDouble(paymentSumRows.first['paid_total']),
        );
        // Cap to totalAmount to prevent over-payment display from duplicate pagos.
        final paidAmount = rawPaid > totalAmount
            ? _roundCurrency(totalAmount)
            : rawPaid;
        final currentMontoPagado = _toDouble(row['monto_pagado']);

        if ((currentMontoPagado - paidAmount).abs() <= 0.009) continue;

        // State is inconsistent — restore from pagos.
        final interestAmount = _toDouble(row['interes_cuota']);
        final principalAmount = _toDouble(row['capital_cuota']);
        final interestPaid = _roundCurrency(
          paidAmount > interestAmount ? interestAmount : paidAmount,
        );
        final principalPaid = _roundCurrency(
          (paidAmount - interestPaid).clamp(0, principalAmount),
        );
        final dueDate = DateTime.parse(row['fecha_vencimiento'] as String);
        final repairedStatus = SaleCalculator.resolveInstallmentStatus(
          totalAmount: totalAmount,
          paidAmount: paidAmount,
          dueDate: dueDate,
          asOf: repairAsOf,
        );

        await txn.update(
          DatabaseSchema.installmentsTable,
          {
            'monto_pagado': paidAmount,
            'capital_pagado': principalPaid,
            'interes_pagado': interestPaid,
            'estado': repairedStatus,
            'fecha_actualizacion': nowIso,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ?',
          whereArgs: [installmentId],
        );
        anyFixed = true;
      }

      if (anyFixed) {
        final newPendingBalance = await _loadOutstandingContractBalance(
          txn,
          saleId,
        );
        await txn.update(
          DatabaseSchema.salesTable,
          {
            'saldo_pendiente': newPendingBalance,
            'estado': newPendingBalance <= 0.009 ? 'pagada' : 'activa',
            'fecha_actualizacion': nowIso,
            'sync_status': DatabaseSchema.syncStatusPending,
          },
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [saleId],
        );
      }
    });
  }

  Future<PaymentRepairReport> repairExistingPaymentApplicationInconsistencies({
    DateTime? statusAsOf,
  }) async {
    final repairAsOf = statusAsOf ?? DateTime.now();
    var scannedInstallments = 0;
    var fixedInstallments = 0;
    final touchedSaleIds = <int>{};
    final nowIso = DateTime.now().toIso8601String();

    await _runWithDatabaseRetry(() async {
      final db = await _appDatabase.database;
      await db.transaction<void>((txn) async {
        final rows = await txn.query(
          DatabaseSchema.installmentsTable,
          where: 'deleted_at IS NULL AND estado <> ?',
          whereArgs: ['ajustada'],
          orderBy: 'venta_id ASC, numero_cuota ASC',
        );

        for (final row in rows) {
          scannedInstallments += 1;
          final installmentId = _toInt(row['id']);
          final saleId = _toInt(row['venta_id']);
          final totalAmount = _toDouble(row['monto_cuota']);
          final dueDate = DateTime.parse(row['fecha_vencimiento'] as String);

          final paymentRows = await txn.rawQuery(
            '''
            SELECT
              COALESCE(SUM(monto_pagado), 0) AS paid_total
            FROM ${DatabaseSchema.paymentsTable}
            WHERE cuota_id = ?
              AND deleted_at IS NULL
          ''',
            [installmentId],
          );

          final paidAmount = _roundCurrency(
            _toDouble(paymentRows.first['paid_total']),
          );
          final interestAmount = _toDouble(row['interes_cuota']);
          final principalAmount = _toDouble(row['capital_cuota']);
          final repairedInterestPaid = _roundCurrency(
            paidAmount > interestAmount ? interestAmount : paidAmount,
          );
          final repairedPrincipalPaid = _roundCurrency(
            (paidAmount - repairedInterestPaid).clamp(0, principalAmount),
          );
          final repairedStatus = SaleCalculator.resolveInstallmentStatus(
            totalAmount: totalAmount,
            paidAmount: paidAmount,
            dueDate: dueDate,
            asOf: repairAsOf,
          );

          final statusChanged =
              (row['estado'] as String? ?? '') != repairedStatus;
          final paidChanged =
              (_toDouble(row['monto_pagado']) - paidAmount).abs() > 0.009;
          final principalChanged =
              (_toDouble(row['capital_pagado']) - repairedPrincipalPaid).abs() >
              0.009;
          final interestChanged =
              (_toDouble(row['interes_pagado']) - repairedInterestPaid).abs() >
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
              'capital_pagado': repairedPrincipalPaid,
              'interes_pagado': repairedInterestPaid,
              'estado': repairedStatus,
              'fecha_actualizacion': nowIso,
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'id = ?',
            whereArgs: [installmentId],
          );
          fixedInstallments += 1;
          touchedSaleIds.add(saleId);
        }

        for (final saleId in touchedSaleIds) {
          final newPendingBalance = await _loadOutstandingContractBalance(
            txn,
            saleId,
          );
          await txn.update(
            DatabaseSchema.salesTable,
            {
              'saldo_pendiente': newPendingBalance,
              'estado': newPendingBalance <= 0.009 ? 'pagada' : 'activa',
              'fecha_actualizacion': nowIso,
              'sync_status': DatabaseSchema.syncStatusPending,
            },
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [saleId],
          );
        }
      });
    });

    return PaymentRepairReport(
      scannedInstallments: scannedInstallments,
      fixedInstallments: fixedInstallments,
      touchedSales: touchedSaleIds.length,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOwnerItems(String path) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    const pageSize = 200;
    while (true) {
      final response = await _apiClient.get(
        path,
        queryParameters: {'page': '$page', 'pageSize': '$pageSize'},
      );
      final payload = response is Map<String, dynamic>
          ? response
          : (response as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            );
      final data = payload['data'];
      final dataMap = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : payload;
      final items = (dataMap['items'] as List?) ?? const [];
      for (final item in items.whereType<Map>()) {
        all.add(item.map((key, value) => MapEntry(key.toString(), value)));
      }
      final total = int.tryParse('${dataMap['total'] ?? ''}') ?? all.length;
      if (items.isEmpty || all.length >= total || page >= 200) {
        break;
      }
      page++;
    }
    return all;
  }

  Future<PaymentSaleContext?> _fetchSaleContextFromBackend(int saleId) async {
    final saleRemoteId = _idRegistry.resolveRemoteId('sales', saleId);
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      return null;
    }

    // El contexto financiero de la venta (cuotas + pagos) es autoritativo y
    // viene del endpoint por-venta del backend (SIN el límite de 200 del
    // listado global y sin truncar cuotas por fecha de actualización).
    final response = await _apiClient.get(
      '/owner/sales/$saleRemoteId/payments-context',
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    final data = payload['data'];
    final dataMap = data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : payload;
    final rawSale = dataMap['sale'];
    if (rawSale is! Map) {
      return null;
    }
    final sale = rawSale.map((key, value) => MapEntry(key.toString(), value));

    final installments = <Installment>[];
    final numberByRemoteId = <String, int>{};
    final numberByRemoteSyncId = <String, int>{};
    for (final raw in (dataMap['installments'] as List?) ?? const []) {
      if (raw is! Map) {
        continue;
      }
      final installmentMap = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final remoteId = installmentMap['id']?.toString().trim() ?? '';
      final remoteSyncId = installmentMap['syncId']?.toString().trim() ?? '';
      final number = _toInt(installmentMap['installmentNumber']);
      if (remoteId.isNotEmpty) {
        numberByRemoteId[remoteId] = number;
      }
      if (remoteSyncId.isNotEmpty) {
        numberByRemoteSyncId[remoteSyncId] = number;
      }
      installments.add(_installmentFromBackend(installmentMap, saleId: saleId));
    }

    final history = <PaymentHistoryItem>[];
    for (final raw in (dataMap['payments'] as List?) ?? const []) {
      if (raw is! Map) {
        continue;
      }
      history.add(
        _paymentHistoryFromBackend(
          raw.map((key, value) => MapEntry(key.toString(), value)),
          saleId: saleId,
          installmentNumbersByRemoteId: numberByRemoteId,
          installmentNumbersByRemoteSyncId: numberByRemoteSyncId,
        ),
      );
    }

    final annulledHistory = <PaymentHistoryItem>[];
    for (final raw in (dataMap['annulledPayments'] as List?) ?? const []) {
      if (raw is! Map) {
        continue;
      }
      annulledHistory.add(
        _paymentHistoryFromBackend(
          raw.map((key, value) => MapEntry(key.toString(), value)),
          saleId: saleId,
          installmentNumbersByRemoteId: numberByRemoteId,
          installmentNumbersByRemoteSyncId: numberByRemoteSyncId,
        ),
      );
    }

    return PaymentSaleContext(
      sale: _paymentSaleOptionFromBackend(sale),
      monthlyInterest: _toDouble(sale['monthlyInterestRate']),
      installments: installments,
      history: history,
      annulledHistory: annulledHistory,
      actionableInstallment: _findActionableInstallment(
        installments,
        DateTime.now(),
      ),
    );
  }

  Future<void> _registerPaymentInBackend(PaymentDraft draft) async {
    final saleRemoteId = _idRegistry.resolveRemoteId('sales', draft.saleId);
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      throw const BackendApiException(
        'No se pudo identificar la venta remota para registrar el pago.',
      );
    }
    final installmentRemoteId = _idRegistry.resolveRemoteId(
      'installments',
      draft.targetInstallmentId,
    );
    final operationId =
        'desktop-payment-${draft.saleId}-${draft.paymentDate.microsecondsSinceEpoch}';
    await _apiClient.post(
      '/authoritative/payments',
      idempotencyKey: operationId,
      body: {
        'saleId': saleRemoteId,
        'paymentDate': draft.paymentDate.toIso8601String(),
        'amountPaid': draft.amountPaid,
        'paymentMethod': draft.paymentMethod,
        'paymentTypeOverride': draft.paymentTypeOverride,
        if (installmentRemoteId != null && installmentRemoteId.isNotEmpty)
          'targetInstallmentId': installmentRemoteId,
        'targetInstallmentNumber': draft.targetInstallmentNumber,
        'yearToPay': int.tryParse(draft.yearToPay ?? ''),
        'operationId': operationId,
      },
    );
  }

  Future<void> _annulPaymentInBackend(
    int paymentId, {
    String? reason,
    String? adminAuthorizationId,
  }) async {
    final paymentRemoteId = _idRegistry.resolveRemoteId('payments', paymentId);
    if (paymentRemoteId == null || paymentRemoteId.isEmpty) {
      throw const BackendApiException(
        'No se pudo identificar el pago remoto para anularlo.',
      );
    }
    final operationId =
        'desktop-payment-annul-$paymentId-${DateTime.now().microsecondsSinceEpoch}';
    final trimmedReason = (reason ?? '').trim();
    await _apiClient.post(
      '/authoritative/payments/$paymentRemoteId/annul',
      idempotencyKey: operationId,
      body: {
        'reason': trimmedReason.isEmpty
            ? 'Anulado desde desktop cloud-first.'
            : trimmedReason,
        if (adminAuthorizationId != null && adminAuthorizationId.isNotEmpty)
          'adminAuthorizationId': adminAuthorizationId,
        'operationId': operationId,
      },
    );
  }

  ///
  /// Solicita al backend una autorizacion administrativa de un solo uso para
  /// anular un pago. La contrasena viaja una sola vez y el backend la valida;
  /// el cliente nunca la almacena ni la registra.
  Future<String> authorizePaymentCancellation({
    required int paymentId,
    required String email,
    required String password,
  }) async {
    _systemConfigService.ensureWritable();
    final paymentRemoteId = _idRegistry.resolveRemoteId('payments', paymentId);
    if (paymentRemoteId == null || paymentRemoteId.isEmpty) {
      throw const BackendApiException(
        'No se pudo identificar el pago remoto para anularlo.',
      );
    }
    final response = await _apiClient.post(
      '/auth/authorize-action',
      body: {
        'action': 'payments.cancel',
        'resourceType': 'PAYMENT',
        'resourceId': paymentRemoteId,
        'email': email.trim(),
        'password': password,
      },
    );
    final data = response is Map ? response['data'] : null;
    final authorizationId = data is Map
        ? data['authorizationId']?.toString().trim()
        : null;
    if (authorizationId == null || authorizationId.isEmpty) {
      throw const BackendApiException(
        'No se pudo obtener la autorizacion del administrador.',
      );
    }
    return authorizationId;
  }

  PaymentSaleOption _paymentSaleOptionFromBackend(Map<String, dynamic> item) {
    final remoteSaleId = item['id']?.toString().trim() ?? '';
    final localSaleId = _idRegistry.register('sales', remoteSaleId);
    final clientSyncId = item['clientSyncId']?.toString().trim() ?? '';
    final localClientId = clientSyncId.isEmpty
        ? 0
        : _idRegistry.register('clients', clientSyncId);
    final status = _mapSaleStatusFromBackend(item['status']?.toString() ?? '');
    return PaymentSaleOption(
      saleId: localSaleId,
      clientId: localClientId,
      clientName: item['client']?.toString() ?? '',
      clientDocumentId: item['cedula']?.toString() ?? '',
      clientPhone: item['clientPhone']?.toString() ?? '',
      lotDisplayCode: item['lot']?.toString() ?? '',
      pendingBalance: _toDouble(item['balance']),
      requiredInitialPayment: _toDouble(item['initialRequiredAmount']),
      paidInitialPayment: _toDouble(item['initialPaid']),
      pendingInitialPayment: _toDouble(item['initialPendingAmount']),
      paidApartadoPayment: _toDouble(item['reservationPaidAmount']),
      status: status,
    );
  }

  Installment _installmentFromBackend(
    Map<String, dynamic> item, {
    required int saleId,
  }) {
    final remoteId = item['id']?.toString().trim() ?? '';
    final localId = _idRegistry.register('installments', remoteId);
    return Installment(
      id: localId,
      saleId: saleId,
      installmentNumber: _toInt(item['installmentNumber']),
      dueDate:
          DateTime.tryParse(item['dueDate']?.toString() ?? '') ??
          DateTime.now(),
      openingBalance: _toDouble(item['openingBalance']),
      principalAmount: _toDouble(item['principalAmount']),
      interestAmount: _toDouble(item['interestAmount']),
      totalAmount: _toDouble(item['totalAmount']),
      paidAmount: _toDouble(item['paidAmount']),
      paidPrincipalAmount: _toDouble(item['paidPrincipalAmount']),
      paidInterestAmount: _toDouble(item['paidInterestAmount']),
      endingBalance: _toDouble(item['endingBalance']),
      status: _mapInstallmentStatusFromBackend(
        item['status']?.toString() ?? '',
      ),
      createdAt:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(item['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  PaymentHistoryItem _paymentHistoryFromBackend(
    Map<String, dynamic> item, {
    required int saleId,
    Map<String, int>? installmentNumbersByRemoteId,
    Map<String, int>? installmentNumbersByRemoteSyncId,
  }) {
    final remoteId = item['id']?.toString().trim() ?? '';
    final localId = _idRegistry.register('payments', remoteId);
    final installmentRemoteId = item['installmentId']?.toString().trim() ?? '';
    final installmentRemoteSyncId =
        item['installmentSyncId']?.toString().trim() ?? '';
    final installmentNumber = _toInt(item['installmentNumber']) != 0
        ? _toInt(item['installmentNumber'])
        : (installmentNumbersByRemoteId?[installmentRemoteId] ??
              installmentNumbersByRemoteSyncId?[installmentRemoteSyncId]);
    return PaymentHistoryItem(
      id: localId,
      saleId: saleId,
      clientId: 0,
      installmentId: installmentRemoteId.isEmpty
          ? null
          : _idRegistry.register('installments', installmentRemoteId),
      paymentDate:
          DateTime.tryParse(item['paidAt']?.toString() ?? '') ?? DateTime.now(),
      amountPaid: _toDouble(item['amount']),
      paymentMethod: item['method']?.toString() ?? '',
      paymentType: item['paymentType']?.toString() ?? 'cuota',
      reference: item['reference']?.toString(),
      installmentNumber: installmentNumber,
      annulledAt: DateTime.tryParse(item['annulledAt']?.toString() ?? ''),
      annulledByName: item['annulledByName']?.toString(),
      annulmentReason: item['annulmentReason']?.toString(),
      authorizedByAdmin: item['authorizedByAdmin'] == true,
    );
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
      case 'apartado':
      case 'inicial_incompleto':
      case 'activa':
      case 'pagada':
      case 'cancelada':
        return status.trim().toLowerCase();
      case 'active':
      default:
        return 'activa';
    }
  }

  String _mapInstallmentStatusFromBackend(String status) {
    switch (status.trim().toLowerCase()) {
      case 'paid':
        return 'pagada';
      case 'cancelled':
        return 'cancelada';
      case 'adjusted':
        return 'ajustada';
      case 'overdue':
        return 'vencida';
      default:
        return status.trim().isEmpty
            ? 'pendiente'
            : status.trim().toLowerCase();
    }
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

  String _generatePaymentReference(PaymentDraft draft) {
    final date = draft.paymentDate;
    final timestamp = date.microsecondsSinceEpoch;
    return 'PAY-${draft.saleId}-$timestamp';
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  String _resolveUpfrontSaleStatus({
    required double initialRequiredAmount,
    required double initialPaidAmount,
    required double financedBalance,
  }) {
    if (financedBalance <= 0.009) {
      return 'pagada';
    }
    if (initialPaidAmount >= initialRequiredAmount - 0.009) {
      return 'activa';
    }
    if (initialPaidAmount <= 0.009) {
      return 'apartado';
    }
    return 'inicial_incompleto';
  }
}

class _InstallmentPaymentOutcome {
  const _InstallmentPaymentOutcome({
    required this.appliedAmount,
    required this.principalPaidNow,
    required this.newPaidAmount,
    required this.newInterestPaid,
    required this.newPrincipalPaid,
    required this.remainingAmount,
    required this.newStatus,
  });

  final double appliedAmount;
  final double principalPaidNow;
  final double newPaidAmount;
  final double newInterestPaid;
  final double newPrincipalPaid;
  final double remainingAmount;
  final String newStatus;
}

class PaymentRepairReport {
  const PaymentRepairReport({
    required this.scannedInstallments,
    required this.fixedInstallments,
    required this.touchedSales,
  });

  final int scannedInstallments;
  final int fixedInstallments;
  final int touchedSales;
}
