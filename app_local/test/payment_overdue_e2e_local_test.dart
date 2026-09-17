import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/business/installment_status.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';

import 'helpers/payment_application_test_harness.dart';

/// Cobertura E2E de extremo a extremo (DB SQLite real + repositorios reales) de
/// los escenarios que cambian el conteo de cuotas vencidas, verificando paridad
/// LISTA == DETALLE y ausencia de duplicados.
///
/// Las fechas se derivan de la FECHA DE NEGOCIO real (`currentBusinessDateKey`)
/// para que el resultado sea determinista sin importar el dia en que se ejecute.
void main() {
  late DateTime anchor;

  setUpAll(() {
    // Fecha de negocio (America/Santo_Domingo) como fecha naive de pared.
    anchor = DateTime.parse(InstallmentStatusResolver.currentBusinessDateKey());
  });

  /// Venta con EXACTAMENTE 2 cuotas vencidas (cuota 1 y cuota 2) y el resto
  /// pendientes: el ancla queda 2 meses y 5 dias atras.
  Future<int> createSaleWithTwoOverdue(PaymentApplicationTestHarness harness) {
    return harness.createFinancedSale(
      saleDate: DateTime(
        anchor.year,
        anchor.month - 2,
        anchor.day,
      ).subtract(const Duration(days: 5)),
      installmentCount: 6,
    );
  }

  /// Venta sin cuotas vencidas (ancla hoy: la primera cuota vence en 1 mes).
  Future<int> createSaleWithoutOverdue(
    PaymentApplicationTestHarness harness,
  ) {
    return harness.createFinancedSale(saleDate: anchor, installmentCount: 6);
  }

  Future<int> listOverdue(
    PaymentApplicationTestHarness harness,
    int saleId,
  ) async {
    final summaries = await harness.salesRepository.fetchAll();
    final summary = summaries.where((item) => item.id == saleId).toList();
    expect(summary, hasLength(1), reason: 'la venta debe aparecer en la lista');
    return summary.first.overdueInstallmentCount;
  }

  Future<String?> listOverdueLabel(
    PaymentApplicationTestHarness harness,
    int saleId,
  ) async {
    final summaries = await harness.salesRepository.fetchAll();
    return summaries.firstWhere((item) => item.id == saleId)
        .overdueInstallmentsLabel;
  }

  Future<int> detailOverdue(
    PaymentApplicationTestHarness harness,
    int saleId,
  ) async {
    final detail = await harness.salesRepository.fetchDetail(saleId);
    expect(detail, isNotNull, reason: 'el detalle real debe existir');
    return detail!.overdueInstallmentCount;
  }

  Future<double> listPendingBalance(
    PaymentApplicationTestHarness harness,
    int saleId,
  ) async {
    final summaries = await harness.salesRepository.fetchAll();
    return summaries.firstWhere((item) => item.id == saleId).pendingBalance;
  }

  Future<int> paymentsCount(PaymentApplicationTestHarness harness) async {
    final db = await harness.appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DatabaseSchema.paymentsTable}',
    );
    return (rows.first['total'] as num).toInt();
  }

  /// Deuda pendiente total del cronograma (suma de saldos de cuotas).
  double debtOf(List<Installment> installments) {
    return installments.fold<double>(
      0,
      (total, item) => total + item.remainingAmount,
    );
  }

  test(
    'E2E pago TOTAL de cuota vencida: lista y detalle bajan de 2 a 1 y no duplica',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      final saleId = await createSaleWithTwoOverdue(harness);
      // La venta registra su pago INICIAL: el baseline no es cero.
      final baselinePayments = await paymentsCount(harness);

      // PRE: 2 vencidas, list == detail, etiqueta en plural.
      final pre = await harness.paymentsRepository.fetchSaleContext(saleId);
      expect(pre, isNotNull);
      expect(pre!.overdueInstallments, hasLength(2));
      expect(pre.installments, hasLength(6));
      expect(await listOverdue(harness, saleId), 2);
      expect(await detailOverdue(harness, saleId), 2);
      expect(await listOverdueLabel(harness, saleId), '2 cuotas vencidas');

      final target = pre.overdueInstallments.first;
      await harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: anchor,
          amountPaid: target.remainingAmount,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuota_vencida',
          targetInstallmentId: target.id,
        ),
      );

      // POST: 1 vencida en lista Y en detalle (paridad) y etiqueta en singular.
      final post = await harness.paymentsRepository.fetchSaleContext(saleId);
      expect(post!.overdueInstallments, hasLength(1));
      expect(await listOverdue(harness, saleId), 1);
      expect(await detailOverdue(harness, saleId), 1);
      expect(await listOverdueLabel(harness, saleId), '1 cuota vencida');

      // Sin duplicados: mismas cuotas y exactamente UN pago nuevo.
      expect(post.installments, hasLength(6));
      expect(post.installments.where((i) => i.status == 'pagada'), hasLength(1));
      expect(await paymentsCount(harness), baselinePayments + 1);
    },
  );

  test(
    'E2E pago PARCIAL: el conteo de vencidas NO baja (2) y lista == detalle',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      final saleId = await createSaleWithTwoOverdue(harness);
      final baselinePayments = await paymentsCount(harness);

      final pre = await harness.paymentsRepository.fetchSaleContext(saleId);
      final target = pre!.overdueInstallments.first;
      await harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: anchor,
          amountPaid: target.remainingAmount / 2,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuota_vencida',
          targetInstallmentId: target.id,
        ),
      );

      final post = await harness.paymentsRepository.fetchSaleContext(saleId);
      final updated = post!.installments.firstWhere((i) => i.id == target.id);
      expect(updated.status, 'parcial');
      expect(updated.paidAmount, greaterThan(0));
      expect(updated.paidAmount, lessThan(updated.totalAmount));

      // Una cuota parcial sigue vencida: el conteo se mantiene en 2.
      expect(post.overdueInstallments, hasLength(2));
      expect(await listOverdue(harness, saleId), 2);
      expect(await detailOverdue(harness, saleId), 2);
      expect(await listOverdueLabel(harness, saleId), '2 cuotas vencidas');
      expect(await paymentsCount(harness), baselinePayments + 1);
    },
  );

  test(
    'E2E pago a CAPITAL sin vencidas: aplica, baja saldo y no altera el conteo',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      final saleId = await createSaleWithoutOverdue(harness);

      final baselinePayments = await paymentsCount(harness);
      final preContext = await harness.paymentsRepository.fetchSaleContext(
        saleId,
      );
      expect(preContext!.overdueInstallments, isEmpty);
      final debtBefore = debtOf(preContext.installments);
      final balanceBefore = await listPendingBalance(harness, saleId);
      expect(debtBefore, greaterThan(0));
      expect(balanceBefore, closeTo(90000, 0.02));
      expect(await listOverdueLabel(harness, saleId), isNull);

      await harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: anchor,
          amountPaid: 5000,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'abono_capital',
        ),
      );

      final postContext = await harness.paymentsRepository.fetchSaleContext(
        saleId,
      );
      expect(postContext!.installments, hasLength(6));
      expect(postContext.overdueInstallments, isEmpty);

      // P1 CORREGIDO: el abono a capital SI reduce la deuda en el acto. Antes
      // quedaba identica porque el calendario reconstruido generaba capital
      // fantasma (ver capital_payment_local_effect_test.dart).
      final debtAfter = debtOf(postContext.installments);
      expect(
        debtAfter,
        lessThan(debtBefore),
        reason: 'un abono a capital debe reducir la deuda pendiente',
      );
      final balanceAfter = await listPendingBalance(harness, saleId);
      expect(
        balanceAfter,
        closeTo(balanceBefore - 5000, 0.02),
        reason: 'el saldo de la venta baja exactamente el abono a capital',
      );

      // Paridad lista/detalle y sin duplicados: el pago se registra UNA vez.
      expect(await listOverdue(harness, saleId), 0);
      expect(await detailOverdue(harness, saleId), 0);
      expect(await listOverdueLabel(harness, saleId), isNull);
      expect(await paymentsCount(harness), baselinePayments + 1);
      expect(await listPendingBalance(harness, saleId), greaterThan(0));
    },
  );

  test(
    'E2E pago a CAPITAL con cuotas vencidas: bloqueado por regla de negocio',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      final saleId = await createSaleWithTwoOverdue(harness);
      final baselinePayments = await paymentsCount(harness);
      expect(await listOverdue(harness, saleId), 2);

      await expectLater(
        harness.paymentsRepository.registerPayment(
          PaymentDraft(
            saleId: saleId,
            paymentDate: anchor,
            amountPaid: 5000,
            paymentMethod: 'efectivo',
            paymentTypeOverride: 'abono_capital',
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Nada se aplico: ni pago nuevo ni cambio de conteo.
      expect(await paymentsCount(harness), baselinePayments);
      expect(await listOverdue(harness, saleId), 2);
      expect(await detailOverdue(harness, saleId), 2);
    },
  );
}
