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
  var seq = 0;

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
    paymentsRepo = PaymentsRepository(
      appDatabase: db,
      syncQueueService: syncQueue,
    );
  });

  tearDown(() async {
    syncQueue.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> createActiveSaleWithOverdue({
    int overdueMonths = 2,
    double salePrice = 480000,
    double downPct = 20,
    int installmentCount = 12,
    double monthlyInterest = 1.5,
  }) async {
    seq++;
    final saleDate = overdueMonths > 0
        ? DateTime.now().subtract(Duration(days: overdueMonths * 31 + 5))
        : DateTime.now();
    final createdAt = saleDate;
    await clientRepo.save(
      Client(
        fullName: 'Test Client $seq',
        documentId: '001-0000${seq.toString().padLeft(5, "0")}-1',
        phone: '8091234567',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await lotRepo.save(
      Lot(
        blockNumber: 'A',
        lotNumber: seq.toString().padLeft(2, '0'),
        area: 200,
        price: salePrice,
        status: 'disponible',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    final client = (await clientRepo.fetchAll()).last;
    final lot = (await lotRepo.fetchAll()).last;
    final requiredInitial = salePrice * (downPct / 100);
    return salesRepo.createSale(
      SaleDraft(
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
      ),
    );
  }

  double money(double value) => (value * 100).roundToDouble() / 100;

  double amountWithLateFee(dynamic installment, DateTime paymentDate) {
    final dueDate = installment.dueDate as DateTime;
    final rawRemainingAmount = installment.remainingAmount as double;
    final remainingAmount = money(rawRemainingAmount);
    final overdueDays = DateTime(
      paymentDate.year,
      paymentDate.month,
      paymentDate.day,
    ).difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
    final lateFeeDays = overdueDays > 5 ? overdueDays - 5 : 0;
    final lateFee = money(rawRemainingAmount * 0.005 * lateFeeDays);
    return money(remainingAmount + lateFee);
  }

  test('cannot_save_zero_payment_test', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 0);
    await expectLater(
      () async => paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime.now(),
          amountPaid: 0,
          paymentMethod: 'efectivo',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('mayor que cero'),
        ),
      ),
    );
  });

  test('overdue_installments_are_shown_in_payment_screen_test', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 3);
    final ctx = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctx, isNotNull);
    final overdue = ctx!.overdueInstallments;
    expect(
      overdue,
      isNotEmpty,
      reason: 'Sale created 3 months ago must have overdue installments',
    );
    for (final inst in overdue) {
      expect(inst.status, equals('vencida'));
      expect(inst.dueDate.isBefore(DateTime.now()), isTrue);
    }
  });

  test(
    'cannot_apply_capital_payment_when_overdue_installments_exist_test',
    () async {
      final saleId = await createActiveSaleWithOverdue(overdueMonths: 2);
      final ctx = await paymentsRepo.fetchSaleContext(saleId);
      expect(ctx!.overdueInstallments, isNotEmpty);
      await expectLater(
        () async => paymentsRepo.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime.now(),
            amountPaid: 5000,
            paymentMethod: 'efectivo',
            paymentTypeOverride: 'abono_capital',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('cuotas vencidas'),
          ),
        ),
      );
    },
  );

  test('can_apply_payment_to_oldest_overdue_installment_test', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 2);
    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxBefore!.overdueInstallments, isNotEmpty);
    final oldestOverdue = ctxBefore.overdueInstallments.first;
    await paymentsRepo.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: amountWithLateFee(oldestOverdue, DateTime.now()),
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
      ),
    );
    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    final paidInst = ctxAfter!.installments.firstWhere(
      (i) => i.id == oldestOverdue.id,
    );
    expect(paidInst.status, equals('pagada'));
  });

  test('payment_summary_updates_when_payment_type_changes_test', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 2);
    final ctx = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctx, isNotNull);
    expect(ctx!.overdueInstallments, isNotEmpty);
    expect(ctx.actionableInstallment, isNotNull);
    expect(ctx.actionableInstallment!.status, equals('vencida'));
    final capitalBlocked = ctx.overdueInstallments.isNotEmpty;
    expect(
      capitalBlocked,
      isTrue,
      reason: 'Capital must be blocked when overdue installments exist',
    );
    await paymentsRepo.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: amountWithLateFee(
          ctx.overdueInstallments.first,
          DateTime.now(),
        ),
        paymentMethod: 'efectivo',
      ),
    );
    final ctx2 = await paymentsRepo.fetchSaleContext(saleId);
    expect(
      ctx2!.overdueInstallments.length,
      lessThan(ctx.overdueInstallments.length),
      reason: 'Paying one overdue reduces overdue count',
    );
  });

  test('cannot_pay_already_paid_installment_test', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 0);
    final ctx = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctx, isNotNull);
    final fullBalance = ctx!.sale.pendingBalance;
    expect(fullBalance, greaterThan(0));
    await paymentsRepo.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: fullBalance,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'abono_capital',
      ),
    );
    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    expect(
      ctxAfter!.sale.pendingBalance,
      lessThanOrEqualTo(0.01),
      reason: 'After paying full balance, pendingBalance must be 0',
    );
    await expectLater(
      () async => paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime.now(),
          amountPaid: 1000,
          paymentMethod: 'efectivo',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          anyOf(contains('saldo pendiente'), contains('ya no tiene')),
        ),
      ),
    );
  });

  test(
    'capital_payment_allowed_only_when_no_overdue_or_initial_pending_test',
    () async {
      final saleId = await createActiveSaleWithOverdue(overdueMonths: 0);
      final ctx = await paymentsRepo.fetchSaleContext(saleId);
      expect(
        ctx!.overdueInstallments,
        isEmpty,
        reason: 'A fresh sale should have no overdue installments',
      );
      await paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime.now(),
          amountPaid: 5000,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'abono_capital',
        ),
      );
      final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
      expect(
        ctxAfter!.history,
        isNotEmpty,
        reason: 'Capital payment should be recorded in history',
      );
      expect(ctxAfter.history.first.paymentType, equals('abono_capital'));
    },
  );

  test('future_installment_payment_is_allowed_without_capital_effect', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 0);
    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxBefore, isNotNull);
    expect(ctxBefore!.overdueInstallments, isEmpty);
    final nextInstallment = ctxBefore.actionableInstallment;
    expect(
      nextInstallment,
      isNotNull,
      reason:
          'A fresh financed sale should expose the next open installment for advance payment.',
    );
    expect(nextInstallment!.dueDate.isAfter(DateTime.now()), isTrue);

    await paymentsRepo.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: nextInstallment.remainingAmount,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota',
        targetInstallmentId: nextInstallment.id,
        targetInstallmentNumber: nextInstallment.installmentNumber,
      ),
    );

    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    final updated = ctxAfter!.installments.firstWhere(
      (item) => item.id == nextInstallment.id,
    );
    expect(updated.status, equals('pagada'));
    expect(updated.remainingAmount, lessThanOrEqualTo(0.01));
    expect(ctxAfter.history.first.paymentType, equals('cuota'));
    expect(
      ctxAfter.history.any((item) => item.paymentType == 'abono_capital'),
      isFalse,
      reason: 'Paying a future cuota must not create a capital prepayment.',
    );
  });

  test('advance_installment_mode_pays_future_installments_in_order', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 0);
    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxBefore, isNotNull);
    expect(ctxBefore!.overdueInstallments, isEmpty);
    final openInstallments = ctxBefore.installments
        .where((item) => item.remainingAmount > 0.009)
        .toList();
    expect(openInstallments.length, greaterThanOrEqualTo(2));
    final firstTwo = openInstallments.take(2).toList();
    final amount = money(
      firstTwo.fold(0.0, (sum, item) => sum + item.remainingAmount),
    );

    await paymentsRepo.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: amount,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuotas_adelantadas',
      ),
    );

    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    for (final installment in firstTwo) {
      final updated = ctxAfter!.installments.firstWhere(
        (item) => item.id == installment.id,
      );
      expect(updated.status, equals('pagada'));
      expect(updated.remainingAmount, lessThanOrEqualTo(0.01));
    }
    expect(
      ctxAfter!.history.where((item) => item.paymentType == 'cuota').length,
      greaterThanOrEqualTo(2),
    );
    expect(
      ctxAfter.history.any((item) => item.paymentType == 'abono_capital'),
      isFalse,
      reason:
          'Advance installment payments must not recalculate future schedule as capital.',
    );
  });

  test('advance_installment_mode_is_blocked_when_overdue_exists', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 2);
    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(ctxBefore!.overdueInstallments, isNotEmpty);

    await expectLater(
      () async => paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime.now(),
          amountPaid: ctxBefore.installments.first.remainingAmount,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuotas_adelantadas',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('cuotas vencidas'),
        ),
      ),
    );
  });

  test('offline_payment_validation_uses_local_sqlite_test', () async {
    final saleId = await createActiveSaleWithOverdue(overdueMonths: 1);
    final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
    expect(
      ctxBefore,
      isNotNull,
      reason: 'Context must load from local SQLite without network',
    );
    final instToPay = ctxBefore!.overdueInstallments.isNotEmpty
        ? ctxBefore.overdueInstallments.first
        : ctxBefore.actionableInstallment;
    expect(instToPay, isNotNull);
    final historyCountBefore = ctxBefore.history.length;
    final amountPaid = amountWithLateFee(instToPay, DateTime.now());
    await paymentsRepo.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime.now(),
        amountPaid: amountPaid,
        paymentMethod: 'efectivo',
      ),
    );
    final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
    expect(
      ctxAfter!.history.length,
      greaterThan(historyCountBefore),
      reason: 'Payment must be persisted to local SQLite in offline mode',
    );
    final newPayment = ctxAfter.history.firstWhere(
      (h) => (h.amountPaid - amountPaid).abs() < 0.01,
      orElse: () => throw StateError('New payment not found in history'),
    );
    expect(
      newPayment.amountPaid,
      closeTo(amountPaid, 0.01),
      reason: 'Persisted payment amount must match what was registered',
    );
  });

  test(
    'todas_cuotas_vencidas_pays_all_overdue_in_one_transaction_test',
    () async {
      final saleId = await createActiveSaleWithOverdue(overdueMonths: 3);
      final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
      final overdueList = ctxBefore!.overdueInstallments;
      final paymentDate = DateTime.now();
      expect(
        overdueList.length,
        greaterThanOrEqualTo(2),
        reason: 'Must have multiple overdue installments to test batch pay',
      );
      final totalOverdue = money(
        overdueList.fold(
          0.0,
          (sum, i) => sum + amountWithLateFee(i, paymentDate),
        ),
      );
      await paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: paymentDate,
          amountPaid: totalOverdue,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'todas_cuotas_vencidas',
        ),
      );
      final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
      for (final overdue in overdueList) {
        final updated = ctxAfter!.installments.firstWhere(
          (i) => i.id == overdue.id,
        );
        expect(
          updated.status,
          equals('pagada'),
          reason:
              'Cuota #${overdue.installmentNumber} should be pagada after batch pay',
        );
      }
      expect(
        ctxAfter!.overdueInstallments,
        isEmpty,
        reason: 'No overdue installments should remain after paying all',
      );
      final newPayments = ctxAfter.history
          .where((h) => h.paymentType == 'cuota')
          .toList();
      expect(
        newPayments.length,
        greaterThanOrEqualTo(overdueList.length),
        reason: 'History must include a cuota payment entry per installment',
      );
    },
  );

  test(
    'payment_correctly_marks_sale_pagada_when_all_installments_paid',
    () async {
      final saleId = await createActiveSaleWithOverdue(
        overdueMonths: 12,
        installmentCount: 12,
      );
      final ctxBefore = await paymentsRepo.fetchSaleContext(saleId);
      final paymentDate = DateTime.now();
      final dueInstallments = ctxBefore!.installments
          .where((installment) {
            final dueDate = installment.dueDate;
            return DateTime(dueDate.year, dueDate.month, dueDate.day).compareTo(
                  DateTime(
                    paymentDate.year,
                    paymentDate.month,
                    paymentDate.day,
                  ),
                ) <=
                0;
          })
          .toList(growable: false);
      final dueAmount = money(
        dueInstallments.fold(
          0.0,
          (sum, installment) =>
              sum + amountWithLateFee(installment, paymentDate),
        ),
      );
      final outstandingPrincipal = money(
        ctxBefore.installments.fold<double>(
          0,
          (sum, installment) =>
              sum +
              (installment.principalAmount - installment.paidPrincipalAmount)
                  .clamp(0, installment.principalAmount)
                  .toDouble(),
        ),
      );
      final principalPaidByDueInstallments = money(
        dueInstallments.fold<double>(
          0,
          (sum, installment) =>
              sum +
              (installment.principalAmount - installment.paidPrincipalAmount)
                  .clamp(0, installment.principalAmount)
                  .toDouble(),
        ),
      );
      final totalDue = money(
        dueAmount +
            money(outstandingPrincipal - principalPaidByDueInstallments),
      );
      expect(totalDue, greaterThan(0));
      await paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: paymentDate,
          amountPaid: totalDue,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'todas_cuotas_vencidas',
        ),
      );
      final ctxAfter = await paymentsRepo.fetchSaleContext(saleId);
      expect(
        ctxAfter!.sale.status,
        equals('pagada'),
        reason: 'Sale must transition to pagada when all installments are paid',
      );
      for (final inst in ctxAfter.installments) {
        expect(
          inst.status,
          equals('pagada'),
          reason: 'All installments must be pagada after full plan is settled',
        );
      }
    },
  );

  test(
    'payment_only_targets_active_installments_not_soft_deleted_ones',
    () async {
      seq++;
      final saleDate = DateTime.now().subtract(const Duration(days: 62));
      await clientRepo.save(
        Client(
          fullName: 'Regression Client $seq',
          documentId: '001-0000${seq.toString().padLeft(5, "0")}-9',
          phone: '8091234567',
          createdAt: saleDate,
          updatedAt: saleDate,
        ),
      );
      await lotRepo.save(
        Lot(
          blockNumber: 'R',
          lotNumber: seq.toString().padLeft(2, '0'),
          area: 200,
          price: 480000,
          status: 'disponible',
          createdAt: saleDate,
          updatedAt: saleDate,
        ),
      );
      final client = (await clientRepo.fetchAll()).last;
      final lot = (await lotRepo.fetchAll()).last;
      final saleId = await salesRepo.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: saleDate,
          salePrice: 480000,
          downPaymentPercentage: 20,
          requiredInitialPayment: 96000,
          initialPaymentPaid: 0,
          initialIsApartado: true,
          minimumReserveAmount: 10000,
          initialPaymentDeadline: DateTime.now().add(const Duration(days: 30)),
          monthlyInterest: 1.5,
          installmentCount: 12,
        ),
      );
      await paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: saleDate,
          amountPaid: 96000,
          paymentMethod: 'efectivo',
        ),
      );
      final ctxAfterActivation = await paymentsRepo.fetchSaleContext(saleId);
      expect(
        ctxAfterActivation!.sale.status,
        equals('activa'),
        reason: 'Sale should be activa after full initial payment',
      );
      final activeCount = ctxAfterActivation.installments.length;
      expect(activeCount, greaterThan(0));
      final overdueInst = ctxAfterActivation.overdueInstallments;
      expect(
        overdueInst,
        isNotEmpty,
        reason: 'Sale started 62 days ago must have overdue installments',
      );
      final targetInst = overdueInst.first;
      await paymentsRepo.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime.now(),
          amountPaid: amountWithLateFee(targetInst, DateTime.now()),
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuota_vencida',
        ),
      );
      final ctxAfterPayment = await paymentsRepo.fetchSaleContext(saleId);
      final updatedInst = ctxAfterPayment!.installments.firstWhere(
        (i) => i.id == targetInst.id,
      );
      expect(
        updatedInst.status,
        equals('pagada'),
        reason:
            'Active installment must be pagada; payment must not go to deleted rows',
      );
      expect(
        ctxAfterPayment.installments.length,
        equals(activeCount),
        reason: 'Active installment count must remain unchanged after payment',
      );
    },
  );
}
