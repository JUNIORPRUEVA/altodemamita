import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_owner/app/app_theme.dart';
import 'package:sistema_solares_owner/features/auth/login_page.dart';

void main() {
  testWidgets('owner app renders login before customer session', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: LoginPage(onLogin: (_, _) async {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Alto de Mamita'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
