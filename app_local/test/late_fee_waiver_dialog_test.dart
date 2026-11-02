import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/authoritative_late_fee.dart';
import 'package:sistema_solares/features/payments/presentation/late_fee_waiver_dialog.dart';

/// FASE 01B — el OWNER debe ver el IMPACTO FINANCIERO y el motivo es
/// obligatorio antes de condonar mora.
void main() {
  const summary = AuthoritativeLateFeeSummary(
    saleId: 'sale-1',
    saleSyncId: 'sync-1',
    asOfDate: '2026-11-02T00:00:00.000Z',
    policyEnabled: true,
    grossLateFees: 1500,
    collectedLateFees: 200,
    waivedLateFees: 0,
    outstandingLateFees: 1300,
    installments: <AuthoritativeLateFeeInstallment>[],
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    ValueChanged<({String reason, double? waivedAmount})>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result =
                      await showDialog<({String reason, double? waivedAmount})>(
                        context: context,
                        builder: (_) => const LateFeeWaiverDialog(
                          clientName: 'Cliente Demo',
                          saleLabel: 'M-01',
                          summary: summary,
                        ),
                      );
                  if (result != null) onResult?.call(result);
                },
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

  testWidgets('muestra la mora exigible y el impacto de la condonacion', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('Condonar mora'), findsWidgets);
    expect(find.textContaining('Mora exigible actual'), findsOneWidget);
    expect(find.textContaining('Exigible despues de condonar'), findsOneWidget);
    // 1300.00 con separador de miles dominicano.
    expect(find.textContaining('1,300.00'), findsWidgets);
  });

  testWidgets('no permite confirmar sin motivo', (tester) async {
    await pumpDialog(tester);

    final confirm = find.widgetWithText(FilledButton, 'Condonar mora');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'ab');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField).first,
      'acuerdo comercial con el cliente',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('condonacion PARCIAL: muestra el monto y calcula el resto', (
    tester,
  ) async {
    ({String reason, double? waivedAmount})? result;
    await pumpDialog(tester, onResult: (value) => result = value);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.textContaining('Se condonara (parcial)'), findsOneWidget);

    final confirm = find.widgetWithText(FilledButton, 'Condonar mora');
    // Con el modo parcial activo, el primer campo es el MONTO y el segundo el
    // motivo.
    await tester.enterText(
      find.byType(TextField).at(1),
      'acuerdo parcial con el cliente',
    );
    await tester.pump();
    // Sin monto, la confirmacion sigue bloqueada.
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '500');
    await tester.pumpAndSettle();
    // 1300 - 500 = 800 exigible despues.
    expect(find.textContaining('800.00'), findsWidgets);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result?.waivedAmount, 500);
    expect(result?.reason, contains('acuerdo parcial'));
  });

  testWidgets('condonacion TOTAL: no envia monto parcial', (tester) async {
    ({String reason, double? waivedAmount})? result;
    await pumpDialog(tester, onResult: (value) => result = value);

    await tester.enterText(
      find.byType(TextField).first,
      'condonacion total aprobada',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Condonar mora'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result?.waivedAmount, isNull);
  });
}
