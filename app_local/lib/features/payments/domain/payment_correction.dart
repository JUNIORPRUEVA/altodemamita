/// FASE 01C — Previsualizacion autoritativa de una correccion de pago.
///
/// Contrato: `GET /authoritative/payments/:paymentId/correction-preview`
/// Devuelve si la operacion es financieramente segura, el mensaje accionable y
/// el impacto estimado. El escritorio NO decide por su cuenta: si el backend
/// rechaza, la accion queda bloqueada con la explicacion recibida.
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

String _asString(Object? value) => (value ?? '').toString();

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

class PaymentCorrectionImpact {
  const PaymentCorrectionImpact({
    required this.amountRestoredToBalance,
    required this.saleBalanceBefore,
    required this.saleBalanceAfter,
    required this.paidAmountBefore,
    required this.paidAmountAfter,
    required this.becomesOpen,
    required this.dateChange,
    required this.replacesPayment,
    required this.lateFeeNote,
    required this.estimated,
  });

  final double amountRestoredToBalance;
  final double saleBalanceBefore;
  final double saleBalanceAfter;
  final double paidAmountBefore;
  final double paidAmountAfter;
  final bool becomesOpen;
  final bool dateChange;
  final bool replacesPayment;
  final String? lateFeeNote;
  final bool estimated;

  factory PaymentCorrectionImpact.fromMap(Map<String, dynamic> map) {
    final installment = _asMap(map['installment']);
    return PaymentCorrectionImpact(
      amountRestoredToBalance: _asDouble(map['amountRestoredToBalance']),
      saleBalanceBefore: _asDouble(map['saleBalanceBefore']),
      saleBalanceAfter: _asDouble(map['saleBalanceAfter']),
      paidAmountBefore: _asDouble(installment['paidAmountBefore']),
      paidAmountAfter: _asDouble(installment['paidAmountAfter']),
      becomesOpen: installment['becomesOpen'] == true,
      dateChange: map['dateChange'] == true,
      replacesPayment: map['replacesPayment'] == true,
      lateFeeNote: (map['lateFeeNote'] as String?)?.trim().isEmpty == true
          ? null
          : map['lateFeeNote']?.toString(),
      estimated: map['impactEstimated'] != false,
    );
  }
}

class PaymentCorrectionPreview {
  const PaymentCorrectionPreview({
    required this.allowed,
    required this.code,
    required this.message,
    required this.requiresScheduleReconstruction,
    required this.createsReplacementPayment,
    required this.paymentId,
    required this.paymentType,
    required this.paymentAmount,
    required this.paymentVersion,
    required this.saleBalance,
    required this.impact,
  });

  final bool allowed;
  final String code;
  final String message;
  final bool requiresScheduleReconstruction;
  final bool createsReplacementPayment;
  final int paymentId;
  final String paymentType;
  final double paymentAmount;
  final int paymentVersion;
  final double saleBalance;
  final PaymentCorrectionImpact impact;

  factory PaymentCorrectionPreview.fromMap(Map<String, dynamic> map) {
    final payment = _asMap(map['payment']);
    final correction = _asMap(map['correction']);
    final sale = _asMap(map['sale']);
    return PaymentCorrectionPreview(
      allowed: correction['allowed'] == true,
      code: _asString(correction['code']),
      message: _asString(correction['message']),
      requiresScheduleReconstruction:
          correction['requiresScheduleReconstruction'] == true,
      createsReplacementPayment:
          correction['createsReplacementPayment'] == true,
      paymentId: _asInt(payment['id']),
      paymentType: _asString(payment['paymentType']),
      paymentAmount: _asDouble(payment['amount']),
      paymentVersion: _asInt(payment['version']),
      saleBalance: _asDouble(sale['balance']),
      impact: PaymentCorrectionImpact.fromMap(_asMap(map['impact'])),
    );
  }

  /// Previsualizacion de fallback cuando la llamada falla: fail-closed.
  factory PaymentCorrectionPreview.blocked(String message) {
    return PaymentCorrectionPreview(
      allowed: false,
      code: 'PREVIEW_UNAVAILABLE',
      message: message,
      requiresScheduleReconstruction: false,
      createsReplacementPayment: false,
      paymentId: 0,
      paymentType: '',
      paymentAmount: 0,
      paymentVersion: 0,
      saleBalance: 0,
      impact: const PaymentCorrectionImpact(
        amountRestoredToBalance: 0,
        saleBalanceBefore: 0,
        saleBalanceAfter: 0,
        paidAmountBefore: 0,
        paidAmountAfter: 0,
        becomesOpen: false,
        dateChange: false,
        replacesPayment: false,
        lateFeeNote: null,
        estimated: true,
      ),
    );
  }
}

/// Acciones de correccion soportadas por el backend.
class PaymentCorrectionAction {
  const PaymentCorrectionAction._();

  static const String annul = 'annul';
  static const String changeDate = 'change_date';
  static const String correctAmount = 'correct_amount';

  static String label(String action) {
    switch (action) {
      case annul:
        return 'Anular pago';
      case changeDate:
        return 'Cambiar fecha';
      case correctAmount:
        return 'Editar monto';
      default:
        return 'Corregir pago';
    }
  }
}
