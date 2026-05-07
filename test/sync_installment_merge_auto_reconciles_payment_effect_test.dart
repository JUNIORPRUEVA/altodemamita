import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';

import 'helpers/payment_application_test_harness.dart';

void main() {
  test('sync_installment_merge_auto_reconciles_payment_effect_test', () async {
    final harness = await PaymentApplicationTestHarness.create();
    addTearDown(harness.dispose);

    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(2025, 1, 10),
      installmentCount: 2,
    );
    final context = await harness.paymentsRepository.fetchSaleContext(saleId);
    final target = context!.overdueInstallments.first;

    await harness.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: DateTime(2026, 3, 1),
        amountPaid: 250,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'cuota_vencida',
        targetInstallmentId: target.id,
      ),
    );

    final db = await harness.appDatabase.database;
    final sameTimestamp = DateTime(2026, 3, 1, 12).toIso8601String();
    await db.update(
      DatabaseSchema.installmentsTable,
      {
        'sync_status': DatabaseSchema.syncStatusSynced,
        'fecha_actualizacion': sameTimestamp,
        'last_modified_local': null,
      },
      where: 'id = ?',
      whereArgs: [target.id],
    );

    final localRow = (await db.query(
      DatabaseSchema.installmentsTable,
      where: 'id = ?',
      whereArgs: [target.id],
      limit: 1,
    )).first;

    final repository = InstallmentsSyncRepository(
      appDatabase: harness.appDatabase,
    );
    await repository.mergeRemoteRecords([
      {
        'sync_id': localRow['sync_id'],
        'sale_sync_id': (await db.query(
          DatabaseSchema.salesTable,
          columns: ['sync_id'],
          where: 'id = ?',
          whereArgs: [saleId],
          limit: 1,
        )).first['sync_id'],
        'version': localRow['version'] ?? 1,
        'installment_number': localRow['numero_cuota'],
        'due_date': localRow['fecha_vencimiento'],
        'opening_balance': localRow['saldo_inicial'],
        'principal_amount': localRow['capital_cuota'],
        'interest_amount': localRow['interes_cuota'],
        'total_amount': localRow['monto_cuota'],
        'paid_amount': 0,
        'paid_principal_amount': 0,
        'paid_interest_amount': 0,
        'ending_balance': localRow['saldo_final'],
        'status': 'vencida',
        'created_at': localRow['fecha_creacion'],
        'updated_at': sameTimestamp,
        'deleted_at': null,
      },
    ]);

    final afterRow = (await db.query(
      DatabaseSchema.installmentsTable,
      where: 'id = ?',
      whereArgs: [target.id],
      limit: 1,
    )).first;

    expect((afterRow['monto_pagado'] as num).toDouble(), greaterThan(0));
    expect(afterRow['estado'], isNot('vencida'));
  });
}
