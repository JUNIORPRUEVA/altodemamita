/// Politica de acciones administrativas sobre pagos (FASE 01B).
///
/// Espeja exactamente la guarda del backend
/// (`paymentAnnulmentTypeRejection` en `authoritativePayment.service.ts`):
/// el cobro de una venta al contado NO admite anulacion individual porque no
/// tiene cuota que revertir ni deuda que restaurar. La via correcta es
/// anular/revertir la venta completa desde Ventas.
///
/// Este archivo es la unica fuente de verdad en Flutter para decidir si la UI
/// ofrece la accion. El backend sigue siendo la autoridad final: aunque la UI
/// mostrara el boton, la anulacion se rechaza con
/// `CASH_SALE_PAYMENT_NOT_ANNULLABLE` (HTTP 409).
abstract final class PaymentAdminPolicy {
  /// Tipo de pago del cobro de una venta al contado.
  static const String cashSalePaymentType = 'contado';

  /// Mensaje unico mostrado al operador cuando la accion no esta disponible.
  static const String cashSaleAnnulBlockedMessage =
      'El cobro de una venta al contado no se puede anular individualmente: '
      'anula o revierte la venta completa desde Ventas.';

  static String normalizePaymentType(String? paymentType) =>
      (paymentType ?? '').trim().toLowerCase();

  /// `true` para el cobro de una venta al contado.
  static bool isCashSalePayment(String? paymentType) =>
      normalizePaymentType(paymentType) == cashSalePaymentType;

  /// Tipos que SI tienen motor de reversion en el backend.
  static bool isAnnullablePaymentType(String? paymentType) =>
      !isCashSalePayment(paymentType);

  /// Decide si la UI puede ofrecer "Anular" para un pago concreto.
  ///
  /// Requiere sesion administrativa (rol OWNER en la nube / `admin` local) y un
  /// tipo de pago con motor de reversion.
  static bool canAnnulPayment({required bool isAdmin, String? paymentType}) =>
      isAdmin && isAnnullablePaymentType(paymentType);
}
