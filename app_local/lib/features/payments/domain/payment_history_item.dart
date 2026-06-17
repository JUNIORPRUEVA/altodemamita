class PaymentHistoryItem {
  const PaymentHistoryItem({
    required this.id,
    required this.saleId,
    required this.clientId,
    this.installmentId,
    required this.paymentDate,
    required this.amountPaid,
    required this.paymentMethod,
    required this.paymentType,
    this.reference,
    this.installmentNumber,
  });

  final int id;
  final int saleId;
  final int clientId;
  final int? installmentId;
  final DateTime paymentDate;
  final double amountPaid;
  final String paymentMethod;
  final String paymentType;
  final String? reference;
  final int? installmentNumber;

  factory PaymentHistoryItem.fromMap(Map<String, Object?> map) {
    return PaymentHistoryItem(
      id: map['id'] as int? ?? 0,
      saleId: map['venta_id'] as int? ?? 0,
      clientId: map['cliente_id'] as int? ?? 0,
      installmentId: map['cuota_id'] as int?,
      paymentDate: DateTime.parse(map['fecha_pago'] as String),
      amountPaid: _toDouble(map['monto_pagado']),
      paymentMethod: map['metodo_pago'] as String? ?? '',
      paymentType: map['tipo_pago'] as String? ?? 'cuota',
      reference: map['referencia'] as String?,
      installmentNumber: map['numero_cuota'] as int?,
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}
