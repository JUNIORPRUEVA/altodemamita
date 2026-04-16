class PaymentSaleOption {
  const PaymentSaleOption({
    required this.saleId,
    required this.clientId,
    required this.clientName,
    required this.clientDocumentId,
    required this.clientPhone,
    required this.lotDisplayCode,
    required this.pendingBalance,
    required this.requiredInitialPayment,
    required this.paidInitialPayment,
    required this.pendingInitialPayment,
    required this.status,
  });

  final int saleId;
  final int clientId;
  final String clientName;
  final String clientDocumentId;
  final String clientPhone;
  final String lotDisplayCode;
  final double pendingBalance;
  final double requiredInitialPayment;
  final double paidInitialPayment;
  final double pendingInitialPayment;
  final String status;

  bool get isFinancingActive => status == 'activa' || status == 'pagada';

  factory PaymentSaleOption.fromMap(Map<String, Object?> map) {
    return PaymentSaleOption(
      saleId: map['id'] as int? ?? 0,
      clientId: map['cliente_id'] as int? ?? 0,
      clientName: map['cliente_nombre'] as String? ?? '',
      clientDocumentId: map['cliente_cedula'] as String? ?? '',
        clientPhone: map['cliente_telefono'] as String? ?? '',
      lotDisplayCode:
          'M${map['manzana_numero'] as String? ?? ''}-S${map['solar_numero'] as String? ?? ''}',
      pendingBalance: _toDouble(map['saldo_pendiente']),
      requiredInitialPayment: _toDouble(map['monto_inicial_requerido']),
      paidInitialPayment: _toDouble(map['monto_inicial_pagado']),
      pendingInitialPayment: _toDouble(map['monto_inicial_pendiente']),
      status: map['estado'] as String? ?? 'activa',
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}
