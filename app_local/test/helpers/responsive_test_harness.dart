import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tamaños de pantalla reales requeridos por la especificación PWA.
///
/// Se incluyen los tamaños de mayor prioridad:
/// 360x800, 390x844, 412x915 y 430x932.
class TestViewSizes {
  const TestViewSizes._();

  static const Size iphoneSe = Size(320, 568);
  static const Size androidCompact = Size(360, 800);
  static const Size iphone12 = Size(390, 844);
  static const Size androidLarge = Size(412, 915);
  static const Size iphoneProMax = Size(430, 932);
  static const Size tabletPortrait = Size(768, 1024);
  static const Size desktopSmall = Size(1024, 768);
  static const Size desktop = Size(1366, 768);
  static const Size wideDesktop = Size(1920, 1080);

  /// Todos los anchos exigidos por la especificación de pruebas.
  static const List<double> requiredWidths = [
    320,
    360,
    375,
    390,
    412,
    430,
    768,
    1024,
    1366,
    1920,
  ];
}

/// Ajusta la ventana de prueba a [size] con densidad 1:1.
///
/// Se modifica la vista real (no un `MediaQuery` inyectado) por dos razones:
/// - Las rutas de diálogo/hoja se insertan en el `Overlay` del `Navigator`,
///   por encima del árbol de widgets, y por tanto ignoran cualquier
///   `MediaQuery` inyectado dentro de `MaterialApp`.
/// - Las restricciones de los `RenderObject` provienen de la vista, no del
///   `MediaQuery`; declarar un ancho sin cambiarlo produciría expectativas
///   de layout incorrectas.
void useTestSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// Simula un teclado en pantalla ocupando [height] px en la parte inferior.
void useTestKeyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  addTearDown(tester.view.resetViewInsets);
}

/// Simula safe areas (notch / barra de gestos) de iOS.
void useTestSafeArea(
  WidgetTester tester, {
  double top = 0,
  double bottom = 0,
  double left = 0,
  double right = 0,
}) {
  tester.view.padding = FakeViewPadding(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
  );
  addTearDown(tester.view.resetPadding);
}

/// `MaterialApp` mínimo para las pruebas de layout responsive.
Widget testApp(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? ThemeData(useMaterial3: true),
    home: child,
  );
}
