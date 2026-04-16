class PaymentDraft {
  const PaymentDraft({
    required this.saleId,
    required this.paymentDate,
    required this.amountPaid,
    required this.paymentMethod,
    this.registeredByUserId,
    this.yearToPay,
    this.printReceiptAutomatically = false,
  });

  final int saleId;
  final DateTime paymentDate;
  final double amountPaid;
  final String paymentMethod;
  final int? registeredByUserId;

  /// Año al que aplica el pago (opcional). Ej: "2025".
  final String? yearToPay;
  final bool printReceiptAutomatically;
}
