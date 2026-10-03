import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/features/global_search/presentation/global_search_mobile.dart';
import 'package:sistema_solares/features/global_search/presentation/global_search_page.dart';

import 'helpers/responsive_test_harness.dart';

/// P0 ATAJOS DE TECLADO — CONTRATO DE ENTREGA.
///
/// Defecto reportado: "después de usar una tecla rápida se desactiva todo".
///
/// CAUSA RAIZ (verificada): los atajos viven en un `CallbackShortcuts`, que es
/// `Focus(canRequestFocus:false, skipTraversal:true, onKeyEvent:...)`: SOLO
/// entrega teclas mientras el foco primario sea DESCENDIENTE de su nodo.
/// La pantalla cerraba el foco con `_searchFocusNode.unfocus()`, cuya
/// disposicion por defecto (`UnfocusDisposition.scope`) manda el foco al
/// `enclosingScope` mas cercano. Con un `Focus(autofocus:true)` simple ese
/// scope es el de la RUTA, que es ANCESTRO de `CallbackShortcuts` => todos los
/// atajos dejan de entregarse hasta que el usuario hace clic.
///
/// Estos tests fijan el contrato completo (PARTE 1D): un atajo no puede
/// "apagar" la entrega de teclado del resto de la pantalla.
///
/// Semantica vigente (intencional, no se cambia aqui): al ENTRAR en la pantalla
/// el foco lo toma la pantalla (asi los atajos estan vivos sin hacer clic) y
/// `Ctrl+K` enfoca el buscador; el campo de texto NO se autoenfoca.

const Size _desktop = Size(1280, 900);
const Size _pwaCompact = Size(390, 844);

Finder get _searchField => find.byType(TextField);

FocusNode _fieldNode(WidgetTester tester) =>
    tester.widget<TextField>(_searchField).focusNode!;

bool _fieldFocused(WidgetTester tester) => _fieldNode(tester).hasFocus;

Widget _host({GlobalKey<NavigatorState>? navigatorKey}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    home: const GlobalSearchPage(),
  );
}

Future<void> _pumpDesktop(
  WidgetTester tester, {
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  useTestSize(tester, _desktop);
  await tester.pumpWidget(_host(navigatorKey: navigatorKey));
  await tester.pumpAndSettle();
}

Future<void> _ctrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('1. Ctrl+K funciona sin clic previo (primer uso)', (
    tester,
  ) async {
    await _pumpDesktop(tester);

    // La capa de atajos esta viva sin interaccion previa (esto es lo que el
    // defecto rompia: tras el primer uso, el resto dejaba de entregarse).
    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue, reason: 'primer uso del atajo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. Ctrl+K funciona dos veces consecutivas', (tester) async {
    await _pumpDesktop(tester);

    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue);

    await _escape(tester);
    expect(_fieldFocused(tester), isFalse);

    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue, reason: 'segundo uso del atajo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('3. atajo A (Esc limpia) -> atajo B (Ctrl+K enfoca)', (
    tester,
  ) async {
    await _pumpDesktop(tester);

    await tester.enterText(_searchField, 'maria');
    await tester.pump();
    expect(find.text('maria'), findsOneWidget);

    await _escape(tester);
    // Esc con texto: limpia la busqueda y CONSERVA el foco en el campo.
    expect(find.text('maria'), findsNothing);
    expect(_fieldFocused(tester), isTrue);

    // El primer atajo no desactiva el segundo.
    await _escape(tester);
    expect(_fieldFocused(tester), isFalse);
    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue);
  });

  testWidgets('4. atajo -> abrir/cerrar dialogo -> atajo otra vez', (
    tester,
  ) async {
    await _pumpDesktop(tester);

    final pageContext = tester.element(find.byType(GlobalSearchPage));
    _openDialog(pageContext);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Esc cierra el dialogo (DismissIntent de la ruta del modal).
    await _escape(tester);
    expect(find.byType(AlertDialog), findsNothing);

    // Cerrado el modal, la pantalla sigue respondiendo al teclado.
    await _escape(tester);
    expect(_fieldFocused(tester), isFalse);
    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue, reason: 'atajos restaurados');
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. ESC no desactiva el resto de atajos', (tester) async {
    await _pumpDesktop(tester);

    await _escape(tester);
    await _escape(tester);
    await _escape(tester);

    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('6. ENTER no desactiva el resto de atajos', (tester) async {
    await _pumpDesktop(tester);

    await tester.enterText(_searchField, '');
    await _enter(tester);
    expect(tester.takeException(), isNull);

    await _escape(tester);
    expect(_fieldFocused(tester), isFalse);

    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue, reason: 'ENTER no rompe la entrega');
  });

  testWidgets('7. navegar fuera y volver: los atajos siguen funcionando', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    useTestSize(tester, _desktop);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    final navigator = navigatorKey.currentState!;
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const GlobalSearchPage()),
    );
    await tester.pumpAndSettle();

    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue);
    await _escape(tester);
    expect(_fieldFocused(tester), isFalse);

    navigator.pop();
    await tester.pumpAndSettle();
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const GlobalSearchPage()),
    );
    await tester.pumpAndSettle();

    // Volver a la pantalla no deja los atajos muertos.
    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue, reason: 'atajos vivos tras volver');
    await _escape(tester);
    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue);
  });

  testWidgets('8. foco en el TextField: reglas correctas', (tester) async {
    await _pumpDesktop(tester);

    // Escribir mantiene el foco en el campo y NO debe romper la entrega.
    await tester.enterText(_searchField, 'solar');
    await tester.pump();
    expect(_fieldFocused(tester), isTrue);

    // Con foco en un campo de texto, Ctrl+K sigue re-enfocando el buscador.
    await _ctrlK(tester);
    expect(_fieldFocused(tester), isTrue);

    // Esc limpia el texto en vez de abandonar la pantalla.
    await _escape(tester);
    expect(find.text('solar'), findsNothing);
    expect(_fieldFocused(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '9. Windows: misma entrega de atajos',
    (tester) async {
      await _pumpDesktop(tester);

      await _escape(tester);
      expect(_fieldFocused(tester), isFalse);
      await _ctrlK(tester);
      expect(_fieldFocused(tester), isTrue);

      await _escape(tester);
      await _escape(tester);
      await _ctrlK(tester);
      expect(_fieldFocused(tester), isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('10. escritorio: escribir no mueve ni redimensiona el buscador', (
    tester,
  ) async {
    await _pumpDesktop(tester);

    final before = tester.getRect(_searchField);
    await tester.enterText(_searchField, 'y');
    await tester.pump();
    final after = tester.getRect(_searchField);

    expect(after.top, closeTo(before.top, 0.1));
    expect(after.left, closeTo(before.left, 0.1));
    expect(after.width, closeTo(before.width, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('11. PWA (compacto): no queda atrapado el teclado', (
    tester,
  ) async {
    useTestSize(tester, _pwaCompact);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSearchMobileView), findsOneWidget);

    // La vista compacta no registra atajos globales: escribir y pulsar Esc no
    // puede dejar la pantalla sin respuesta ni lanzar excepciones.
    await tester.enterText(find.byType(TextField).first, 'solar');
    await tester.pump();
    await _escape(tester);
    await _enter(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(GlobalSearchMobileView), findsOneWidget);
  });
}

/// Abre un dialogo modal sobre la pantalla de busqueda.
///
/// No se espera la `Future` a proposito: completaria solo al cerrar el modal.
void _openDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Dialogo de prueba'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
