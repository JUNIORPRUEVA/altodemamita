/// FASE 02 — Previsualizacion autoritativa de una correccion de cronograma.
///
/// Contrato: `GET /authoritative/sales/:saleId/installment-corrections/preview`
/// El backend ejecuta la MISMA logica del apply dentro de una transaccion que se
/// revierte, por lo que el impacto mostrado es el real.
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

class InstallmentCorrectionAction {
  const InstallmentCorrectionAction._();

  static const String changeDueDate = 'change_due_date';
  static const String changeAmounts = 'change_amounts';
  static const String addInstallment = 'add_installment';
  static const String removeInstallment = 'remove_installment';
  static const String reschedule = 'reschedule';

  static String label(String action) {
    switch (action) {
      case changeDueDate:
        return 'Cambiar vencimiento';
      case changeAmounts:
        return 'Editar montos';
      case addInstallment:
        return 'Agregar cuota';
      case removeInstallment:
        return 'Eliminar cuota';
      case reschedule:
        return 'Reprogramar cuotas';
      default:
        return 'Corregir cronograma';
    }
  }
}

class InstallmentCorrectionImpact {
  const InstallmentCorrectionImpact({
    required this.outstandingPrincipalBefore,
    required this.outstandingPrincipalAfter,
    required this.nextDueDateBefore,
    required this.nextDueDateAfter,
    required this.installmentCountBefore,
    required this.installmentCountAfter,
    required this.grossLateFeesBefore,
    required this.grossLateFeesAfter,
    required this.outstandingLateFeesBefore,
    required this.outstandingLateFeesAfter,
    required this.principalPreserved,
  });

  final double outstandingPrincipalBefore;
  final double outstandingPrincipalAfter;
  final String? nextDueDateBefore;
  final String? nextDueDateAfter;
  final int installmentCountBefore;
  final int installmentCountAfter;
  final double grossLateFeesBefore;
  final double grossLateFeesAfter;
  final double outstandingLateFeesBefore;
  final double outstandingLateFeesAfter;
  final bool principalPreserved;

  factory InstallmentCorrectionImpact.fromMap(Map<String, dynamic> map) {
    return InstallmentCorrectionImpact(
      outstandingPrincipalBefore: _asDouble(map['outstandingPrincipalBefore']),
      outstandingPrincipalAfter: _asDouble(map['outstandingPrincipalAfter']),
      nextDueDateBefore: map['nextDueDateBefore']?.toString(),
      nextDueDateAfter: map['nextDueDateAfter']?.toString(),
      installmentCountBefore: _asInt(map['installmentCountBefore']),
      installmentCountAfter: _asInt(map['installmentCountAfter']),
      grossLateFeesBefore: _asDouble(map['grossLateFeesBefore']),
      grossLateFeesAfter: _asDouble(map['grossLateFeesAfter']),
      outstandingLateFeesBefore: _asDouble(map['outstandingLateFeesBefore']),
      outstandingLateFeesAfter: _asDouble(map['outstandingLateFeesAfter']),
      principalPreserved: map['principalPreserved'] != false,
    );
  }

  static const InstallmentCorrectionImpact empty = InstallmentCorrectionImpact(
    outstandingPrincipalBefore: 0,
    outstandingPrincipalAfter: 0,
    nextDueDateBefore: null,
    nextDueDateAfter: null,
    installmentCountBefore: 0,
    installmentCountAfter: 0,
    grossLateFeesBefore: 0,
    grossLateFeesAfter: 0,
    outstandingLateFeesBefore: 0,
    outstandingLateFeesAfter: 0,
    principalPreserved: true,
  );
}

class InstallmentCorrectionPreview {
  const InstallmentCorrectionPreview({
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
  final InstallmentCorrectionImpact impact;

  /// La previsualizacion nunca bloquea por defecto: si el backend falla, la UI
  /// debe impedir aplicar (fail-closed).
  factory InstallmentCorrectionPreview.blocked(String message) {
    return InstallmentCorrectionPreview(
      allowed: false,
      code: 'PREVIEW_UNAVAILABLE',
      message: message,
      saleVersion: 0,
      impact: InstallmentCorrectionImpact.empty,
    );
  }

  factory InstallmentCorrectionPreview.fromMap(Map<String, dynamic> map) {
    return InstallmentCorrectionPreview(
      allowed: map['allowed'] != false,
      code: (map['code'] ?? 'OK').toString(),
      message: (map['message'] ?? '').toString(),
      saleVersion: _asInt(map['saleVersion']),
      impact: InstallmentCorrectionImpact.fromMap(_asMap(map['impact'])),
    );
  }
}
