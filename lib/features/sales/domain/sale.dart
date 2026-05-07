class Sale {
  const Sale({
    this.id,
    this.syncId,
    required this.clientId,
    required this.lotId,
    required this.userId,
    this.sellerId,
    required this.saleDate,
    required this.salePrice,
    required this.downPaymentPercentage,
    required this.downPaymentAmount,
    required this.requiredInitialPayment,
    required this.paidInitialPayment,
    required this.pendingInitialPayment,
    this.minimumReserveAmount,
    this.initialPaymentDeadline,
    this.activationDate,
    required this.financedBalance,
    required this.pendingBalance,
    required this.monthlyInterest,
    required this.installmentCount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String? syncId;
  final int clientId;
  final int lotId;
  final int userId;
  final int? sellerId;
  final DateTime saleDate;
  final double salePrice;
  final double downPaymentPercentage;
  final double downPaymentAmount;
  final double requiredInitialPayment;
  final double paidInitialPayment;
  final double pendingInitialPayment;
  final double? minimumReserveAmount;
  final DateTime? initialPaymentDeadline;
  final DateTime? activationDate;
  final double financedBalance;
  final double pendingBalance;
  final double monthlyInterest;
  final int installmentCount;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Sale.fromMap(Map<String, Object?> map) {
    return Sale(
      id: map['id'] as int?,
      syncId: (map['sync_id'] as String?)?.trim(),
      clientId: map['cliente_id'] as int? ?? 0,
      lotId: map['solar_id'] as int? ?? 0,
      userId: map['usuario_id'] as int? ?? 0,
      sellerId: map['vendedor_id'] as int?,
      saleDate: DateTime.parse(map['fecha_venta'] as String),
      salePrice: _toDouble(map['precio_venta']),
      downPaymentPercentage: _toDouble(map['inicial_porcentaje']),
      downPaymentAmount: _toDouble(map['inicial_monto']),
      requiredInitialPayment: _toDouble(map['monto_inicial_requerido']),
      paidInitialPayment: _toDouble(map['monto_inicial_pagado']),
      pendingInitialPayment: _toDouble(map['monto_inicial_pendiente']),
      minimumReserveAmount: map['monto_apartado_minimo'] == null
          ? null
          : _toDouble(map['monto_apartado_minimo']),
      initialPaymentDeadline: (map['fecha_limite_inicial'] as String?) == null
          ? null
          : DateTime.parse(map['fecha_limite_inicial'] as String),
      activationDate: (map['fecha_activacion'] as String?) == null
          ? null
          : DateTime.parse(map['fecha_activacion'] as String),
      financedBalance: _toDouble(map['saldo_financiado']),
      pendingBalance: _toDouble(map['saldo_pendiente']),
      monthlyInterest: _toDouble(map['interes_mensual']),
      installmentCount: map['cantidad_cuotas'] as int? ?? 0,
      status: map['estado'] as String? ?? 'activa',
      createdAt: DateTime.parse(map['fecha_creacion'] as String),
      updatedAt: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'sync_id': syncId,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': userId,
      'vendedor_id': sellerId,
      'fecha_venta': saleDate.toIso8601String(),
      'precio_venta': salePrice,
      'inicial_porcentaje': downPaymentPercentage,
      'inicial_monto': downPaymentAmount,
      'monto_inicial_requerido': requiredInitialPayment,
      'monto_inicial_pagado': paidInitialPayment,
      'monto_inicial_pendiente': pendingInitialPayment,
      'monto_apartado_minimo': minimumReserveAmount,
      'fecha_limite_inicial': initialPaymentDeadline?.toIso8601String(),
      'fecha_activacion': activationDate?.toIso8601String(),
      'saldo_financiado': financedBalance,
      'saldo_pendiente': pendingBalance,
      'interes_mensual': monthlyInterest,
      'cantidad_cuotas': installmentCount,
      'estado': status,
      'fecha_creacion': createdAt.toIso8601String(),
      'fecha_actualizacion': updatedAt.toIso8601String(),
    };
  }

  bool get isFinancingActive => status == 'activa' || status == 'pagada';

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}
