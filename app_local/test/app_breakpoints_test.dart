import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/responsive/app_breakpoints.dart';

import 'helpers/responsive_test_harness.dart';

void main() {
  group('AppBreakpoints.sizeFor', () {
    test('clasifica cada limite exactamente una sola vez', () {
      expect(AppBreakpoints.sizeFor(0), AppWindowSize.mobileCompact);
      expect(AppBreakpoints.sizeFor(319), AppWindowSize.mobileCompact);
      expect(AppBreakpoints.sizeFor(359.99), AppWindowSize.mobileCompact);
      expect(AppBreakpoints.sizeFor(360), AppWindowSize.mobile);
      expect(AppBreakpoints.sizeFor(599.99), AppWindowSize.mobile);
      expect(AppBreakpoints.sizeFor(600), AppWindowSize.tablet);
      expect(AppBreakpoints.sizeFor(1023.99), AppWindowSize.tablet);
      expect(AppBreakpoints.sizeFor(1024), AppWindowSize.desktop);
      expect(AppBreakpoints.sizeFor(1439.99), AppWindowSize.desktop);
      expect(AppBreakpoints.sizeFor(1440), AppWindowSize.wideDesktop);
      expect(AppBreakpoints.sizeFor(3840), AppWindowSize.wideDesktop);
    });

    test('cubre todos los anchos exigidos por la especificacion', () {
      for (final width in TestViewSizes.requiredWidths) {
        expect(
          () => AppBreakpoints.sizeFor(width),
          returnsNormally,
          reason: 'ancho requerido $width',
        );
      }
    });
  });

  group('AppBreakpoints predicates', () {
    test('isMobileWidth solo para anchos menores a 600', () {
      expect(AppBreakpoints.isMobileWidth(320), isTrue);
      expect(AppBreakpoints.isMobileWidth(430), isTrue);
      expect(AppBreakpoints.isMobileWidth(599.99), isTrue);
      expect(AppBreakpoints.isMobileWidth(600), isFalse);
      expect(AppBreakpoints.isMobileWidth(1024), isFalse);
    });

    test('isTabletWidth solo para el rango 600..1023', () {
      expect(AppBreakpoints.isTabletWidth(599.99), isFalse);
      expect(AppBreakpoints.isTabletWidth(600), isTrue);
      expect(AppBreakpoints.isTabletWidth(768), isTrue);
      expect(AppBreakpoints.isTabletWidth(1023.99), isTrue);
      expect(AppBreakpoints.isTabletWidth(1024), isFalse);
    });

    test('isDesktopWidth para 1024 en adelante', () {
      expect(AppBreakpoints.isDesktopWidth(1023.99), isFalse);
      expect(AppBreakpoints.isDesktopWidth(1024), isTrue);
      expect(AppBreakpoints.isDesktopWidth(1366), isTrue);
      expect(AppBreakpoints.isDesktopWidth(1920), isTrue);
    });

    test('las tres clasificaciones son mutuamente excluyentes y exhaustivas',
        () {
      for (final width in [
        0.0,
        320.0,
        360.0,
        390.0,
        430.0,
        599.99,
        600.0,
        768.0,
        1023.99,
        1024.0,
        1366.0,
        1920.0,
      ]) {
        final mobile = AppBreakpoints.isMobileWidth(width);
        final tablet = AppBreakpoints.isTabletWidth(width);
        final desktop = AppBreakpoints.isDesktopWidth(width);

        expect(
          [mobile, tablet, desktop].where((value) => value).length,
          1,
          reason: 'el ancho $width debe caer en exactamente una categoria',
        );
      }
    });
  });

  group('AppBreakpoints helpers de contexto', () {
    testWidgets('of() y los helpers leen el MediaQuery real', (tester) async {
      AppWindowSize? observed;
      bool? mobile;
      bool? tablet;
      bool? desktop;
      bool? compactNav;

      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) {
              observed = AppBreakpoints.of(context);
              mobile = AppBreakpoints.isMobile(context);
              tablet = AppBreakpoints.isTablet(context);
              desktop = AppBreakpoints.isDesktop(context);
              compactNav = AppBreakpoints.usesCompactNavigation(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(observed, AppWindowSize.mobile);
      expect(mobile, isTrue);
      expect(tablet, isFalse);
      expect(desktop, isFalse);
      expect(compactNav, isTrue);
    });

    testWidgets('en 1366 no se usa navegacion compacta', (tester) async {
      bool? compactNav;

      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) {
              compactNav = AppBreakpoints.usesCompactNavigation(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(compactNav, isFalse);
    });
  });
}
