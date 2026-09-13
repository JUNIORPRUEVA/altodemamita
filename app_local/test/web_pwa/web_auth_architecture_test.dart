import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login web no ofrece importar SQLite ni autenticacion local', () async {
    final source = await File(
      'lib/features/auth/presentation/login_screen.dart',
    ).readAsString();

    expect(source, isNot(contains('Importar base de Windows')));
    expect(source, isNot(contains('importa una copia')));
    expect(source, isNot(contains('Iniciar sesion local')));
    expect(source, isNot(contains('file_picker')));
  });

  test(
    'PWA autenticada no usa pantalla global de preparacion para sync',
    () async {
      final source = await File(
        'lib/app/navigation/app_shell.dart',
      ).readAsString();

      expect(
        source,
        isNot(contains("shared/widgets/preparation_status_screen.dart")),
      );
      expect(source, isNot(contains('_InitialCloudHydrationPage')));
      expect(source, isNot(contains('PreparationStatusScreen()')));
      expect(
        source,
        contains('ShellLayoutScope(child: _buildCurrentPage(resolvedModule))'),
      );
      expect(source, contains('unawaited(_syncManager.start())'));
    },
  );

  test('error de hidratacion/sync queda como retry no bloqueante', () async {
    final source = await File(
      'lib/app/navigation/app_shell.dart',
    ).readAsString();

    expect(source, contains('_NonBlockingSyncIssueBanner'));
    expect(source, contains("label: const Text('Reintentar')"));
    expect(
      source,
      contains('onRetry: () => unawaited(_syncManager.syncNow())'),
    );
    expect(source, isNot(contains('isInitialCloudHydration\n        ?')));
  });
}
