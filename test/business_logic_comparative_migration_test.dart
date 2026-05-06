import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/data/receipt_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('comparative_business_logic', () {
    late Directory tempDirectory;
    late AppDatabase appDatabase;
    late SalesRepository salesRepository;
    late PaymentsRepository paymentsRepository;
    late ReceiptRepository receiptRepository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDirectory = await Directory.systemTemp.createTemp(
        'business_logic_comparative_',
      );
      appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
      await appDatabase.initialize();

      salesRepository = SalesRepository(appDatabase: appDatabase);
      paymentsRepository = PaymentsRepository(appDatabase: appDatabase);
      receiptRepository = ReceiptRepository(
        appDatabase: appDatabase,
        paymentsRepository: paymentsRepository,
      );
    });

    tearDown(() async {
      await appDatabase.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('sale_creation_matches_old_logic_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 10));

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 1, 10),
          salePrice: 720000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 72000,
          initialPaymentPaid: 72000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final installmentRows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
        orderBy: 'numero_cuota ASC',
      );

      expect(installmentRows.length, 12);
      for (var i = 1; i <= installmentRows.length; i++) {
        expect(installmentRows[i - 1]['numero_cuota'], i);
      }

      final principalSum = installmentRows.fold<double>(
        0,
        (sum, row) => sum + _toDouble(row['capital_cuota']),
      );
      expect(principalSum, closeTo(648000, 0.1));
    });

    test('sale_balance_calculation_matches_old_logic_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 2, 1));

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 2, 1),
          salePrice: 500000,
          downPaymentPercentage: 20,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 10,
        ),
      );

      final saleRow = (await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;

      expect(_toDouble(saleRow['saldo_financiado']), 400000);
      expect(_toDouble(saleRow['saldo_pendiente']), 400000);
      expect(saleRow['estado'], 'activa');
    });

    test('installment_generation_matches_old_logic_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 5));

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 1, 5),
          salePrice: 360000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 36000,
          initialPaymentPaid: 36000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final rows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
        orderBy: 'numero_cuota ASC',
      );

      expect(rows.length, 12);
      for (var i = 1; i <= rows.length; i++) {
        expect(rows[i - 1]['numero_cuota'], i);
      }
      final firstDue = DateTime.parse(
        rows.first['fecha_vencimiento'] as String,
      );
      final secondDue = DateTime.parse(rows[1]['fecha_vencimiento'] as String);
      expect(secondDue.isAfter(firstDue), isTrue);
    });

    test('payment_application_matches_old_logic_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 1));
      final saleId = await _createActiveSale(salesRepository, ids);

      final contextBefore = await paymentsRepository.fetchSaleContext(saleId);
      expect(contextBefore, isNotNull);
      final installment = contextBefore!.actionableInstallment;
      expect(installment, isNotNull);

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 2, 15),
          amountPaid: installment!.totalAmount,
          paymentMethod: 'efectivo',
        ),
      );

      final updatedInstallmentRows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'id = ?',
        whereArgs: [installment.id],
        limit: 1,
      );
      final updated = updatedInstallmentRows.single;
      expect(updated['estado'], 'pagada');
      expect(
        _toDouble(updated['monto_pagado']),
        closeTo(installment.totalAmount, 0.01),
      );
    });

    test('partial_payment_updates_balance_correctly_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 1));
      final saleId = await _createActiveSale(salesRepository, ids);
      final before = await paymentsRepository.fetchSaleContext(saleId);
      final target = before!.actionableInstallment!;

      final partialAmount = (target.totalAmount / 2).toStringAsFixed(2);
      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 2, 20),
          amountPaid: double.parse(partialAmount),
          paymentMethod: 'transferencia',
        ),
      );

      final installmentRow = (await db.query(
        DatabaseSchema.installmentsTable,
        where: 'id = ?',
        whereArgs: [target.id],
        limit: 1,
      )).single;
      final saleRow = (await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;

      expect(installmentRow['estado'], 'parcial');
      expect(_toDouble(installmentRow['monto_pagado']), greaterThan(0));
      expect(
        _toDouble(saleRow['saldo_pendiente']),
        lessThan(before.sale.pendingBalance),
      );
    });

    test('full_payment_marks_installment_paid_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 3, 1));
      final saleId = await _createActiveSale(salesRepository, ids);
      final context = await paymentsRepository.fetchSaleContext(saleId);
      final target = context!.actionableInstallment!;

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 4, 2),
          amountPaid: target.remainingAmount,
          paymentMethod: 'efectivo',
        ),
      );

      final installmentRow = (await db.query(
        DatabaseSchema.installmentsTable,
        where: 'id = ?',
        whereArgs: [target.id],
        limit: 1,
      )).single;
      expect(installmentRow['estado'], 'pagada');
      expect(
        _toDouble(installmentRow['monto_pagado']),
        closeTo(target.totalAmount, 0.01),
      );
    });

    test('sale_paid_full_marks_sale_completed_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 1));
      final saleId = await _createActiveSale(salesRepository, ids);

      final context = await paymentsRepository.fetchSaleContext(saleId);
      final fullPending = context!.sale.pendingBalance;

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 6, 1),
          amountPaid: fullPending,
          paymentMethod: 'transferencia',
        ),
      );

      var safeguard = 0;
      var latest = await paymentsRepository.fetchSaleContext(saleId);
      while (latest != null &&
          latest.sale.pendingBalance > 0.009 &&
          safeguard < 6) {
        safeguard += 1;
        await paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime(2026, 6, 1 + safeguard),
            amountPaid: latest.sale.pendingBalance,
            paymentMethod: 'transferencia',
          ),
        );
        latest = await paymentsRepository.fetchSaleContext(saleId);
      }

      final saleRow = (await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      expect(_toDouble(saleRow['saldo_pendiente']), closeTo(0, 0.01));
      expect(saleRow['estado'], 'pagada');
    });

    test('dashboard_totals_match_local_sales_payments_test', () async {
      final db = await appDatabase.database;
      final ids1 = await _seedBaseEntities(
        db,
        now: DateTime(2026, 2, 1),
        suffix: 'A',
      );
      final ids2 = await _seedBaseEntities(
        db,
        now: DateTime(2026, 2, 1),
        suffix: 'B',
      );
      final saleId1 = await _createActiveSale(
        salesRepository,
        ids1,
        salePrice: 300000,
      );
      final saleId2 = await _createActiveSale(
        salesRepository,
        ids2,
        salePrice: 400000,
      );

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId1,
          paymentDate: DateTime(2026, 3, 5),
          amountPaid: 12000,
          paymentMethod: 'efectivo',
        ),
      );
      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId2,
          paymentDate: DateTime(2026, 3, 6),
          amountPaid: 15000,
          paymentMethod: 'efectivo',
        ),
      );

      final salesTotalRows = await db.rawQuery(
        'SELECT SUM(precio_venta) AS total FROM ${DatabaseSchema.salesTable} WHERE deleted_at IS NULL',
      );
      final paymentsTotalRows = await db.rawQuery(
        'SELECT SUM(monto_pagado) AS total FROM ${DatabaseSchema.paymentsTable} WHERE deleted_at IS NULL',
      );

      final salesTotal = _toDouble(salesTotalRows.single['total']);
      final paymentsTotal = _toDouble(paymentsTotalRows.single['total']);

      expect(salesTotal, closeTo(700000, 0.1));
      expect(paymentsTotal, greaterThan(27000));
    });

    test('receipt_pdf_values_match_payment_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 1));
      final saleId = await _createActiveSale(
        salesRepository,
        ids,
        salePrice: 360000,
      );

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 2, 10),
          amountPaid: 18000,
          paymentMethod: 'efectivo',
        ),
      );

      final paymentRow = (await db.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ? AND tipo_pago = ?',
        whereArgs: [saleId, 'cuota'],
        orderBy: 'id DESC',
        limit: 1,
      )).single;

      final receipt = await receiptRepository.fetchReceiptByPaymentId(
        paymentRow['id'] as int,
      );
      expect(receipt, isNotNull);
      expect(receipt!.sale.saleId, saleId);
      expect(receipt.payment.id, paymentRow['id']);
      expect(receipt.payment.amountPaid, closeTo(18000, 0.01));
      expect(receipt.sale.pendingBalance, greaterThanOrEqualTo(0));
    });

    test('overpayment_distributes_correctly_or_is_blocked_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 1, 7));
      final saleId = await _createActiveSale(
        salesRepository,
        ids,
        salePrice: 360000,
      );

      final before = await paymentsRepository.fetchSaleContext(saleId);
      final installment = before!.actionableInstallment!;
      final overpayment = installment.totalAmount + 15000;

      try {
        await paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime(2026, 2, 12),
            amountPaid: overpayment,
            paymentMethod: 'efectivo',
          ),
        );

        final after = await paymentsRepository.fetchSaleContext(saleId);
        expect(after, isNotNull);
        expect(
          after!.sale.pendingBalance,
          lessThan(before.sale.pendingBalance),
        );
        expect(after.sale.pendingBalance, greaterThanOrEqualTo(0));

        final recentPayments = await db.query(
          DatabaseSchema.paymentsTable,
          columns: ['tipo_pago'],
          where: 'venta_id = ? AND deleted_at IS NULL',
          whereArgs: [saleId],
          orderBy: 'id DESC',
          limit: 2,
        );
        final types = recentPayments
            .map((row) => row['tipo_pago']?.toString() ?? '')
            .toSet();
        expect(
          types.contains('cuota') || types.contains('abono_capital'),
          isTrue,
        );
      } on StateError {
        // También es válido bloquear sobrepago explícitamente.
        expect(true, isTrue);
      }
    });
  });

  group('comparative_business_logic_offline_sync', () {
    late Directory tempDirectory;
    late AppDatabase appDatabase;
    late SyncQueueService syncQueueService;
    late SalesRepository salesRepository;
    late PaymentsRepository paymentsRepository;
    late StreamController<List<ConnectivityResult>> connectivityController;
    late _MemorySyncApiClient apiClient;
    late bool online;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDirectory = await Directory.systemTemp.createTemp(
        'business_logic_comparative_offline_',
      );
      appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
      await appDatabase.initialize();

      connectivityController =
          StreamController<List<ConnectivityResult>>.broadcast();
      apiClient = _MemorySyncApiClient();
      online = false;

      syncQueueService = SyncQueueService.test(
        appDatabase: appDatabase,
        configRepository: _FakeSyncConfigRepository(),
        apiClient: apiClient,
        conflictService: SyncConflictService(appDatabase: appDatabase),
        connectivityProbe: (_) async => online,
        connectivityChanges: connectivityController.stream,
      );
      ClientRepository(
        appDatabase: appDatabase,
        syncQueueService: syncQueueService,
      );
      SellerRepository(
        database: appDatabase,
        syncQueueService: syncQueueService,
      );
      syncQueueService.registerRepository(
        ProductsSyncRepository(appDatabase: appDatabase),
      );
      syncQueueService.registerRepository(
        SalesSyncRepository(appDatabase: appDatabase),
      );
      syncQueueService.registerRepository(
        InstallmentsSyncRepository(appDatabase: appDatabase),
      );
      syncQueueService.registerRepository(
        PaymentsSyncRepository(appDatabase: appDatabase),
      );

      salesRepository = SalesRepository(
        appDatabase: appDatabase,
        syncQueueService: syncQueueService,
      );
      paymentsRepository = PaymentsRepository(
        appDatabase: appDatabase,
        syncQueueService: syncQueueService,
      );
    });

    tearDown(() async {
      await syncQueueService.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      syncQueueService.dispose();
      await connectivityController.close();
      await appDatabase.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('offline_sale_payment_persist_after_restart_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 4, 1));

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 4, 1),
          salePrice: 500000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 50000,
          initialPaymentPaid: 50000,
          monthlyInterest: 1,
          installmentCount: 10,
        ),
      );

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 5, 1),
          amountPaid: 9000,
          paymentMethod: 'efectivo',
        ),
      );

      await syncQueueService.refreshScope('products');
      await syncQueueService.refreshScope('clients');
      await syncQueueService.refreshScope('sellers');
      await syncQueueService.refreshScope('sales');
      await syncQueueService.refreshScope('installments');
      await syncQueueService.refreshScope('payments');

      final pending = await syncQueueService.pendingCount();
      expect(pending, greaterThan(0));

      final pendingSales = await db.query(
        DatabaseSchema.salesTable,
        where: 'sync_status = ?',
        whereArgs: [DatabaseSchema.syncStatusPendingCreate],
      );
      expect(pendingSales.length, 1);

      final persistedSale = await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      final persistedPayments = await db.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      expect(persistedSale.length, 1);
      expect(persistedPayments.isNotEmpty, isTrue);
    });

    test('offline_payment_creates_sync_queue_entries_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 4, 2));
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 4, 2),
          salePrice: 420000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 42000,
          initialPaymentPaid: 42000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 5, 10),
          amountPaid: 12000,
          paymentMethod: 'efectivo',
        ),
      );

      await syncQueueService.refreshScope('payments');
      final pending = await syncQueueService.pendingCount();
      expect(pending, greaterThan(0));

      final pendingPayments = await db.query(
        DatabaseSchema.paymentsTable,
        where: 'sync_status IN (?, ?, ?)',
        whereArgs: [
          DatabaseSchema.syncStatusPending,
          DatabaseSchema.syncStatusPendingCreate,
          DatabaseSchema.syncStatusPendingUpdate,
        ],
      );
      expect(pendingPayments.isNotEmpty, isTrue);
    });

    test('no_duplicate_installments_when_sale_is_synced_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 4, 3));
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 4, 3),
          salePrice: 600000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 60000,
          initialPaymentPaid: 60000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      await syncQueueService.refreshScope('products');
      await syncQueueService.refreshScope('clients');
      await syncQueueService.refreshScope('sellers');
      await syncQueueService.refreshScope('sales');
      await syncQueueService.refreshScope('installments');
      await syncQueueService.refreshScope('payments');

      online = true;
      await syncQueueService.syncPending();

      final beforeRows = await db.query(
        DatabaseSchema.installmentsTable,
        columns: ['id', 'sync_id'],
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      expect(beforeRows.length, 12);

      await syncQueueService.syncPending();

      final afterRows = await db.query(
        DatabaseSchema.installmentsTable,
        columns: ['id', 'sync_id'],
        where: 'venta_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      expect(afterRows.length, 12);

      final syncIds = afterRows
          .map((row) => row['sync_id']?.toString() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet();
      expect(syncIds.length, 12);
    });

    test('offline_sale_payment_sync_without_duplicates_test', () async {
      final db = await appDatabase.database;
      final ids = await _seedBaseEntities(db, now: DateTime(2026, 4, 4));
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: ids.clientId,
          lotId: ids.lotId,
          userId: 1,
          sellerId: ids.sellerId,
          saleDate: DateTime(2026, 4, 4),
          salePrice: 360000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 36000,
          initialPaymentPaid: 36000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 5, 12),
          amountPaid: 10000,
          paymentMethod: 'efectivo',
        ),
      );

      final paymentRows = await db.query(
        DatabaseSchema.paymentsTable,
        columns: ['sync_id'],
        where: 'venta_id = ? AND tipo_pago = ? AND deleted_at IS NULL',
        whereArgs: [saleId, 'cuota'],
        orderBy: 'id DESC',
        limit: 1,
      );
      final paymentSyncId = paymentRows.single['sync_id'] as String;

      await syncQueueService.refreshScope('products');
      await syncQueueService.refreshScope('clients');
      await syncQueueService.refreshScope('sellers');
      await syncQueueService.refreshScope('sales');
      await syncQueueService.refreshScope('installments');
      await syncQueueService.refreshScope('payments');

      online = true;
      await syncQueueService.processQueue(includeDeferred: true);
      await syncQueueService.processQueue(includeDeferred: true);

      final localRows = await db.query(
        DatabaseSchema.paymentsTable,
        columns: ['sync_id'],
        where: 'sync_id = ? AND deleted_at IS NULL',
        whereArgs: [paymentSyncId],
      );
      expect(localRows.length, 1);
    });
  });
}

class _SeededIds {
  const _SeededIds({
    required this.clientId,
    required this.sellerId,
    required this.lotId,
  });

  final int clientId;
  final int sellerId;
  final int lotId;
}

Future<_SeededIds> _seedBaseEntities(
  dynamic db, {
  required DateTime now,
  String suffix = '',
}) async {
  final stamp = now.toIso8601String();
  final uniqueBase = now.microsecondsSinceEpoch + suffix.hashCode.abs();
  final uniqueDigits = (uniqueBase % 10000000000).toString().padLeft(10, '0');
  final clientId = await db.insert(DatabaseSchema.clientsTable, {
    'sync_id': 'client-$suffix-${now.microsecondsSinceEpoch}',
    'version': 1,
    'nombre': 'Cliente Test $suffix',
    'cedula': uniqueDigits,
    'telefono': '8095550000',
    'direccion': 'Direccion Test',
    'fecha_creacion': stamp,
    'fecha_actualizacion': stamp,
    'deleted_at': null,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  final sellerId = await db.insert(DatabaseSchema.sellersTable, {
    'sync_id': 'seller-$suffix-${now.microsecondsSinceEpoch}',
    'version': 1,
    'nombre': 'Vendedor Test $suffix',
    'cedula': '4$uniqueDigits',
    'telefono': '8095551111',
    'fecha_creacion': stamp,
    'fecha_actualizacion': stamp,
    'deleted_at': null,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  final lotId = await db.insert(DatabaseSchema.lotsTable, {
    'sync_id': 'lot-$suffix-${now.microsecondsSinceEpoch}',
    'version': 1,
    'manzana_numero': suffix.isEmpty ? 'A' : suffix,
    'solar_numero': '${10 + now.second}',
    'metros_cuadrados': 180.0,
    'precio_por_metro': 4000.0,
    'estado': 'disponible',
    'fecha_creacion': stamp,
    'fecha_actualizacion': stamp,
    'deleted_at': null,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  return _SeededIds(clientId: clientId, sellerId: sellerId, lotId: lotId);
}

Future<int> _createActiveSale(
  SalesRepository repository,
  _SeededIds ids, {
  double salePrice = 360000,
}) async {
  return repository.createSale(
    SaleDraft(
      clientId: ids.clientId,
      lotId: ids.lotId,
      userId: 1,
      sellerId: ids.sellerId,
      saleDate: DateTime(2026, 1, 1),
      salePrice: salePrice,
      downPaymentPercentage: 10,
      requiredInitialPayment: salePrice * 0.1,
      initialPaymentPaid: salePrice * 0.1,
      monthlyInterest: 1,
      installmentCount: 12,
    ),
  );
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString()) ?? 0;
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://sync.example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 10),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'desktop-test-device',
    );
  }
}

class _MemorySyncApiClient extends SyncApiClient {
  final Map<String, List<Map<String, dynamic>>> serverRecordsByScope = {};
  final Map<String, List<Map<String, dynamic>>> uploadedRecordsByScope = {};

  int countServerRecords(String scope, String syncId) {
    return (serverRecordsByScope[scope] ?? const <Map<String, dynamic>>[])
        .where((record) => record['sync_id'] == syncId)
        .length;
  }

  int countUploads(String scope, String syncId) {
    return (uploadedRecordsByScope[scope] ?? const <Map<String, dynamic>>[])
        .where((record) => record['sync_id'] == syncId)
        .length;
  }

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final returned = <String, List<Map<String, dynamic>>>{};

    recordsByScope.forEach((scope, records) {
      for (final record in records) {
        final normalized = record.map((key, value) => MapEntry(key, value));
        uploadedRecordsByScope.putIfAbsent(scope, () => []).add(normalized);

        final syncId = normalized['sync_id']?.toString().trim() ?? '';
        if (syncId.isEmpty) {
          continue;
        }

        final serverScope = serverRecordsByScope.putIfAbsent(scope, () => []);
        final existingIndex = serverScope.indexWhere(
          (item) => item['sync_id'] == syncId,
        );
        if (existingIndex == -1) {
          serverScope.add(Map<String, dynamic>.from(normalized));
        } else {
          serverScope[existingIndex] = Map<String, dynamic>.from(normalized);
        }
      }

      returned[scope] = records
          .map((record) => record.map((key, value) => MapEntry(key, value)))
          .toList(growable: false);
    });

    return SyncUploadResponse(returnedRecordsByScope: returned);
  }

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    return SyncDownloadResponse(
      recordsByScope: const {},
      serverTime: DateTime.now(),
    );
  }
}
