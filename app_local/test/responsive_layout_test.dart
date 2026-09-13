import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/responsive/app_breakpoints.dart';
import 'package:sistema_solares/core/responsive/responsive_layout.dart';
import 'package:sistema_solares/core/responsive/responsive_page.dart';

import 'helpers/responsive_test_harness.dart';

void main() {
  group('ResponsiveLayout', () {
    testWidgets('en Windows (1366) devuelve EXACTAMENTE la rama desktop',
        (tester) async {
      var desktopBuilds = 0;
      var mobileBuilds = 0;

      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(
        testApp(
          ResponsiveLayout(
            desktop: (_) {
              desktopBuilds += 1;
              return const Text('DESKTOP');
            },
            mobile: (_) {
              mobileBuilds += 1;
              return const Text('MOBILE');
            },
          ),
        ),
      );

      expect(find.text('DESKTOP'), findsOneWidget);
      expect(find.text('MOBILE'), findsNothing);
      expect(desktopBuilds, 1);
      expect(mobileBuilds, 0);
    });

    testWidgets('en 1920 (wideDesktop) tambien usa la rama desktop',
        (tester) async {
      useTestSize(tester, TestViewSizes.wideDesktop);
      await tester.pumpWidget(
        testApp(
          ResponsiveLayout(
            desktop: (_) => const Text('DESKTOP'),
            mobile: (_) => const Text('MOBILE'),
          ),
        ),
      );

      expect(find.text('DESKTOP'), findsOneWidget);
    });

    testWidgets('en 1024 (limite desktop) usa la rama desktop', (tester) async {
      useTestSize(tester, TestViewSizes.desktopSmall);
      await tester.pumpWidget(
        testApp(
          ResponsiveLayout(
            desktop: (_) => const Text('DESKTOP'),
            mobile: (_) => const Text('MOBILE'),
          ),
        ),
      );

      expect(find.text('DESKTOP'), findsOneWidget);
    });

    testWidgets('en movil usa la rama mobile', (tester) async {
      useTestSize(tester, TestViewSizes.iphoneSe);
      await tester.pumpWidget(
        testApp(
          ResponsiveLayout(
            desktop: (_) => const Text('DESKTOP'),
            mobile: (_) => const Text('MOBILE'),
          ),
        ),
      );

      for (final size in [
        TestViewSizes.iphoneSe,
        TestViewSizes.androidCompact,
        TestViewSizes.iphone12,
        TestViewSizes.androidLarge,
        TestViewSizes.iphoneProMax,
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();

        expect(
          find.text('MOBILE'),
          findsOneWidget,
          reason: 'tamano ${size.width}x${size.height}',
        );
      }
    });

    testWidgets('en tableta usa mobile cuando no hay rama tablet',
        (tester) async {
      useTestSize(tester, TestViewSizes.tabletPortrait);
      await tester.pumpWidget(
        testApp(
          ResponsiveLayout(
            desktop: (_) => const Text('DESKTOP'),
            mobile: (_) => const Text('MOBILE'),
          ),
        ),
      );

      expect(find.text('MOBILE'), findsOneWidget);
    });

    testWidgets('en tableta usa la rama tablet cuando existe', (tester) async {
      useTestSize(tester, TestViewSizes.tabletPortrait);
      await tester.pumpWidget(
        testApp(
          ResponsiveLayout(
            desktop: (_) => const Text('DESKTOP'),
            tablet: (_) => const Text('TABLET'),
            mobile: (_) => const Text('MOBILE'),
          ),
        ),
      );

      expect(find.text('TABLET'), findsOneWidget);
    });
  });

  group('ResponsiveBuilder', () {
    testWidgets('expone la clasificacion actual', (tester) async {
      final observed = <AppWindowSize>[];

      useTestSize(tester, TestViewSizes.iphoneProMax);
      await tester.pumpWidget(
        testApp(
          ResponsiveBuilder(
            builder: (context, size) {
              observed.add(size);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(observed, [AppWindowSize.mobile]);
    });
  });

  group('ResponsiveContentBox', () {
    testWidgets('limita el ancho y no se desborda en movil', (tester) async {
      useTestSize(tester, TestViewSizes.androidCompact);
      await tester.pumpWidget(
        testApp(
          const ResponsiveContentBox(
            maxWidth: 720,
            child: SizedBox(width: double.infinity, height: 24),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(ResponsiveContentBox));
      expect(size.width, lessThanOrEqualTo(360));
    });

    testWidgets('centra el contenido en pantallas anchas', (tester) async {
      useTestSize(tester, TestViewSizes.wideDesktop);
      await tester.pumpWidget(
        testApp(
          const ResponsiveContentBox(
            maxWidth: 720,
            child: SizedBox(width: 100, height: 24),
          ),
        ),
      );

      final box = tester.getRect(find.byType(ResponsiveContentBox));
      final child = tester.getRect(
        find
            .descendant(
              of: find.byType(ResponsiveContentBox),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      expect(box.width, 1920);
      expect(child.width, lessThanOrEqualTo(720));
      // Centrado horizontalmente.
      expect(
        (child.left - (box.left + (box.width - child.width) / 2)).abs(),
        lessThan(1),
      );
    });
  });

  group('ResponsivePagePadding', () {
    testWidgets('usa el padding desktop existente en 1366', (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(
        testApp(
          const ResponsivePagePadding(
            desktopPadding: 16,
            mobilePadding: 12,
            applySafeArea: false,
            child: SizedBox(width: 100, height: 20),
          ),
        ),
      );

      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(ResponsivePagePadding),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, const EdgeInsets.all(16));
    });

    testWidgets('usa padding movil en 390', (tester) async {
      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(
          const ResponsivePagePadding(
            desktopPadding: 16,
            mobilePadding: 12,
            applySafeArea: false,
            child: SizedBox(width: 100, height: 20),
          ),
        ),
      );

      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(ResponsivePagePadding),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, const EdgeInsets.all(12));
    });

    testWidgets('no produce overflow en ningun tamano requerido',
        (tester) async {
      useTestSize(tester, const Size(320, 800));
      await tester.pumpWidget(
        testApp(
          const ResponsivePagePadding(
            child: SizedBox(width: double.infinity, height: 40),
          ),
        ),
      );

      for (final width in TestViewSizes.requiredWidths) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho $width no debe desbordarse',
        );
      }
    });
  });

  group('ResponsiveFormContainer', () {
    testWidgets('ocupa todo el ancho en movil', (tester) async {
      useTestSize(tester, TestViewSizes.androidCompact);
      await tester.pumpWidget(
        testApp(
          const ResponsiveFormContainer(child: SizedBox(height: 40)),
        ),
      );

      final rect = tester.getRect(find.byType(ResponsiveFormContainer));
      expect(rect.width, 360);
    });

    testWidgets('limita el ancho en escritorio', (tester) async {
      useTestSize(tester, TestViewSizes.wideDesktop);
      await tester.pumpWidget(
        testApp(
          const ResponsiveFormContainer(
            maxWidth: 720,
            child: SizedBox(height: 40),
          ),
        ),
      );

      final inner = tester.getSize(
        find
            .descendant(
              of: find.byType(ResponsiveFormContainer),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(inner.width, lessThanOrEqualTo(720));
    });
  });

  group('ResponsiveCardGrid', () {
    int columnsAt(WidgetTester tester) {
      final grid = tester.widget<ResponsiveCardGrid>(
        find.byType(ResponsiveCardGrid),
      );
      final boxes = find
          .descendant(
            of: find.byType(ResponsiveCardGrid),
            matching: find.byType(SizedBox),
          )
          .evaluate()
          .toList();

      final firstWidth = (boxes.first.renderObject as RenderBox).size.width;
      final totalWidth = tester.getSize(find.byType(ResponsiveCardGrid)).width;

      return ((totalWidth + grid.spacing) / (firstWidth + grid.spacing)).round();
    }

    testWidgets('usa una columna en movil', (tester) async {
      useTestSize(tester, TestViewSizes.androidCompact);
      await tester.pumpWidget(
        testApp(
          const ResponsiveCardGrid(
            children: [
              SizedBox(height: 60),
              SizedBox(height: 60),
              SizedBox(height: 60),
            ],
          ),
        ),
      );

      expect(columnsAt(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('usa dos columnas en tableta', (tester) async {
      useTestSize(tester, TestViewSizes.tabletPortrait);
      await tester.pumpWidget(
        testApp(
          const ResponsiveCardGrid(
            children: [
              SizedBox(height: 60),
              SizedBox(height: 60),
              SizedBox(height: 60),
            ],
          ),
        ),
      );

      expect(columnsAt(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('usa tres columnas en escritorio', (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(
        testApp(
          const ResponsiveCardGrid(
            children: [
              SizedBox(height: 60),
              SizedBox(height: 60),
              SizedBox(height: 60),
            ],
          ),
        ),
      );

      expect(columnsAt(tester), 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nunca usa mas columnas de las que caben por ancho minimo',
        (tester) async {
      useTestSize(tester, const Size(600, 800));
      await tester.pumpWidget(
        testApp(
          const ResponsiveCardGrid(
            minItemWidth: 400,
            children: [
              SizedBox(height: 60),
              SizedBox(height: 60),
            ],
          ),
        ),
      );

      expect(columnsAt(tester), 1);
    });

    testWidgets('no se desborda en ningun tamano requerido', (tester) async {
      useTestSize(tester, const Size(320, 800));
      await tester.pumpWidget(
        testApp(
          const ResponsiveCardGrid(
            children: [
              SizedBox(height: 40),
              SizedBox(height: 40),
              SizedBox(height: 40),
              SizedBox(height: 40),
            ],
          ),
        ),
      );

      for (final width in TestViewSizes.requiredWidths) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho $width no debe desbordarse',
        );
      }
    });
  });
}
