import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/presentation/payment_annul_dialog.dart';

class _Harness {
  PaymentAnnulResult? result;
  bool closed = false;
}

Future<_Harness> _openAnnulDialog(
  WidgetTester tester, {
  bool requiresAdminAuthorization = false,
  PaymentAnnulAuthorizer? onAuthorize,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                harness.result = await showDialog<PaymentAnnulResult>(
                  context: context,
                  builder: (_) => PaymentAnnulDialog(
                    clientName: 'Prueva tres',
                    concept: 'Abono a inicial',
                    amount: 'RD\$ 25,000.00',
                    paymentDate: '10/09/2026',
                    requiresAdminAuthorization: requiresAdminAuthorization,
                    onAuthorize:
                        onAuthorize ??
                        (email, password) async =>
                            (authorizationId: 'auth-1', error: null),
                  ),
                );
                harness.closed = true;
              },
              child: const Text('abrir anulacion'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir anulacion'));
  await tester.pumpAndSettle();
  return harness;
}

FilledButton _confirmButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Anular pago'),
  );
}

Future<void> _selectReason(WidgetTester tester, String reason) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(reason).last);
  await tester.pumpAndSettle();
}

void main() {
  group('PaymentAnnulReasons.resolve', () {
    test('sin seleccion no produce motivo', () {
      expect(PaymentAnnulReasons.resolve(null, ''), isNull);
      expect(PaymentAnnulReasons.resolve('', 'algo'), isNull);
      expect(PaymentAnnulReasons.resolve('   ', 'algo'), isNull);
    });

    test('devuelve el motivo elegido tal cual', () {
      expect(
        PaymentAnnulReasons.resolve(PaymentAnnulReasons.duplicated, ''),
        'Pago duplicado',
      );
    });

    test('Otro exige descripcion', () {
      expect(PaymentAnnulReasons.resolve(PaymentAnnulReasons.other, ''), isNull);
      expect(
        PaymentAnnulReasons.resolve(PaymentAnnulReasons.other, '   '),
        isNull,
      );
    });

    test('Otro conserva la trazabilidad con el prefijo', () {
      expect(
        PaymentAnnulReasons.resolve(PaymentAnnulReasons.other, 'Cliente pidio'),
        'Otro: Cliente pidio',
      );
    });

    test('la lista canonica no incluye lenguaje tecnico', () {
      expect(PaymentAnnulReasons.all, <String>[
        'Pago registrado por error',
        'Monto incorrecto',
        'Método de pago incorrecto',
        'Pago duplicado',
        'Otro',
      ]);
      expect(
        PaymentAnnulReasons.all.any((reason) => reason.contains('digitacion')),
        isFalse,
      );
      expect(
        PaymentAnnulReasons.all.any((reason) => reason.contains('digitación')),
        isFalse,
      );
    });
  });

  group('etiqueta de concepto', () {
    test('traduce los tipos de pago del backend', () {
      expect(paymentAnnulConceptLabel('inicial', null), 'Abono a inicial');
      expect(paymentAnnulConceptLabel('abono_inicial', null), 'Abono a inicial');
      expect(paymentAnnulConceptLabel('apartado', null), 'Abono a apartado');
      expect(paymentAnnulConceptLabel('abono_capital', null), 'Abono a capital');
      expect(paymentAnnulConceptLabel('cuota', 4), 'Cuota 4');
      expect(paymentAnnulConceptLabel('cuota', null), 'Cuota');
      expect(paymentAnnulConceptLabel('', null), 'Pago');
    });
  });

  group('PaymentAnnulDialog', () {
    testWidgets('abre sin motivo seleccionado y muestra el placeholder', (
      tester,
    ) async {
      await _openAnnulDialog(tester);

      expect(find.text('Anular pago'), findsWidgets);
      expect(find.text(PaymentAnnulReasons.placeholder), findsOneWidget);
      expect(find.text('Error de digitacion'), findsNothing);
      expect(find.text('Error de digitación'), findsNothing);

      // Datos de confirmacion y advertencia financiera.
      expect(find.text('Prueva tres'), findsOneWidget);
      expect(find.text('Abono a inicial'), findsOneWidget);
      expect(find.textContaining('revertirá el efecto financiero'), findsOneWidget);
    });

    testWidgets('confirmar esta deshabilitado sin motivo', (tester) async {
      await _openAnnulDialog(tester);

      expect(_confirmButton(tester).onPressed, isNull);
      expect(
        find.text('Selecciona un motivo para anular el pago.'),
        findsOneWidget,
      );
    });

    testWidgets('elegir un motivo habilita confirmar', (tester) async {
      await _openAnnulDialog(tester);

      await _selectReason(tester, 'Pago registrado por error');

      expect(_confirmButton(tester).onPressed, isNotNull);
      expect(find.text(PaymentAnnulReasons.placeholder), findsNothing);
    });

    testWidgets('Otro muestra el campo de descripcion', (tester) async {
      await _openAnnulDialog(tester);

      expect(find.text('Especifique el motivo'), findsNothing);

      await _selectReason(tester, 'Otro');

      expect(find.text('Especifique el motivo'), findsOneWidget);
    });

    testWidgets('Otro sin descripcion queda bloqueado', (tester) async {
      await _openAnnulDialog(tester);

      await _selectReason(tester, 'Otro');

      expect(_confirmButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(_confirmButton(tester).onPressed, isNull);
    });

    testWidgets('Otro con descripcion se envia con prefijo de trazabilidad', (
      tester,
    ) async {
      final harness = await _openAnnulDialog(tester);

      await _selectReason(tester, 'Otro');
      await tester.enterText(find.byType(TextField), 'Cliente solicito');
      await tester.pumpAndSettle();

      expect(_confirmButton(tester).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Anular pago'));
      await tester.pumpAndSettle();

      expect(harness.result?.reason, 'Otro: Cliente solicito');
    });

    testWidgets('el motivo elegido llega limpio al confirmar', (tester) async {
      final harness = await _openAnnulDialog(tester);

      await _selectReason(tester, 'Pago duplicado');
      await tester.tap(find.widgetWithText(FilledButton, 'Anular pago'));
      await tester.pumpAndSettle();

      expect(harness.result?.reason, 'Pago duplicado');
      expect(harness.result?.adminAuthorizationId, isNull);
    });

    testWidgets('cancelar no produce anulacion', (tester) async {
      final harness = await _openAnnulDialog(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(harness.closed, isTrue);
      expect(harness.result, isNull);
    });

    testWidgets('con autorizacion admin no confirma sin motivo', (
      tester,
    ) async {
      await _openAnnulDialog(tester, requiresAdminAuthorization: true);

      expect(
        find.textContaining('autorizacion de un administrador'),
        findsWidgets,
      );
      // Sin motivo, aunque se rellenen credenciales, no se puede confirmar.
      await tester.enterText(find.byType(TextField).at(0), 'admin@local.test');
      await tester.enterText(find.byType(TextField).at(1), 'secreto');
      await tester.pumpAndSettle();

      expect(_confirmButton(tester).onPressed, isNull);
    });

    testWidgets('credenciales admin invalidas mantienen el dialogo abierto', (
      tester,
    ) async {
      final harness = await _openAnnulDialog(
        tester,
        requiresAdminAuthorization: true,
        onAuthorize: (email, password) async =>
            (authorizationId: null, error: 'Credenciales invalidas.'),
      );

      await _selectReason(tester, 'Pago registrado por error');
      await tester.enterText(find.byType(TextField).at(0), 'admin@local.test');
      await tester.enterText(find.byType(TextField).at(1), 'incorrecta');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Anular pago'));
      await tester.pumpAndSettle();

      expect(harness.closed, isFalse);
      expect(harness.result, isNull);
      expect(find.text('Credenciales invalidas.'), findsOneWidget);
    });

    testWidgets('autorizacion admin valida devuelve el identificador', (
      tester,
    ) async {
      final harness = await _openAnnulDialog(
        tester,
        requiresAdminAuthorization: true,
        onAuthorize: (email, password) async =>
            (authorizationId: 'auth-9', error: null),
      );

      await _selectReason(tester, 'Monto incorrecto');
      await tester.enterText(find.byType(TextField).at(0), 'admin@local.test');
      await tester.enterText(find.byType(TextField).at(1), 'secreto');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Anular pago'));
      await tester.pumpAndSettle();

      expect(harness.result?.reason, 'Monto incorrecto');
      expect(harness.result?.adminAuthorizationId, 'auth-9');
    });

    testWidgets('admin sin permiso propio no ve peticion de credenciales', (
      tester,
    ) async {
      await _openAnnulDialog(tester);

      expect(
        find.textContaining('autorizacion de un administrador'),
        findsNothing,
      );
      expect(find.text('Usuario administrador'), findsNothing);
    });
  });
}
