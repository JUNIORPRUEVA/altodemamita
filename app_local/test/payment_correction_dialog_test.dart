import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/payment_correction.dart';
import 'package:sistema_solares/features/payments/presentation/payment_correction_dialog.dart';

/// FASE 01C — el dialogo NO decide: refleja la autorizacion del backend y exige
/// motivo antes de aplicar cualquier correccion.
void main() {
  PaymentCorrectionPreview preview({
    bool allowed = true,
    String code = 'OK',
    String message = 'Reversion historica segura.',
  }) {
    return PaymentCorrectionPreview(
      allowed: allowed,
      code: code,
      message: message,
      requiresScheduleReconstruction: false,
      createsReplacementPayment: false,
      paymentId: 7,
      paymentType: 'cuota',
      paymentAmount: 15000,
      paymentVersion: 3,
      saleBalance: 10000,
      impact: const PaymentCorrectionImpact(
        amountRestoredToBalance: 15000,
        saleBalanceBefore: 10000,
        saleBalanceAfter: 25000,
        paidAmountBefore: 15000,
        paidAmountAfter: 0,
        becomesOpen: true,
        dateChange: false,
        replacesPayment: false,
        lateFeeNote: null,
        estimated: true,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required PaymentCorrectionPreview result,
    required CorrectionApplier apply,
    String action = PaymentCorrectionAction.annul,
    List<Map<String, Object?>>? calls,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => PaymentCorrectionDialog(
                    action: action,
                    clientName: 'Cliente Demo',
                    concept: 'Cuota 1',
                    amountLabel: 'RD\$ 15,000.00',
                    paymentDateLabel: '05/10/2026',
                    loadPreview: ({newDate, newAmount}) async {
                      calls?.add({
                        'newDate': newDate?.toIso8601String(),
                        'newAmount': newAmount,
                      });
                      return result;
                    },
                    apply: apply,
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el impacto autoritativo y exige motivo', (tester) async {
    var applied = 0;
    await pump(
      tester,
      result: preview(),
      apply: ({required reason, newDate, newAmount}) async {
        applied += 1;
        return <String, dynamic>{};
      },
    );

    expect(find.textContaining('Saldo de la venta'), findsOneWidget);
    expect(find.textContaining('RD\$ 10,000.00'), findsWidgets);

    final confirm = find.widgetWithText(FilledButton, 'Anular pago');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'ab');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField).first,
      'Pago historico registrado por error',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(applied, 1);
  });

  testWidgets('bloquea la accion cuando el backend no la autoriza', (
    tester,
  ) async {
    await pump(
      tester,
      result: preview(
        allowed: false,
        code: 'ONLY_LATEST_PAYMENT_CAN_BE_ANNULLED',
        message: 'El pago tiene movimientos posteriores que lo impiden.',
      ),
      apply: ({required reason, newDate, newAmount}) async =>
          <String, dynamic>{},
    );

    expect(
      find.textContaining('El pago tiene movimientos posteriores'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField).first,
      'Intento de anulacion',
    );
    await tester.pump();

    final confirm = find.widgetWithText(FilledButton, 'Anular pago');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });

  testWidgets(
    'la correccion de monto recalcula el impacto con el nuevo monto',
    (tester) async {
      final calls = <Map<String, Object?>>[];
      await pump(
        tester,
        action: PaymentCorrectionAction.correctAmount,
        result: preview(),
        calls: calls,
        apply: ({required reason, newDate, newAmount}) async =>
            <String, dynamic>{},
      );

      expect(
        find.textContaining('Se registra un pago de reemplazo'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, '12000');
      await tester.pump();
      await tester.ensureVisible(find.text('Calcular impacto'));
      await tester.tap(find.text('Calcular impacto'));
      await tester.pumpAndSettle();

      expect(calls.length, greaterThanOrEqualTo(2));
      expect(calls.last['newAmount'], 12000.0);
    },
  );
}
