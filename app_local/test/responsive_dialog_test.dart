import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/responsive/responsive_dialog.dart';

import 'helpers/responsive_test_harness.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _closeDialog(WidgetTester tester) async {
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
}

Widget _host({
  ResponsiveDialogMode? mobileMode,
  ResponsiveDialogMode? desktopMode,
  double contentHeight = 0,
}) {
  return Builder(
    builder: (context) {
      return Center(
        child: TextButton(
          onPressed: () {
            showResponsiveDialog<void>(
              context: context,
              mobileMode: mobileMode,
              desktopMode: desktopMode,
              builder: (_) => contentHeight > 0
                  ? SizedBox(height: contentHeight)
                  : const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('contenido-dialogo'),
                    ),
            );
          },
          child: const Text('abrir'),
        ),
      );
    },
  );
}

void main() {
  group('showResponsiveDialog', () {
    testWidgets('en Windows (1366) usa dialogo centrado, no pantalla completa',
        (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(testApp(_host()));
      await _openDialog(tester);

      expect(find.text('contenido-dialogo'), findsOneWidget);

      final frame = tester.widget<ResponsiveDialogFrame>(
        find.byType(ResponsiveDialogFrame),
      );
      expect(frame.mode, ResponsiveDialogMode.dialog);
    });

    testWidgets('en movil usa pantalla completa por defecto', (tester) async {
      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(testApp(_host()));
      await _openDialog(tester);

      expect(find.text('contenido-dialogo'), findsOneWidget);

      final frame = tester.widget<ResponsiveDialogFrame>(
        find.byType(ResponsiveDialogFrame),
      );
      expect(frame.mode, ResponsiveDialogMode.fullScreen);
    });

    testWidgets('en movil respeta el modo hoja inferior cuando se solicita',
        (tester) async {
      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(_host(mobileMode: ResponsiveDialogMode.sheet)),
      );
      await _openDialog(tester);

      expect(find.text('contenido-dialogo'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ResponsiveDialogFrame), findsNothing);
    });

    testWidgets('el dialogo nunca excede la pantalla ni desborda en movil',
        (tester) async {
      useTestSize(tester, TestViewSizes.iphoneSe);
      await tester.pumpWidget(
        testApp(
          _host(
            mobileMode: ResponsiveDialogMode.dialog,
            contentHeight: 2000,
          ),
        ),
      );

      for (final size in [
        TestViewSizes.iphoneSe,
        TestViewSizes.androidCompact,
        TestViewSizes.iphone12,
        TestViewSizes.iphoneProMax,
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();

        await _openDialog(tester);

        final frameSize = tester.getSize(
          find.byKey(ResponsiveDialogFrame.surfaceKey),
        );
        expect(
          frameSize.width,
          lessThanOrEqualTo(size.width),
          reason: 'tamano ${size.width}x${size.height}',
        );
        expect(
          frameSize.height,
          lessThanOrEqualTo(size.height),
          reason: 'tamano ${size.width}x${size.height}',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'tamano ${size.width}x${size.height} sin overflow',
        );

        await _closeDialog(tester);
      }
    });

    testWidgets('el dialogo cede espacio al teclado movil', (tester) async {
      const size = Size(390, 844);
      const keyboard = 320.0;

      useTestSize(tester, size);
      useTestKeyboard(tester, keyboard);

      await tester.pumpWidget(
        testApp(
          _host(
            mobileMode: ResponsiveDialogMode.dialog,
            contentHeight: 2000,
          ),
        ),
      );
      await _openDialog(tester);

      final frameSize = tester.getSize(
        find.byKey(ResponsiveDialogFrame.surfaceKey),
      );
      expect(
        frameSize.height,
        lessThanOrEqualTo(size.height - keyboard),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('el dialogo respeta el safe area de iPhone', (tester) async {
      useTestSize(tester, const Size(390, 844));
      useTestSafeArea(tester, top: 47, bottom: 34);

      await tester.pumpWidget(
        testApp(
          _host(
            mobileMode: ResponsiveDialogMode.dialog,
            contentHeight: 2000,
          ),
        ),
      );
      await _openDialog(tester);

      final frame = tester.getRect(find.byKey(ResponsiveDialogFrame.surfaceKey));
      expect(frame.top, greaterThanOrEqualTo(47));
      expect(frame.bottom, lessThanOrEqualTo(844 - 34));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cierra sin error tocando la barrera', (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(testApp(_host()));
      await _openDialog(tester);

      await _closeDialog(tester);

      expect(find.text('contenido-dialogo'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('showResponsiveConfirmDialog', () {
    testWidgets('devuelve true al confirmar en movil', (tester) async {
      bool? result;

      useTestSize(tester, TestViewSizes.androidCompact);

      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showResponsiveConfirmDialog(
                    context: context,
                    title: 'Anular pago',
                    message: 'Esta accion no se puede deshacer.',
                    confirmLabel: 'Anular',
                    destructive: true,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Anular pago'), findsOneWidget);
      expect(find.text('Esta accion no se puede deshacer.'), findsOneWidget);

      await tester.tap(find.text('Anular'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('devuelve false al cancelar', (tester) async {
      bool? result;

      useTestSize(tester, TestViewSizes.desktop);

      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showResponsiveConfirmDialog(
                    context: context,
                    title: 'Confirmar',
                    message: 'Mensaje',
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('ResponsiveDialogFrame', () {
    testWidgets('fullScreen ocupa toda la pantalla disponible', (tester) async {
      useTestSize(tester, TestViewSizes.iphone12);

      await tester.pumpWidget(
        testApp(
          ResponsiveDialogFrame(
            mode: ResponsiveDialogMode.fullScreen,
            child: (_) => const SizedBox(width: 280, height: 200),
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(ResponsiveDialogFrame.fullScreenKey));
      expect(rect.width, 390);
      expect(rect.height, 844);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dialog en 320 se mantiene dentro de la pantalla',
        (tester) async {
      useTestSize(tester, TestViewSizes.iphoneSe);

      await tester.pumpWidget(
        testApp(
          ResponsiveDialogFrame(
            mode: ResponsiveDialogMode.dialog,
            child: (_) => const SizedBox(width: 900, height: 900),
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(ResponsiveDialogFrame.surfaceKey));
      expect(rect.width, lessThanOrEqualTo(320));
      expect(rect.height, lessThanOrEqualTo(568));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });
}
