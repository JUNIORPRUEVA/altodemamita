import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/settings/presentation/documentation_page.dart';

void main() {
  testWidgets('documentation search filters sections and entries', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DocumentationPage()));

    expect(find.text('Registrar un cliente nuevo'), findsOneWidget);
    expect(find.text('Respaldo y recuperacion'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'backup');
    await tester.pumpAndSettle();

    expect(find.text('Respaldo y recuperacion'), findsOneWidget);
    expect(find.text('Registrar un cliente nuevo'), findsNothing);
  });
}
