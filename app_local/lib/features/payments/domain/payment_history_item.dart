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
    this.annulledAt,
    this.annulledByName,
    this.annulmentReason,
    this.authorizedByAdmin = false,
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

  /// Fecha de anulacion cuando el pago ya fue revertido.
  final DateTime? annulledAt;

  /// Nombre del usuario que ejecuto la anulacion, si el backend lo informa.
  final String? annulledByName;

  /// Motivo declarado al anular.
  final String? annulmentReason;

  /// `true` cuando la anulacion requirio autorizacion de un administrador.
  final bool authorizedByAdmin;

  /// Un pago anulado se conserva en el historial pero ya no es cobrable ni
  /// reversible: no debe ofrecer acciones financieras.
  bool get isAnnulled => annulledAt != null;

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
      annulledAt: _toDateTime(map['anulado_en']),
      annulledByName: map['anulado_por'] as String?,
      annulmentReason: map['motivo_anulacion'] as String?,
    );
  }

  static DateTime? _toDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}
