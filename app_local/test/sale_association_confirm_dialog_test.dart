import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/sales/domain/sale_correction.dart';
import 'package:sistema_solares/features/sales/presentation/sale_association_confirm_dialog.dart';

/// FASE 03B — el cambio de cliente/solar exige motivo y muestra el impacto real
/// devuelto por el backend; si el backend no autoriza, no se puede confirmar.
void main() {
  SaleCorrectionPreview preview({
    bool allowed = true,
    String message = 'Cambio permitido.',
    int activePayments = 0,
  }) {
    return SaleCorrectionPreview(
      allowed: allowed,
      code: allowed ? 'OK' : 'LOT_ALREADY_ASSIGNED',
      message: message,
      saleVersion: 9,
      impact: SaleCorrectionImpact(
        statusBefore: 'activa',
        statusAfter: 'activa',
        totalBefore: 50000,
        totalAfter: 50000,
        balanceBefore: 40000,
        balanceAfter: 40000,
        initialPaidBefore: 10000,
        initialPaidAfter: 10000,
        financedBefore: 40000,
        financedAfter: 40000,
        installmentCountBefore: 4,
        installmentCountAfter: 4,
        activePayments: activePayments,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required SaleCorrectionPreview result,
    required Future<Map<String, dynamic>> Function(String, SaleCorrectionPreview)
    apply,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => SaleAssociationConfirmDialog(
                    title: 'Cambiar solar',
                    currentLabel: 'A-01',
                    targetLabel: 'B-07',
                    loadPreview: () async => result,
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

  testWidgets('muestra la asociación actual y la nueva con el impacto', (
    tester,
  ) async {
    await pump(
      tester,
      result: preview(),
      apply: (reason, preview) async => <String, dynamic>{},
    );

    expect(find.textContaining('Actual'), findsOneWidget);
    expect(find.textContaining('A-01'), findsOneWidget);
    expect(find.textContaining('B-07'), findsOneWidget);
    expect(find.textContaining('Cuotas activas'), findsOneWidget);
    expect(find.textContaining('4 → 4'), findsOneWidget);
  });

  testWidgets('exige motivo antes de confirmar', (tester) async {
    await pump(
      tester,
      result: preview(),
      apply: (reason, preview) async => <String, dynamic>{},
    );

    final confirm = find.widgetWithText(FilledButton, 'Cambiar solar');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Solar mal capturado');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('bloquea cuando el backend rechaza el solar ocupado', (
    tester,
  ) async {
    await pump(
      tester,
      result: preview(
        allowed: false,
        message: 'Ese solar ya pertenece a otra venta activa.',
      ),
      apply: (reason, preview) async => <String, dynamic>{},
    );

    expect(
      find.textContaining('ya pertenece a otra venta activa'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'Intento de cambio');
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'Cambiar solar');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });

  testWidgets('avisa de pagos activos en el impacto', (tester) async {
    await pump(
      tester,
      result: preview(activePayments: 2),
      apply: (reason, preview) async => <String, dynamic>{},
    );
    expect(find.textContaining('Pagos activos'), findsOneWidget);
    expect(find.textContaining('bloquea importes y cliente'), findsOneWidget);
  });
}
