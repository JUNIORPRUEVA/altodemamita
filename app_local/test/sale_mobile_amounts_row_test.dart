import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/features/sales/presentation/widgets/sale_mobile_amounts_row.dart';

/// Montos usados en las pruebas (formato `RD$ 1,000.00` / `RD$ 200.00`).
const double _price = 1000;
const double _pending = 200;

const String _priceText = 'RD\$1,000.00';
const String _pendingText = 'RD\$200.00';

/// Ancho de fila que garantiza que ambos montos caben completos.
double _rowWidthForBoth() {
  final priceWidth = SaleMobileAmountsRow.amountWidth('Precio', _priceText);
  final pendingWidth = SaleMobileAmountsRow.amountWidth('Pend.', _pendingText);
  return priceWidth +
      SaleMobileAmountsRow.gap +
      pendingWidth +
      SaleMobileAmountsRow.chevronWidth +
      SaleMobileAmountsRow.gap +
      SaleMobileAmountsRow.minMetaWidth +
      40;
}

/// Ancho de fila donde "Precio" ya no cabe.
double _rowWidthForPendingOnly() => _rowWidthForBoth() - 80;

Future<void> _pump(WidgetTester tester, double width) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const SaleMobileAmountsRow(
              metaLabel: 'M12-S34',
              price: _price,
              pending: _pending,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SaleMobileAmountsRow', () {
    testWidgets('muestra Precio y Pendiente completos cuando caben', (
      tester,
    ) async {
      await _pump(tester, _rowWidthForBoth());

      expect(find.text('Precio'), findsOneWidget);
      expect(find.text('Pend.'), findsOneWidget);
      expect(find.text(_priceText), findsOneWidget);
      expect(find.text(_pendingText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'sin espacio oculta Precio y conserva el Pendiente completo',
      (tester) async {
        await _pump(tester, _rowWidthForPendingOnly());

        expect(find.text('Precio'), findsNothing);
        expect(find.text(_priceText), findsNothing);
        expect(find.text('Pend.'), findsOneWidget);
        expect(find.text(_pendingText), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('el monto nunca se recorta con puntos suspensivos', (
      tester,
    ) async {
      await _pump(tester, _rowWidthForBoth());

      final pendingText = tester.widget<Text>(find.text(_pendingText));
      expect(pendingText.overflow, isNull);
      expect(pendingText.maxLines, 1);
    });
  });
}
