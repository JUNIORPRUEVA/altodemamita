import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/shared/widgets/base_layout.dart';

void main() {
  testWidgets('BaseLayout muestra el contenido dentro del shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 900,
          height: 700,
          child: ShellLayoutScope(
            child: BaseLayout(
              title: 'Modulo',
              child: Center(child: Text('Contenido visible')),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Contenido visible'), findsOneWidget);
    expect(find.text('Modulo'), findsNothing);
  });

  testWidgets('BaseLayout standalone muestra titulo y contenido', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BaseLayout(
          title: 'Configuracion',
          child: Center(child: Text('Contenido standalone')),
        ),
      ),
    );

    expect(find.text('Configuracion'), findsWidgets);
    expect(find.text('Contenido standalone'), findsOneWidget);
  });
}
