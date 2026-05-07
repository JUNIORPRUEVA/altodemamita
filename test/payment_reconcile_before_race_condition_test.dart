/// Tests that verify the pre-payment reconcile protects against sync race
/// conditions where installment monto_pagado is reset to 0 by conflict
/// recovery before the user submits a new payment.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('pre-payment reconcile guards against sync race condition', () {
    test(
      'paying cuota #2 does NOT re-pay cuota #1 when sync reset cuota #1 '
      'monto_pagado to 0 but existing pagos record still exists',
      () async {
        final harness = await PaymentApplicationTestHarness.create();
        addTearDown(harness.dispose);
        final db = await harness.appDatabase.database;

        final saleId = await harness.createFinancedSale(
          saleDate: DateTime(2025, 1, 1),
          salePrice: 100000,
          requiredInitialPayment: 10000,
          installmentCount: 4,
          monthlyInterest: 1.0,
        );

        // Load context to get installment IDs.
        final ctx = await harness.paymentsRepository.fetchSaleContext(saleId);
        expect(ctx, isNotNull);
        final cuota1 = ctx!.installments.firstWhere((i) => i.installmentNumber == 1);
        final cuota2 = ctx.installments.firstWhere((i) => i.installmentNumber == 2);

        // Pay cuota #1 fully.
        await harness.paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime(2025, 2, 5),
            amountPaid: cuota1.totalAmount,
            paymentMethod: 'efectivo',
            paymentTypeOverride: 'cuota_vencida',
            targetInstallmentId: cuota1.id,
            targetInstallmentNumber: cuota1.installmentNumber,
          ),
        );

        // Verify cuota #1 is now pagada.
        final afterPay = await harness.paymentsRepository.fetchSaleContext(saleId);
        final c1After = afterPay!.installments.firstWhere(
          (i) => i.installmentNumber == 1,
        );
        expect(c1After.status, 'pagada');
        expect(c1After.paidAmount, closeTo(cuota1.totalAmount, 0.01));

        // SIMULATE SYNC RACE CONDITION:
        // Server conflict recovery resets cuota #1 back to its original state
        // (monto_pagado=0, estado=vencida) — but the pagos row still exists.
        await db.update(
          DatabaseSchema.installmentsTable,
          {
            'monto_pagado': 0.0,
            'capital_pagado': 0.0,
            'interes_pagado': 0.0,
            'estado': 'vencida',
            'sync_status': 'synced',
          },
          where: 'id = ?',
          whereArgs: [cuota1.id],
        );

        // Verify the reset happened.
        final resetRows = await db.query(
          DatabaseSchema.installmentsTable,
          where: 'id = ?',
          whereArgs: [cuota1.id],
        );
        expect(resetRows.first['monto_pagado'], closeTo(0.0, 0.01));
        expect(resetRows.first['estado'], 'vencida');

        // NOW pay cuota #2 — the pre-payment reconcile should restore cuota #1
        // from pagos before the transaction runs.
        await harness.paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime(2025, 3, 5),
            amountPaid: cuota2.totalAmount,
            paymentMethod: 'efectivo',
            paymentTypeOverride: 'cuota_vencida',
            targetInstallmentId: cuota2.id,
            targetInstallmentNumber: cuota2.installmentNumber,
          ),
        );

        // cuota #1 must remain pagada (restored by reconcile, not re-paid).
        final c1Final = await db.query(
          DatabaseSchema.installmentsTable,
          where: 'id = ?',
          whereArgs: [cuota1.id],
        );
        expect(
          c1Final.first['estado'],
          'pagada',
          reason: 'cuota #1 should be pagada after reconcile restores it',
        );
        expect(
          c1Final.first['monto_pagado'],
          closeTo(cuota1.totalAmount, 0.01),
          reason: 'cuota #1 monto_pagado should be restored to the full amount',
        );

        // cuota #2 should be fully paid.
        final c2Final = await db.query(
          DatabaseSchema.installmentsTable,
          where: 'id = ?',
          whereArgs: [cuota2.id],
        );
        expect(c2Final.first['estado'], 'pagada');
        expect(
          c2Final.first['monto_pagado'],
          closeTo(cuota2.totalAmount, 0.01),
        );

        // There should be exactly 2 pagos total (one for each cuota).
        final allPagos = await db.query(
          DatabaseSchema.paymentsTable,
          where: 'venta_id = ? AND deleted_at IS NULL AND tipo_pago = ?',
          whereArgs: [saleId, 'cuota'],
        );
        expect(
          allPagos.length,
          2,
          reason: 'Only 2 cuota pagos should exist, not 3 (no duplicate for cuota #1)',
        );
      },
    );

    test(
      'todas_cuotas_vencidas does NOT re-pay cuota #1 when sync reset its state',
      () async {
        final harness = await PaymentApplicationTestHarness.create();
        addTearDown(harness.dispose);
        final db = await harness.appDatabase.database;

        final saleId = await harness.createFinancedSale(
          saleDate: DateTime(2025, 1, 1),
          salePrice: 100000,
          requiredInitialPayment: 10000,
          installmentCount: 4,
          monthlyInterest: 1.0,
        );

        final ctx = await harness.paymentsRepository.fetchSaleContext(saleId);
        final cuota1 = ctx!.installments.firstWhere((i) => i.installmentNumber == 1);
        final cuota2 = ctx.installments.firstWhere((i) => i.installmentNumber == 2);

        // Pay cuota #1.
        await harness.paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime(2025, 2, 5),
            amountPaid: cuota1.totalAmount,
            paymentMethod: 'efectivo',
            paymentTypeOverride: 'cuota_vencida',
            targetInstallmentId: cuota1.id,
            targetInstallmentNumber: cuota1.installmentNumber,
          ),
        );

        // Simulate sync reset for cuota #1.
        await db.update(
          DatabaseSchema.installmentsTable,
          {
            'monto_pagado': 0.0,
            'capital_pagado': 0.0,
            'interes_pagado': 0.0,
            'estado': 'vencida',
            'sync_status': 'synced',
          },
          where: 'id = ?',
          whereArgs: [cuota1.id],
        );

        // Pay using todas_cuotas_vencidas — should only hit cuota #2.
        await harness.paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: DateTime(2025, 3, 5),
            amountPaid: cuota2.totalAmount,
            paymentMethod: 'efectivo',
            paymentTypeOverride: 'todas_cuotas_vencidas',
            targetInstallmentId: null,
            targetInstallmentNumber: null,
          ),
        );

        // cuota #1 must not have been touched again.
        final pagosForCuota1 = await db.query(
          DatabaseSchema.paymentsTable,
          where: 'cuota_id = ? AND deleted_at IS NULL',
          whereArgs: [cuota1.id],
        );
        expect(
          pagosForCuota1.length,
          1,
          reason: 'cuota #1 should have only its original single pago',
        );
      },
    );
  });
}

