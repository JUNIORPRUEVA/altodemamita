class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.syncStatus,
    required this.clientName,
    required this.clientDocumentId,
    required this.lotDisplayCode,
    required this.saleDate,
    required this.salePrice,
    required this.downPaymentAmount,
    required this.requiredInitialPayment,
    required this.paidInitialPayment,
    required this.pendingInitialPayment,
    this.minimumReserveAmount,
    this.initialPaymentDeadline,
    required this.financedBalance,
    required this.pendingBalance,
    required this.monthlyInterest,
    required this.installmentCount,
    required this.status,
    required this.generatedInstallments,
    this.overdueInstallmentCount = 0,
  });

  final int id;
  final String syncStatus;
  final String clientName;
  final String clientDocumentId;
  final String lotDisplayCode;
  final DateTime saleDate;
  final double salePrice;
  final double downPaymentAmount;
  final double requiredInitialPayment;
  final double paidInitialPayment;
  final double pendingInitialPayment;
  final double? minimumReserveAmount;
  final DateTime? initialPaymentDeadline;
  final double financedBalance;
  final double pendingBalance;
  final double monthlyInterest;
  final int installmentCount;
  final String status;
  final int generatedInstallments;
  final int overdueInstallmentCount;

  factory SaleSummary.fromMap(Map<String, Object?> map) {
    return SaleSummary(
      id: map['id'] as int? ?? 0,
      syncStatus: map['sync_status'] as String? ?? 'synced',
      clientName: map['cliente_nombre'] as String? ?? '',
      clientDocumentId: map['cliente_cedula'] as String? ?? '',
      lotDisplayCode:
          'M${map['manzana_numero'] as String? ?? ''}-S${map['solar_numero'] as String? ?? ''}',
      saleDate: DateTime.parse(map['fecha_venta'] as String),
      salePrice: _toDouble(map['precio_venta']),
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
      financedBalance: _toDouble(map['saldo_financiado']),
      pendingBalance: _toDouble(map['saldo_pendiente']),
      monthlyInterest: _toDouble(map['interes_mensual']),
      installmentCount: map['cantidad_cuotas'] as int? ?? 0,
      status: map['estado'] as String? ?? 'activa',
      generatedInstallments: map['cuotas_generadas'] as int? ?? 0,
      overdueInstallmentCount: map['cuotas_vencidas'] as int? ?? 0,
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  bool get isFinancingActive => status == 'activa' || status == 'pagada';

  bool get isPendingSync =>
      syncStatus == 'pending' ||
      syncStatus == 'pending_sync' ||
      syncStatus == 'pending_create' ||
      syncStatus == 'pending_update' ||
      syncStatus == 'pending_delete' ||
      syncStatus == 'failed' ||
      syncStatus == 'conflict';

  bool get isSynced => syncStatus == 'synced';
}