/// FASE 03 — Correcciones OWNER de ventas y contratos.
library;

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

class SaleCorrectionAction {
  const SaleCorrectionAction._();

  static const String updateFinancing = 'update_financing';
  static const String changeClient = 'change_client';
  static const String changeLot = 'change_lot';
  static const String cancel = 'cancel';
  static const String restore = 'restore';

  static String label(String action) {
    switch (action) {
      case updateFinancing:
        return 'Editar contrato';
      case changeClient:
        return 'Cambiar cliente';
      case changeLot:
        return 'Cambiar solar';
      case cancel:
        return 'Cancelar venta';
      case restore:
        return 'Restaurar venta';
      default:
        return 'Corregir venta';
    }
  }
}

class SaleCorrectionImpact {
  const SaleCorrectionImpact({
    required this.statusBefore,
    required this.statusAfter,
    required this.totalBefore,
    required this.totalAfter,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.initialPaidBefore,
    required this.initialPaidAfter,
    required this.financedBefore,
    required this.financedAfter,
    required this.installmentCountBefore,
    required this.installmentCountAfter,
    required this.activePayments,
  });

  final String? statusBefore;
  final String? statusAfter;
  final double totalBefore;
  final double totalAfter;
  final double balanceBefore;
  final double balanceAfter;
  final double initialPaidBefore;
  final double initialPaidAfter;
  final double financedBefore;
  final double financedAfter;
  final int installmentCountBefore;
  final int installmentCountAfter;
  final int activePayments;

  factory SaleCorrectionImpact.fromMap(Map<String, dynamic> map) {
    return SaleCorrectionImpact(
      statusBefore: map['statusBefore']?.toString(),
      statusAfter: map['statusAfter']?.toString(),
      totalBefore: _asDouble(map['totalBefore']),
      totalAfter: _asDouble(map['totalAfter']),
      balanceBefore: _asDouble(map['balanceBefore']),
      balanceAfter: _asDouble(map['balanceAfter']),
      initialPaidBefore: _asDouble(map['initialPaidBefore']),
      initialPaidAfter: _asDouble(map['initialPaidAfter']),
      financedBefore: _asDouble(map['financedBefore']),
      financedAfter: _asDouble(map['financedAfter']),
      installmentCountBefore: _asInt(map['installmentCountBefore']),
      installmentCountAfter: _asInt(map['installmentCountAfter']),
      activePayments: _asInt(map['activePayments']),
    );
  }

  static const SaleCorrectionImpact empty = SaleCorrectionImpact(
    statusBefore: null,
    statusAfter: null,
    totalBefore: 0,
    totalAfter: 0,
    balanceBefore: 0,
    balanceAfter: 0,
    initialPaidBefore: 0,
    initialPaidAfter: 0,
    financedBefore: 0,
    financedAfter: 0,
    installmentCountBefore: 0,
    installmentCountAfter: 0,
    activePayments: 0,
  );
}

class SaleCorrectionPreview {
  const SaleCorrectionPreview({
    required this.allowed,
    required this.code,
    required this.message,
    required this.saleVersion,
    required this.impact,
  });

  final bool allowed;
  final String code;
  final String message;
  final int saleVersion;
  final SaleCorrectionImpact impact;

  factory SaleCorrectionPreview.fromMap(Map<String, dynamic> map) {
    return SaleCorrectionPreview(
      allowed: map['allowed'] != false,
      code: (map['code'] ?? 'OK').toString(),
      message: (map['message'] ?? '').toString(),
      saleVersion: _asInt(map['saleVersion']),
      impact: SaleCorrectionImpact.fromMap(_asMap(map['impact'])),
    );
  }

  factory SaleCorrectionPreview.blocked(String message) {
    return SaleCorrectionPreview(
      allowed: false,
      code: 'PREVIEW_UNAVAILABLE',
      message: message,
      saleVersion: 0,
      impact: SaleCorrectionImpact.empty,
    );
  }
}
