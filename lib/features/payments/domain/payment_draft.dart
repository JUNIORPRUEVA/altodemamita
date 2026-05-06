class PaymentDraft {
  const PaymentDraft({
    required this.saleId,
    required this.paymentDate,
    required this.amountPaid,
    required this.paymentMethod,
    this.registeredByUserId,
    this.yearToPay,
    this.printReceiptAutomatically = false,
    this.paymentTypeOverride,
    this.targetInstallmentId,
  });

  final int saleId;
  final DateTime paymentDate;
  final double amountPaid;
  final String paymentMethod;
  final int? registeredByUserId;

  /// Año al que aplica el pago (opcional). Ej: "2025".
  final String? yearToPay;
  final bool printReceiptAutomatically;

  /// Optional explicit payment type selected by the user.
  /// Values: 'cuota', 'cuota_vencida', 'abono_capital', 'abono_inicial', 'apartado'.
  /// When null, type is derived automatically from the sale state.
  final String? paymentTypeOverride;

  /// Optional explicit installment selected by the user.
  /// Used to guarantee that a payment targets the intended overdue installment.
  final int? targetInstallmentId;
}
