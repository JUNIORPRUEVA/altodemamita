class Installment {
  const Installment({
    this.id,
    required this.saleId,
    required this.installmentNumber,
    required this.dueDate,
    required this.openingBalance,
    required this.principalAmount,
    required this.interestAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.paidPrincipalAmount,
    required this.paidInterestAmount,
    required this.endingBalance,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int saleId;
  final int installmentNumber;
  final DateTime dueDate;
  final double openingBalance;
  final double principalAmount;
  final double interestAmount;
  final double totalAmount;
  final double paidAmount;
  final double paidPrincipalAmount;
  final double paidInterestAmount;
  final double endingBalance;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get remainingAmount {
    final remaining = totalAmount - paidAmount;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isSettled => remainingAmount <= 0.009;

  factory Installment.fromMap(Map<String, Object?> map) {
    return Installment(
      id: map['id'] as int?,
      saleId: map['venta_id'] as int? ?? 0,
      installmentNumber: map['numero_cuota'] as int? ?? 0,
      dueDate: DateTime.parse(map['fecha_vencimiento'] as String),
      openingBalance: _toDouble(map['saldo_inicial']),
      principalAmount: _toDouble(map['capital_cuota']),
      interestAmount: _toDouble(map['interes_cuota']),
      totalAmount: _toDouble(map['monto_cuota']),
      paidAmount: _toDouble(map['monto_pagado']),
      paidPrincipalAmount: _toDouble(map['capital_pagado']),
      paidInterestAmount: _toDouble(map['interes_pagado']),
      endingBalance: _toDouble(map['saldo_final']),
      status: map['estado'] as String? ?? 'pendiente',
      createdAt: DateTime.parse(map['fecha_creacion'] as String),
      updatedAt: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'venta_id': saleId,
      'numero_cuota': installmentNumber,
      'fecha_vencimiento': dueDate.toIso8601String(),
      'saldo_inicial': openingBalance,
      'capital_cuota': principalAmount,
      'interes_cuota': interestAmount,
      'monto_cuota': totalAmount,
      'monto_pagado': paidAmount,
      'capital_pagado': paidPrincipalAmount,
      'interes_pagado': paidInterestAmount,
      'saldo_final': endingBalance,
      'estado': status,
      'fecha_creacion': createdAt.toIso8601String(),
      'fecha_actualizacion': updatedAt.toIso8601String(),
    };
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}
