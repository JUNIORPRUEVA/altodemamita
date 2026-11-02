import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_correction.dart';
import 'package:sistema_solares/features/sales/presentation/sale_correction_dialog.dart';

/// FASE 03 — el diálogo de venta muestra el impacto, exige motivo y bloquea la
/// confirmación cuando el backend no autoriza la corrección.
void main() {
  SaleCorrectionPreview preview({
    bool allowed = true,
    String message = 'Corrección permitida.',
    String statusAfter = 'activa',
  }) {
    return SaleCorrectionPreview(
      allowed: allowed,
      code: allowed ? 'OK' : 'SALE_HAS_ACTIVE_PAYMENTS',
      message: message,
      saleVersion: 4,
      impact: SaleCorrectionImpact(
        statusBefore: 'apartado',
        statusAfter: statusAfter,
        totalBefore: 50000,
        totalAfter: 60000,
        balanceBefore: 40000,
        balanceAfter: 45000,
        initialPaidBefore: 10000,
        initialPaidAfter: 15000,
        financedBefore: 40000,
        financedAfter: 45000,
        installmentCountBefore: 4,
        installmentCountAfter: 5,
        activePayments: 0,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required String action,
    required SaleCorrectionPreview result,
    required SaleCorrectionApplier apply,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => SaleCorrectionDialog(
                    action: action,
                    saleLabel: 'Cliente Demo — A-01',
                    currentTotal: 50000,
                    currentInitialPaid: 10000,
                    currentInstallmentCount: 4,
                    currentInterestRate: 0,
                    loadPreview:
                        ({
                          saleDate,
                          totalPrice,
                          initialPaidAmount,
                          installmentCount,
                          monthlyInterestRate,
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

  testWidgets('muestra el impacto del contrato antes/después', (tester) async {
    await pump(
      tester,
      action: SaleCorrectionAction.updateFinancing,
      result: preview(),
      apply: ({required reason, saleDate, totalPrice, initialPaidAmount, installmentCount, monthlyInterestRate}) async =>
          <String, dynamic>{},
    );

    expect(find.textContaining('Estado'), findsOneWidget);
    expect(find.textContaining('Financiado'), findsOneWidget);
    expect(find.textContaining('50,000.00'), findsWidgets);
    expect(find.textContaining('60,000.00'), findsWidgets);
    expect(find.textContaining('4 → 5'), findsOneWidget);
  });

  testWidgets('exige motivo antes de confirmar', (tester) async {
    await pump(
      tester,
      action: SaleCorrectionAction.cancel,
      result: preview(statusAfter: 'cancelada'),
      apply: ({required reason, saleDate, totalPrice, initialPaidAmount, installmentCount, monthlyInterestRate}) async =>
          <String, dynamic>{},
    );

    final confirm = find.widgetWithText(FilledButton, 'Cancelar venta');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'ab');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField).last,
      'Cliente desiste de la compra',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('bloquea la corrección cuando el backend la rechaza', (
    tester,
  ) async {
    await pump(
      tester,
      action: SaleCorrectionAction.updateFinancing,
      result: preview(
        allowed: false,
        message: 'La venta tiene pagos activos: anula los pagos antes de cambiar importes.',
      ),
      apply: ({required reason, saleDate, totalPrice, initialPaidAmount, installmentCount, monthlyInterestRate}) async =>
          <String, dynamic>{},
    );

    expect(
      find.textContaining('La venta tiene pagos activos'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Intento de reestructuración',
    );
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'Editar contrato');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });
}
