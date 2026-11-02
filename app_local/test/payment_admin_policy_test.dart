import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/payment_admin_policy.dart';

/// FASE 01B — la UI debe espejar la guarda del backend
/// (`paymentAnnulmentTypeRejection`): el cobro de una venta al contado no se
/// anula individualmente.
void main() {
  group('PaymentAdminPolicy', () {
    test('detecta el cobro de venta al contado sin distinguir formato', () {
      expect(PaymentAdminPolicy.isCashSalePayment('contado'), isTrue);
      expect(PaymentAdminPolicy.isCashSalePayment(' CONTADO '), isTrue);
      expect(PaymentAdminPolicy.isCashSalePayment('Contado'), isTrue);
      expect(PaymentAdminPolicy.isCashSalePayment('cuota'), isFalse);
      expect(PaymentAdminPolicy.isCashSalePayment(null), isFalse);
      expect(PaymentAdminPolicy.isCashSalePayment(''), isFalse);
    });

    test('no ofrece anular el cobro de una venta al contado', () {
      expect(
        PaymentAdminPolicy.canAnnulPayment(
          isAdmin: true,
          paymentType: 'contado',
        ),
        isFalse,
      );
      expect(PaymentAdminPolicy.isAnnullablePaymentType('contado'), isFalse);
    });

    test('mantiene la anulacion en los tipos con motor de reversion', () {
      for (final type in <String>[
        'cuota',
        'apartado',
        'abono_inicial',
        'inicial',
        'abono_capital',
        'liquidacion_total',
      ]) {
        expect(
          PaymentAdminPolicy.canAnnulPayment(isAdmin: true, paymentType: type),
          isTrue,
          reason: type,
        );
      }
    });

    test('un operador no administrador nunca obtiene la accion', () {
      expect(
        PaymentAdminPolicy.canAnnulPayment(
          isAdmin: false,
          paymentType: 'cuota',
        ),
        isFalse,
      );
      expect(
        PaymentAdminPolicy.canAnnulPayment(isAdmin: false, paymentType: null),
        isFalse,
      );
    });

    test('el mensaje de bloqueo es accionable y menciona Ventas', () {
      expect(
        PaymentAdminPolicy.cashSaleAnnulBlockedMessage,
        contains('venta al contado'),
      );
      expect(
        PaymentAdminPolicy.cashSaleAnnulBlockedMessage,
        contains('Ventas'),
      );
    });
  });
}
