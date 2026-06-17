class SaleDraft {
  const SaleDraft({
    required this.clientId,
    required this.lotId,
    required this.userId,
    this.sellerId,
    required this.saleDate,
    required this.salePrice,
    required this.downPaymentPercentage,
    required this.requiredInitialPayment,
    this.initialPaymentPaid = 0,
    this.initialPaymentMethod = 'efectivo',
    this.minimumReserveAmount,
    this.initialPaymentDeadline,
    this.initialIsApartado = false,
    required this.monthlyInterest,
    required this.installmentCount,
    this.status = 'apartado',
    this.additionalLotIds = const [],
  });

  final int clientId;
  final int lotId;
  final int userId;
  final int? sellerId;
  final DateTime saleDate;
  final double salePrice;
  final double downPaymentPercentage;
  final double requiredInitialPayment;
  final double initialPaymentPaid;
  final String initialPaymentMethod;
  final double? minimumReserveAmount;
  final DateTime? initialPaymentDeadline;

  /// Cuando es `true`, el monto entregado al crear la venta se trata como
  /// dinero de APARTADO (reserva del solar), no como pago del inicial. La
  /// venta queda en estado `apartado` o `inicial_incompleto` y el inicial
  /// requerido sigue pendiente; las cuotas no se generan hasta que el inicial
  /// se complete desde el módulo de Pagos.
  final bool initialIsApartado;
  final double monthlyInterest;
  final int installmentCount;
  final String status;
  final List<int> additionalLotIds;

  double get pendingInitialPayment {
    final remaining = requiredInitialPayment - initialPaymentPaid;
    return remaining <= 0 ? 0 : remaining;
  }

  /// Retorna todos los IDs de solares (principal + adicionales)
  List<int> get allLotIds => [lotId, ...additionalLotIds];

  /// Copia el objeto con valores opcionales
  SaleDraft copyWith({
    int? clientId,
    int? lotId,
    int? userId,
    int? sellerId,
    DateTime? saleDate,
    double? salePrice,
    double? downPaymentPercentage,
    double? requiredInitialPayment,
    double? initialPaymentPaid,
    String? initialPaymentMethod,
    double? minimumReserveAmount,
    DateTime? initialPaymentDeadline,
    bool? initialIsApartado,
    double? monthlyInterest,
    int? installmentCount,
    String? status,
    List<int>? additionalLotIds,
  }) {
    return SaleDraft(
      clientId: clientId ?? this.clientId,
      lotId: lotId ?? this.lotId,
      userId: userId ?? this.userId,
      sellerId: sellerId ?? this.sellerId,
      saleDate: saleDate ?? this.saleDate,
      salePrice: salePrice ?? this.salePrice,
      downPaymentPercentage: downPaymentPercentage ?? this.downPaymentPercentage,
      requiredInitialPayment: requiredInitialPayment ?? this.requiredInitialPayment,
      initialPaymentPaid: initialPaymentPaid ?? this.initialPaymentPaid,
      initialPaymentMethod: initialPaymentMethod ?? this.initialPaymentMethod,
      minimumReserveAmount: minimumReserveAmount ?? this.minimumReserveAmount,
      initialPaymentDeadline: initialPaymentDeadline ?? this.initialPaymentDeadline,
      initialIsApartado: initialIsApartado ?? this.initialIsApartado,
      monthlyInterest: monthlyInterest ?? this.monthlyInterest,
      installmentCount: installmentCount ?? this.installmentCount,
      status: status ?? this.status,
      additionalLotIds: additionalLotIds ?? this.additionalLotIds,
    );
  }
}