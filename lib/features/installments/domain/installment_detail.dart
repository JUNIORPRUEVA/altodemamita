/// Detail view of an installment with related sale and client information
class InstallmentDetail {
  const InstallmentDetail({
    required this.id,
    required this.installmentNumber,
    required this.saleId,
    required this.clientName,
    required this.clientDocumentId,
    required this.lotCode,
    required this.dueDate,
    required this.openingBalance,
    required this.principalAmount,
    required this.interestAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.endingBalance,
    required this.status,
  });

  final int id;
  final int installmentNumber;
  final int saleId;
  final String clientName;
  final String clientDocumentId;
  final String lotCode;
  final DateTime dueDate;
  final double openingBalance;
  final double principalAmount;
  final double interestAmount;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final double endingBalance;
  final String status;

  /// Calculate status based on due date and payment
  String get calculatedStatus {
    if (remainingAmount <= 0.009) {
      return 'pagada';
    }
    if (paidAmount > 0) {
      return 'parcial';
    }
    if (DateTime.now().isAfter(dueDate)) {
      return 'vencida';
    }
    return 'pendiente';
  }

  factory InstallmentDetail.fromMap(Map<String, Object?> map) {
    return InstallmentDetail(
      id: map['id'] as int? ?? 0,
      installmentNumber: map['numero_cuota'] as int? ?? 0,
      saleId: map['venta_id'] as int? ?? 0,
      clientName: map['nombre_cliente'] as String? ?? '',
      clientDocumentId: map['cedula_cliente'] as String? ?? '',
      lotCode: map['codigo_solar'] as String? ?? '',
      dueDate: DateTime.parse(map['fecha_vencimiento'] as String),
      openingBalance: _toDouble(map['saldo_inicial']),
      principalAmount: _toDouble(map['capital_cuota']),
      interestAmount: _toDouble(map['interes_cuota']),
      totalAmount: _toDouble(map['monto_cuota']),
      paidAmount: _toDouble(map['monto_pagado']),
      remainingAmount: _toDouble(map['monto_cuota']) - _toDouble(map['monto_pagado']),
      endingBalance: _toDouble(map['saldo_final']),
      status: map['estado'] as String? ?? 'pendiente',
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString()) ?? 0;
  }
}

/// Summary information for a sale with its installments
class SaleInstallmentsSummary {
  const SaleInstallmentsSummary({
    required this.saleId,
    required this.clientName,
    required this.clientDocumentId,
    required this.lotCode,
    required this.totalFinanced,
    required this.totalPaid,
    required this.totalPending,
    required this.totalInstallments,
    required this.paidInstallments,
    required this.pendingInstallments,
  });

  final int saleId;
  final String clientName;
  final String clientDocumentId;
  final String lotCode;
  final double totalFinanced;
  final double totalPaid;
  final double totalPending;
  final int totalInstallments;
  final int paidInstallments;
  final int pendingInstallments;

  factory SaleInstallmentsSummary.fromMap(Map<String, Object?> map) {
    final totalFinanced = _toDoubleSummary(map['monto_total']) ?? 0.0;
    final totalPaid = _toDoubleSummary(map['total_pagado']) ?? 0.0;
    final totalPending = _toDoubleSummary(map['total_pendiente']) ?? 0.0;
    
    return SaleInstallmentsSummary(
      saleId: map['venta_id'] as int? ?? 0,
      clientName: map['nombre_cliente'] as String? ?? '',
      clientDocumentId: map['cedula_cliente'] as String? ?? '',
      lotCode: map['codigo_solar'] as String? ?? '',
      totalFinanced: totalFinanced,
      totalPaid: totalPaid,
      totalPending: totalPending,
      totalInstallments: map['total_cuotas'] as int? ?? 0,
      paidInstallments: map['cuotas_pagadas'] as int? ?? 0,
      pendingInstallments: map['cuotas_pendientes'] as int? ?? 0,
    );
  }

  static double? _toDoubleSummary(Object? value) {
    if (value == null) return null;
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
