class Payment {
  const Payment({
    this.id,
    required this.saleId,
    required this.clientId,
    this.installmentId,
    required this.paymentDate,
    required this.amountPaid,
    required this.paymentType,
    this.paymentMethod,
    this.reference,
    required this.createdAt,
  });

  final int? id;
  final int saleId;
  final int clientId;
  final int? installmentId;
  final DateTime paymentDate;
  final double amountPaid;
  final String paymentType;
  final String? paymentMethod;
  final String? reference;
  final DateTime createdAt;

  factory Payment.fromMap(Map<String, Object?> map) {
    return Payment(
      id: map['id'] as int?,
      saleId: map['venta_id'] as int? ?? 0,
      clientId: map['cliente_id'] as int? ?? 0,
      installmentId: map['cuota_id'] as int?,
      paymentDate: DateTime.parse(map['fecha_pago'] as String),
      amountPaid: _toDouble(map['monto_pagado']),
      paymentType: map['tipo_pago'] as String? ?? 'cuota',
      paymentMethod: map['metodo_pago'] as String?,
      reference: map['referencia'] as String?,
      createdAt: DateTime.parse(map['fecha_creacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'venta_id': saleId,
      'cliente_id': clientId,
      'cuota_id': installmentId,
      'fecha_pago': paymentDate.toIso8601String(),
      'monto_pagado': amountPaid,
      'tipo_pago': paymentType,
      'metodo_pago': paymentMethod,
      'referencia': reference,
      'fecha_creacion': createdAt.toIso8601String(),
    };
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}
