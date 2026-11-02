import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/installments/domain/installment_correction.dart';
import 'package:sistema_solares/features/installments/presentation/installment_correction_dialog.dart';

/// FASE 02 — el dialogo muestra el impacto autoritativo, exige motivo y bloquea
/// la confirmacion cuando el backend no autoriza la correccion.
void main() {
  InstallmentCorrectionPreview preview({
    bool allowed = true,
    String message = 'Correccion permitida.',
    double principalAfter = 30000,
    int countAfter = 3,
  }) {
    return InstallmentCorrectionPreview(
      allowed: allowed,
      code: allowed ? 'OK' : 'INSTALLMENT_HAS_PAYMENTS',
      message: message,
      saleVersion: 7,
      impact: InstallmentCorrectionImpact(
        outstandingPrincipalBefore: 30000,
        outstandingPrincipalAfter: principalAfter,
        nextDueDateBefore: '2026-10-01T00:00:00.000Z',
        nextDueDateAfter: '2026-10-20T00:00:00.000Z',
        installmentCountBefore: 3,
        installmentCountAfter: countAfter,
        grossLateFeesBefore: 540,
        grossLateFeesAfter: 300,
        outstandingLateFeesBefore: 540,
        outstandingLateFeesAfter: 300,
        principalPreserved: principalAfter == 30000,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required String action,
    required InstallmentCorrectionPreview result,
    required InstallmentCorrectionApplier apply,
    DateTime? currentDueDate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => InstallmentCorrectionDialog(
                    action: action,
                    title: InstallmentCorrectionAction.label(action),
                    installmentNumber: 2,
                    currentDueDate: currentDueDate,
                    currentPrincipal: 10000,
                    currentInterest: 0,
                    loadPreview:
                        ({
                          dueDate,
                          principalAmount,
                          interestAmount,
                          installmentCount,
                          firstDueDate,
                        }) async => result,
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

  testWidgets('muestra capital, vencimiento y mora antes/despues', (
    tester,
  ) async {
    await pump(
      tester,
      action: InstallmentCorrectionAction.changeDueDate,
      result: preview(),
      apply: ({required reason, dueDate, principalAmount, interestAmount, installmentCount, firstDueDate}) async =>
          <String, dynamic>{},
    );

    expect(find.textContaining('Capital pendiente'), findsOneWidget);
    expect(find.textContaining('Proximo vencimiento'), findsOneWidget);
    expect(find.textContaining('Mora acumulada'), findsOneWidget);
    expect(find.textContaining('Cuotas activas'), findsOneWidget);
    expect(find.textContaining('3 → 3'), findsOneWidget);
  });

  testWidgets('exige motivo antes de confirmar', (tester) async {
    await pump(
      tester,
      action: InstallmentCorrectionAction.changeDueDate,
      result: preview(),
      apply: ({required reason, dueDate, principalAmount, interestAmount, installmentCount, firstDueDate}) async =>
          <String, dynamic>{},
    );

    final confirm = find.widgetWithText(FilledButton, 'Cambiar vencimiento');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField).first,
      'Vencimiento mal capturado',
    );
    await tester.pump();
    // Aun falta elegir la nueva fecha: el dialogo muestra el error al confirmar.
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('bloquea la accion cuando el backend la rechaza', (tester) async {
    await pump(
      tester,
      action: InstallmentCorrectionAction.changeDueDate,
      result: preview(
        allowed: false,
        message: 'Esta cuota ya tiene pagos aplicados.',
      ),
      apply: ({required reason, dueDate, principalAmount, interestAmount, installmentCount, firstDueDate}) async =>
          <String, dynamic>{},
    );

    expect(
      find.textContaining('Esta cuota ya tiene pagos aplicados'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'Intento de cambio');
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'Cambiar vencimiento');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });

  testWidgets('reprogramacion pide numero de cuotas', (tester) async {
    var applied = 0;
    await pump(
      tester,
      action: InstallmentCorrectionAction.reschedule,
      result: preview(countAfter: 12),
      apply: ({required reason, dueDate, principalAmount, interestAmount, installmentCount, firstDueDate}) async {
        applied += 1;
        expect(installmentCount, 12);
        return <String, dynamic>{};
      },
    );

    expect(find.textContaining('N. cuotas'), findsOneWidget);
    expect(find.textContaining('3 → 12'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).at(1),
      'Cliente solicito reprogramacion',
    );
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'Reprogramar cuotas');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(applied, 1);
  });
}
