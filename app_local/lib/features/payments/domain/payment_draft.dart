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
    this.targetInstallmentNumber,
    this.advanceInstallmentCount,
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
  /// Values: 'cuota', 'cuota_vencida', 'todas_cuotas_vencidas',
  /// 'cuotas_adelantadas', 'abono_capital', 'abono_inicial', 'apartado'.
  /// When null, type is derived automatically from the sale state.
  final String? paymentTypeOverride;

  /// Optional explicit installment selected by the user.
  /// Used to guarantee that a payment targets the intended overdue installment.
  final int? targetInstallmentId;

  /// Optional installment number selected by the user.
  /// Fallback when the local installment id changed after background sync.
  final int? targetInstallmentNumber;

  /// Number of open installments selected for 'cuotas_adelantadas'.
  ///
  /// This keeps any extra amount from spilling into the next installment; the
  /// remaining amount can then be applied as direct capital.
  final int? advanceInstallmentCount;
}
