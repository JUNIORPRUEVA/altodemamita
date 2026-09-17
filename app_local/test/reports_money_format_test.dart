import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/core/utils/dominican_formatters.dart';
import 'package:sistema_solares/features/dashboard/presentation/widgets/money_metric_text.dart';

/// Formato contable RD exigido por el propietario:
/// `1000 -> 1,000.00`, `25350.5 -> 25,350.50`, `1250000 -> 1,250,000.00`.
void main() {
  group('formatRdCurrency (helper central)', () {
    test('cero', () {
      expect(formatRdCurrency(0), '0.00');
    });

    test('mil', () {
      expect(formatRdCurrency(1000), '1,000.00');
    });

    test('un decimal se completa a dos', () {
      expect(formatRdCurrency(25350.5), '25,350.50');
    });

    test('millón con separadores', () {
      expect(formatRdCurrency(1250000), '1,250,000.00');
    });

    test('centavos exactos a dos decimales', () {
      expect(formatRdCurrency(1234.567), '1,234.57');
      expect(formatRdCurrency(0.5), '0.50');
    });

    test('valores no finitos no rompen la UI', () {
      expect(formatRdCurrency(double.nan), '0.00');
      expect(formatRdCurrency(double.infinity), '0.00');
    });

    test('negativos conservan separador', () {
      expect(formatRdCurrency(-1000), '-1,000.00');
    });
  });

  group('MoneyMetricText.format (prefijo RD\$ preservado)', () {
    test('conserva el prefijo existente y no lo duplica', () {
      expect(MoneyMetricText.format(0), 'RD\$ 0.00');
      expect(MoneyMetricText.format(1000), 'RD\$ 1,000.00');
      expect(MoneyMetricText.format(25350.5), 'RD\$ 25,350.50');
      expect(MoneyMetricText.format(1250000), 'RD\$ 1,250,000.00');
    });
  });

  group('MoneyMetricText (widget)', () {
    testWidgets('la tarjeta muestra separadores de miles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 220, child: MoneyMetricText(amount: 1250000)),
            ),
          ),
        ),
      );

      expect(find.text('RD\$ 1,250,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('monto grande en ancho estrecho no desborda', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 120, child: MoneyMetricText(amount: 12500000)),
            ),
          ),
        ),
      );

      // El valor sigue visible y completo: FittedBox reduce, no recorta.
      expect(find.text('RD\$ 12,500,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('layout móvil de 320px sin overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: MoneyMetricText(amount: 1250000),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('layout desktop ancho mantiene el formato', (tester) async {
      tester.view.physicalSize = const Size(1280 * 1, 720 * 1);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: MoneyMetricText(amount: 25350.5),
            ),
          ),
        ),
      );

      expect(find.text('RD\$ 25,350.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
