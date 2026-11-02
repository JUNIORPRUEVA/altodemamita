import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/presentation/payment_correction_history_dialog.dart';

/// FASE 01D — la traza administrativa es de SOLO LECTURA y muestra cada evento
/// con su fecha, motivo y efecto financiero.
void main() {
  Future<void> pump(WidgetTester tester, Map<String, dynamic> data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PaymentCorrectionHistoryDialog(data: data)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lista los eventos con motivo y efecto en el saldo', (
    tester,
  ) async {
    await pump(tester, {
      'payment': {'paymentType': 'cuota', 'amount': 15000},
      'history': [
        {
          'kind': 'created',
          'at': '2026-10-05T12:00:00.000Z',
          'amount': 15000,
          'detail': 'Pago registrado',
        },
        {
          'kind': 'correction',
          'at': '2026-11-02T15:00:00.000Z',
          'action': 'change_date',
          'reason': 'Fecha efectiva mal capturada',
          'performedByUserId': 'owner-1',
        },
        {
          'kind': 'authoritative_operation',
          'at': '2026-11-02T15:10:00.000Z',
          'action': 'annul',
          'reason': 'Pago historico registrado por error',
          'saleBalanceBefore': 10000,
          'saleBalanceAfter': 25000,
        },
      ],
    });

    expect(find.text('Alta del pago'), findsOneWidget);
    expect(find.text('Correccion aplicada'), findsOneWidget);
    expect(find.text('Operacion autoritativa'), findsOneWidget);
    expect(find.textContaining('Fecha efectiva mal capturada'), findsOneWidget);
    expect(
      find.textContaining('Pago historico registrado por error'),
      findsOneWidget,
    );
    expect(find.textContaining('25,000.00'), findsWidgets);
    expect(find.textContaining('owner-1'), findsOneWidget);
  });

  testWidgets('muestra estado vacio sin eventos', (tester) async {
    await pump(tester, {
      'payment': {'paymentType': 'cuota', 'amount': 0},
      'history': <dynamic>[],
    });
    expect(find.textContaining('Sin eventos registrados'), findsOneWidget);
  });
}
