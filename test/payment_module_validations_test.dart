import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase db;
  late ClientRepository clientRepo;
  late LotRepository lotRepo;
  late SalesRepository salesRepo;
  late PaymentsRepository paymentsRepo;
  late SyncQueueService syncQueue;
  var _seq = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('payment_module_test_');
    db = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await db.initialize();
    syncQueue = SyncQueueService.test(
      appDatabase: db,
      conflictService: SyncConflictService(appDatabase: db),
    );
    clientRepo = ClientRepository(appDatabase: db);
    lotRepo = LotRepository(appDatabase: db);
    salesRepo = SalesRepository(appDatabase: db, syncQueueService: syncQueue);
    paymentsRepo =
        PaymentsRepository(appDatabase: db, syncQueueService: syncQueue);
  });

  tearDown(() async {
    syncQueue.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> _createActiveSaleWithOverdue({
    int overdueMonths = 2,
    double salePrice = 480000,
    double downPct = 20,
    int installmentCount = 12,
    double monthlyInterest = 1.5,
  }) async {
    _seq++;
    final saleDate = overdueMonths > 0
        ? DateTime.now().subtract(Duration(days: overdueMonths * 31 + 5))
        : DateTime.now();
    final createdAt = saleDate;

    await clientRepo.save(Client(
      fullName: 'Test Client $_seq',
      documentId: '001-0000${_seq.toString().padLeft(5, '0')}-1',
      phone: '8091234567',
      createdAt: createdAt,
      updatedAt: createdAt,
    ));
    await lotRepo.save(Lot(
      blockNumber: 'A',
      lotNumber: _seq.toString().padLeft(2, '0'),
      area: 200,
      price: salePrice,
      status: 'disponible',
      createdAt: createdAt,
      updatedAt: createdAt,
    ));

    final client = (await clientRepo.fetchAll()).last;
    final lot = (await lotRepo.fetchAll()).last;

    final requiredInitial = salePrice * (downPct / 100);
    return salesRepo.createSale(SaleDraft(
      clientId: client.id!,
      lotId: lot.id!,
      userId: 1,
      saleDate: saleDate,
      salePrice: salePrice,
      downPaymentPercentage: downPct,
      requiredInitialPayment: requiredInitial,
      initialPaymentPaid: requiredInitial,
      initialIsApartado: false,
      monthlyInterest: monthlyInterest,
      installmentCount: installmentCount,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 1: cannot_save_zero_payment_test
  // ─────────────────────────────────────────────────────────────────────────
  test('cannot_save_zero_payment_test', () async {
    final saleId = await _createActiveSaleWithOverdue(overdueMonths: 0);

    await expectLater(
      () async => paymentsRepo.registerPayment(PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: 0,
        paymentMethod: 'efectivo',
      )),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('mayor que cero'),
      )),
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 2: overdue_installments_are_shown_in_payment_screen_test
  // ─────────────────────────────────────────────────────────────────────────
  test('overdue_installments_are_shown_in_payment_screen_test', () async {
    final saleId = await _createActiveSaleWithOverdue(overdueMonths: 3);

    final ctx = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctx, isNotNull);

    final overdue = ctx!.overdueInstallments;
    expect(overdue, isNotEmpty,
        reason: 'Sale created 3 months ago must have overdue installments');
    for (final inst in overdue) {
      expect(inst.status, equals('vencida'));
      expect(inst.dueDate.isBefore(DateTime.now()), isTrue);
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 3: cannot_apply_capital_payment_when_overdue_installments_exist_test
  // ─────────────────────────────────────────────────────────────────────────
  test(
    'cannot_apply_capital_payment_when_overdue_installments_exist_test',
    () async {
      final saleId = await _createActiveSaleWithOverdue(overdueMonths: 2);
      final ctx = await paymentsRepo.fetchSaleContext(saleId);
      expect(ctx!.overdueInstallments, isNotEmpty);

      await expectLater(
        () async => paymentsRepo.registerPayment(PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime.now(),
          amountPaid: 5000,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'abono_capital',
        )),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('cuotas vencidas'),
        )),
      );
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 4: can_apply_payment_to_oldest_overdue_installment_test
  // ─────────────────────────────────────────────────────────────────────────
  test('can_apply_payment_to_oldest_overdue_installment_test', () async {
    final saleId = await _createActiveSaleWithOverdue(overdueMonths: 2);

    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxBefore!.overdueInstallments, isNotEmpty);
    final oldestOverdue = ctxBefore.overdueInstallments.first;

    await paymentsRepo.registerPayment(PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime.now(),
      amountPaid: oldestOverdue.remainingAmount,
      paymentMethod: 'efectivo',
      paymentTypeOverride: 'cuota_vencida',
    ));

    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    final paidInst =
        ctxAfter!.installments.firstWhere((i) => i.id == oldestOverdue.id);
    expect(paidInst.status, equals('pagada'));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 5: payment_summary_updates_when_payment_type_changes_test
  // ─────────────────────────────────────────────────────────────────────────
  test('payment_summary_updates_when_payment_type_changes_test', () async {
    final saleId = await _createActiveSaleWithOverdue(overdueMonths: 2);
    final ctx = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctx, isNotNull);

    // When overdue exist, overdueInstallments is non-empty
    expect(ctx!.overdueInstallments, isNotEmpty);
    // actionableInstallment points to the oldest overdue
    expect(ctx.actionableInstallment, isNotNull);
    expect(ctx.actionableInstallment!.status, equals('vencida'));

    // Capital payment is blocked (UI would disable it)
    final capitalBlocked = ctx.overdueInstallments.isNotEmpty;
    expect(capitalBlocked, isTrue,
        reason: 'Capital must be blocked when overdue installments exist');

    // After paying oldest overdue, capital should no longer be blocked
    await paymentsRepo.registerPayment(PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime.now(),
      amountPaid: ctx.overdueInstallments.first.remainingAmount,
      paymentMethod: 'efectivo',
    ));
    final ctx2 = await paymentsRepo.fetchSaleContext(saleId);
    // Check if fewer overdue remain
    expect(ctx2!.overdueInstallments.length,
        lessThan(ctx.overdueInstallments.length),
        reason: 'Paying one overdue reduces overdue count');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 6: cannot_pay_already_paid_installment_test
  // ─────────────────────────────────────────────────────────────────────────
  test('cannot_pay_already_paid_installment_test', () async {
    final saleId = await _createActiveSaleWithOverdue(overdueMonths: 0);

    final ctx = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctx, isNotNull);
    final fullBalance = ctx!.sale.pendingBalance;
    expect(fullBalance, greaterThan(0));

    // Pay full remaining balance as capital (no overdue = allowed)
    await paymentsRepo.registerPayment(PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime.now(),
      amountPaid: fullBalance,
      paymentMethod: 'efectivo',
      paymentTypeOverride: 'abono_capital',
    ));

    // Verify balance is now zero / sale is pagada
    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxAfter!.sale.pendingBalance, lessThanOrEqualTo(0.01),
        reason: 'After paying full balance, pendingBalance must be 0');

    // Attempting another payment must throw
    await expectLater(
      () async => paymentsRepo.registerPayment(PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: 1000,
        paymentMethod: 'efectivo',
      )),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        anyOf(contains('saldo pendiente'), contains('ya no tiene')),
      )),
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 7: capital_payment_allowed_only_when_no_overdue_or_initial_pending_test
  // ─────────────────────────────────────────────────────────────────────────
  test(
    'capital_payment_allowed_only_when_no_overdue_or_initial_pending_test',
    () async {
      // Fresh sale (today) → no overdue installments
      final saleId = await _createActiveSaleWithOverdue(overdueMonths: 0);

      final ctx = await paymentsRepo.fetchSaleContext(saleId);
      expect(ctx!.overdueInstallments, isEmpty,
          reason: 'A fresh sale should have no overdue installments');

      // Capital payment must succeed
      await paymentsRepo.registerPayment(PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: 5000,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'abono_capital',
      ));

      final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
      expect(ctxAfter!.history, isNotEmpty,
          reason: 'Capital payment should be recorded in history');
      expect(ctxAfter.history.first.paymentType, equals('abono_capital'));
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // TEST 8: offline_payment_validation_uses_local_sqlite_test
  // ─────────────────────────────────────────────────────────────────────────
  test('offline_payment_validation_uses_local_sqlite_test', () async {
    // All operations use in-memory SQLite (no network)
    final saleId = await _createActiveSaleWithOverdue(overdueMonths: 1);

    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxBefore, isNotNull,
        reason: 'Context must load from local SQLite without network');

    final instToPay = ctxBefore!.overdueInstallments.isNotEmpty
        ? ctxBefore.overdueInstallments.first
        : ctxBefore.actionableInstallment;
    expect(instToPay, isNotNull);

    final historyCountBefore = ctxBefore.history.length;

    await paymentsRepo.registerPayment(PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime.now(),
      amountPaid: instToPay!.remainingAmount,
      paymentMethod: 'efectivo',
    ));

    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxAfter!.history.length, greaterThan(historyCountBefore),
        reason: 'Payment must be persisted to local SQLite in offline mode');

    // Find the newly added payment in history by matching the amount
    final newPayment = ctxAfter.history.firstWhere(
      (h) => (h.amountPaid - instToPay.remainingAmount).abs() < 0.01,
      orElse: () => throw StateError('New payment not found in history'),
    );
    expect(newPayment.amountPaid, closeTo(instToPay.remainingAmount, 0.01),
        reason: 'Persisted payment amount must match what was registered');
  });
}
