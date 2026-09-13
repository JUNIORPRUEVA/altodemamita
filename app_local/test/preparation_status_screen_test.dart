import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/shared/widgets/preparation_status_screen.dart';

import 'helpers/responsive_test_harness.dart';

void main() {
  testWidgets('Windows desktop usa esta PC', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(testApp(const PreparationStatusScreen()));

    expect(find.text('Preparando Sistema Solares'), findsOneWidget);
    expect(
      find.textContaining('Estamos preparando la aplicación en esta PC.'),
      findsOneWidget,
    );
    expect(find.text('Cargando información...'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile/tablet/web copy usa este dispositivo', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(testApp(const PreparationStatusScreen()));

    expect(
      find.textContaining(
        'Estamos preparando la aplicación en este dispositivo.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('esta PC'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('no muestra textos tecnicos prohibidos', (tester) async {
    await tester.pumpWidget(testApp(const PreparationStatusScreen()));

    expect(find.textContaining('Cargando datos de la nube'), findsNothing);
    for (final term in _forbiddenVisibleTerms) {
      expect(
        find.textContaining(term, findRichText: true),
        findsNothing,
        reason: 'No debe mostrar "$term" al cliente.',
      );
    }
  });

  testWidgets('error muestra copy aprobado y permite reintentar', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      testApp(
        PreparationStatusScreen(
          status: PreparationStatus.error,
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('No pudimos terminar la preparación.'), findsOneWidget);
    expect(
      find.text('Verifica tu conexión e inténtalo nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Reintentar'));
    expect(retried, isTrue);
  });

  testWidgets('responsive sin overflow en anchos requeridos', (tester) async {
    const widths = <double>[320, 360, 375, 390, 412, 430, 600, 768, 1024, 1366];

    for (final width in widths) {
      useTestSize(tester, Size(width, width < 700 ? 720 : 768));
      await tester.pumpWidget(testApp(const PreparationStatusScreen()));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'No debe lanzar overflow/error en ancho $width.',
      );
    }
  });
}

const _forbiddenVisibleTerms = <String>[
  'Sincronizando',
  'Backend',
  'PostgreSQL',
  'SQLite',
  'IndexedDB',
  'Cloud',
  'API',
  'endpoint',
  'URL',
  'cache',
  'outbox',
  'fingerprint',
  'base de datos',
];
