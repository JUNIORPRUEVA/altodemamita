import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_owner/app/app_theme.dart';
import 'package:sistema_solares_owner/app/app_shell.dart';
import 'package:sistema_solares_owner/core/services/api_client.dart';

void main() {
  testWidgets('owner app opens directly on Resumen shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: AppShell(
          session: const AuthSession(
            accessToken: 'jwt-owner',
            userName: 'Dueño',
            email: '',
          ),
          onLogout: () async {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Resumen'), findsWidgets);
    expect(find.text('Correo'), findsNothing);
    expect(find.text('Contrasena'), findsNothing);
    expect(find.text('Entrar'), findsNothing);
  });
}
