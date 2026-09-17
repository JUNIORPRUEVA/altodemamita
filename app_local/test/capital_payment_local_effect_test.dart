import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/business/installment_status.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/domain/sale_calculator.dart';

import 'helpers/payment_application_test_harness.dart';

/// PARTE A — ABONO A CAPITAL EN MODO LOCAL
///
/// BUG REPRODUCIDO (evidencia cruda en cuotas/ventas):
///   venta financiada 90000 / 6 cuotas / interes 1% / pago fijo 15529.353003979288
///   abono a capital 5000 =>
///     saldo_pendiente ANTES  =  90000
///     saldo_pendiente DESPUES=  90307.6   <-- SUBIA (capital fantasma)
///     suma(capital_cuota) DESPUES = 90307.598 > 90000-5000 = 85000
///
/// ROOT CAUSE:
///   `sale_calculator.dart` (buildInstallmentScheduleForDueDatesWithFixedPayment)
///   calculaba `principalAmount = pagoFijo - interes` SIN acotarlo al saldo de
///   apertura, por lo que la ultima cuota amortizaba mas capital del que quedaba
///   (15428.14 cuando solo restaban 10120.53) y el exceso se perdia al forzar
///   `endingBalance = 0`. El backend SI acota
///   (financing.service.ts: `clamp(scheduledPrincipal, 0, openingBalance)` y la
///   ultima cuota amortiza todo el saldo), de modo que era una divergencia
///   local/backend. Como el saldo de la venta se deriva de SUM(capital_cuota),
///   el operador veia MAS deuda despues de abonar.
void main() {
  late DateTime anchor;

  setUpAll(() {
    anchor = DateTime.parse(InstallmentStatusResolver.currentBusinessDateKey());
  });

  Future<Map<String, double>> snapshot(
    PaymentApplicationTestHarness h,
    int saleId,
  ) async {
    final db = await h.appDatabase.database;
    final cuotas = await db.rawQuery(
      'SELECT capital_cuota, interes_cuota, monto_cuota, saldo_inicial, '
      'saldo_final, monto_pagado FROM cuotas WHERE venta_id = ? '
      'ORDER BY numero_cuota ASC',
      [saleId],
    );
    final venta = await db.rawQuery(
      'SELECT saldo_financiado, saldo_pendiente FROM ventas WHERE id = ?',
      [saleId],
    );
    var capital = 0.0;
    var cuotasConFantasma = 0;
    var desbalanceMonto = 0;
    for (final row in cuotas) {
      final capitalCuota = (row['capital_cuota'] as num).toDouble();
      final interes = (row['interes_cuota'] as num).toDouble();
      final monto = (row['monto_cuota'] as num).toDouble();
      final saldoInicial = (row['saldo_inicial'] as num).toDouble();
      capital += capitalCuota;
      if (capitalCuota - saldoInicial > 0.009) {
        cuotasConFantasma++;
      }
      if ((monto - (capitalCuota + interes)).abs() > 0.009) {
        desbalanceMonto++;
      }
    }
    return {
      'capital_total': double.parse(capital.toStringAsFixed(2)),
      'saldo_financiado': (venta.first['saldo_financiado'] as num).toDouble(),
      'saldo_pendiente': (venta.first['saldo_pendiente'] as num).toDouble(),
      'cuotas': cuotas.length.toDouble(),
      'cuotas_con_capital_fantasma': cuotasConFantasma.toDouble(),
      'cuotas_con_monto_inconsistente': desbalanceMonto.toDouble(),
    };
  }

  Future<int> paymentsCount(PaymentApplicationTestHarness h) async {
    final db = await h.appDatabase.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM pagos');
    return (rows.first['total'] as num).toInt();
  }

  Future<void> payCapital(
    PaymentApplicationTestHarness h,
    int saleId,
    double amount,
  ) {
    return h.paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: anchor,
        amountPaid: amount,
        paymentMethod: 'efectivo',
        paymentTypeOverride: 'abono_capital',
      ),
    );
  }

  test(
    'A2/FIX: abono a capital 5000 reduce la deuda EXACTAMENTE 5000 y no crea capital fantasma',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      final saleId = await harness.createFinancedSale(
        saleDate: anchor,
        installmentCount: 6,
      );
      final baselinePayments = await paymentsCount(harness);

      final before = await snapshot(harness, saleId);
      expect(before['cuotas'], 6);
      expect(before['saldo_financiado'], 90000);
      // Invariante base: el saldo de la venta ES la suma del capital del calendario.
      expect(
        before['saldo_pendiente'],
        closeTo(before['capital_total']!, 0.01),
      );
      expect(before['cuotas_con_capital_fantasma'], 0);
      expect(before['cuotas_con_monto_inconsistente'], 0);

      await payCapital(harness, saleId, 5000);

      final after = await snapshot(harness, saleId);
      expect(after['cuotas'], 6, reason: 'no se crean ni se pierden cuotas');
      expect(
        await paymentsCount(harness),
        baselinePayments + 1,
        reason: 'exactamente un pago nuevo',
      );
      // EFECTO FINANCIERO: el capital del calendario baja exactamente 5000.
      expect(
        after['capital_total'],
        closeTo(before['capital_total']! - 5000, 0.02),
        reason: 'SUM(capital_cuota) debe bajar exactamente el abono',
      );
      // El saldo visible de la venta baja (antes SUBIA a 90307.6).
      expect(
        after['saldo_pendiente'],
        lessThan(before['saldo_pendiente']!),
        reason: 'el operador no puede ver MAS deuda tras abonar 5000',
      );
      expect(
        after['saldo_pendiente'],
        closeTo(before['saldo_pendiente']! - 5000, 0.02),
      );
      // El saldo de la venta sigue siendo consistente con el calendario.
      expect(after['saldo_pendiente'], closeTo(after['capital_total']!, 0.01));
      // Sin capital fantasma ni montos internamente inconsistentes.
      expect(after['cuotas_con_capital_fantasma'], 0);
      expect(after['cuotas_con_monto_inconsistente'], 0);
    },
  );

  test(
    'A5/PARIDAD: el calendario local reproduce EXACTAMENTE el del backend para el mismo fixture',
    () async {
      // Valores capturados EJECUTANDO el backend real
      // (backend/src/services/financing.service.ts -> buildInstallmentSchedule)
      // con: financedBalance=85000, interes=1%, pago fijo=15529.353003979288,
      // 6 vencimientos mensuales (16/10/2026 ... 16/03/2027).
      final schedule =
          SaleCalculator.buildInstallmentScheduleForDueDatesWithFixedPayment(
            saleId: 1,
            dueDates: List.generate(6, (i) => DateTime(2026, 10 + i, 16)),
            financedBalance: 85000,
            monthlyInterest: 1,
            fixedPaymentAmount: 15529.353003979288,
            createdAt: DateTime(2026, 9, 16),
            statusAsOf: DateTime(2026, 9, 16),
          );

      expect(schedule, hasLength(6));
      final expectedPrincipal = [
        14679.35,
        14826.14,
        14974.40,
        15124.15,
        15275.39,
        10120.57,
      ];
      final expectedInterest = [850.00, 703.21, 554.95, 405.20, 253.96, 101.21];
      final expectedTotal = [
        15529.35,
        15529.35,
        15529.35,
        15529.35,
        15529.35,
        10221.78,
      ];

      for (var i = 0; i < schedule.length; i++) {
        expect(
          schedule[i].principalAmount,
          closeTo(expectedPrincipal[i], 0.01),
          reason: 'capital de la cuota ${i + 1}',
        );
        expect(
          schedule[i].interestAmount,
          closeTo(expectedInterest[i], 0.01),
          reason: 'interes de la cuota ${i + 1}',
        );
        expect(
          schedule[i].totalAmount,
          closeTo(expectedTotal[i], 0.01),
          reason: 'monto de la cuota ${i + 1}',
        );
        expect(
          schedule[i].principalAmount,
          lessThanOrEqualTo(schedule[i].openingBalance + 0.009),
          reason: 'el capital nunca puede exceder el saldo de apertura',
        );
      }
      // El backend cierra el capital exactamente en el principal de partida.
      final totalPrincipal = schedule.fold<double>(
        0,
        (sum, item) => sum + item.principalAmount,
      );
      expect(totalPrincipal, closeTo(85000, 0.02));
      // La ultima cuota amortiza el saldo restante y cierra en cero.
      expect(
        schedule.last.principalAmount,
        closeTo(schedule.last.openingBalance, 0.01),
      );
      expect(schedule.last.endingBalance, 0);
      expect(schedule.first.openingBalance, closeTo(85000, 0.01));
    },
  );

  test(
    'A6: abono a capital con cuotas vencidas se bloquea sin tocar nada (atomicidad)',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      final saleId = await harness.createFinancedSale(
        saleDate: DateTime(
          anchor.year,
          anchor.month - 2,
          anchor.day,
        ).subtract(const Duration(days: 5)),
        installmentCount: 6,
      );
      final baselinePayments = await paymentsCount(harness);
      final before = await snapshot(harness, saleId);

      await expectLater(
        payCapital(harness, saleId, 5000),
        throwsA(isA<StateError>()),
      );

      final after = await snapshot(harness, saleId);
      expect(await paymentsCount(harness), baselinePayments);
      expect(
        after['saldo_pendiente'],
        closeTo(before['saldo_pendiente']!, 0.001),
      );
      expect(after['capital_total'], closeTo(before['capital_total']!, 0.001));
    },
  );

  test(
    'A4: sin cuotas futuras donde reflejarlo, el abono se cancela COMPLETO (no hay dinero huerfano)',
    () async {
      final harness = await PaymentApplicationTestHarness.create();
      addTearDown(harness.dispose);

      // Venta de 1 cuota que vence HOY: no esta vencida (date(vencimiento) <
      // date(hoy) es falso) pero tampoco es futura, de modo que el recalculo no
      // tiene donde aplicar el capital.
      final saleId = await harness.createFinancedSale(
        saleDate: DateTime(anchor.year, anchor.month - 1, anchor.day),
        installmentCount: 1,
      );
      final baselinePayments = await paymentsCount(harness);
      final before = await snapshot(harness, saleId);

      await expectLater(
        payCapital(harness, saleId, 5000),
        throwsA(isA<StateError>()),
      );

      // La transaccion revierte: ni pago registrado ni deuda alterada.
      final after = await snapshot(harness, saleId);
      expect(
        await paymentsCount(harness),
        baselinePayments,
        reason: 'no puede quedar un pago sin efecto financiero',
      );
      expect(
        after['saldo_pendiente'],
        closeTo(before['saldo_pendiente']!, 0.001),
      );
      expect(after['capital_total'], closeTo(before['capital_total']!, 0.001));
    },
  );
}
