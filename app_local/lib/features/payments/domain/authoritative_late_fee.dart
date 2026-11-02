/// Mora AUTORITATIVA de una venta, calculada por el backend.
///
/// La condonacion de mora (`LateFeeWaiver`) solo existe en el backend. El
/// cliente no puede deducirla recalculando localmente, por lo que cuando este
/// dato esta disponible el monto COBRABLE debe tomarse de aqui y no del calculo
/// local del escritorio.
///
/// Contrato: `GET /authoritative/sales/:saleId/late-fee-summary`
/// `{ data: { saleId, saleSyncId, asOfDate, policyEnabled,
///            grossLateFees, collectedLateFees, waivedLateFees,
///            outstandingLateFees, installments: [...] } }`
library;

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value == null) return null;
  return int.tryParse(value.toString());
}

class AuthoritativeLateFeeInstallment {
  const AuthoritativeLateFeeInstallment({
    required this.installmentSyncId,
    required this.installmentNumber,
    required this.dueDate,
    required this.grossLateFee,
    required this.waivedLateFee,
    required this.collectedLateFee,
    required this.outstandingLateFee,
  });

  final String installmentSyncId;
  final int? installmentNumber;
  final String? dueDate;

  /// Mora acumulada antes de condonaciones.
  final double grossLateFee;

  /// Mora condonada imputada a esta cuota.
  final double waivedLateFee;

  /// Mora ya cobrada de esta cuota.
  final double collectedLateFee;

  /// Mora realmente cobrable.
  final double outstandingLateFee;

  factory AuthoritativeLateFeeInstallment.fromMap(Map<String, dynamic> map) {
    return AuthoritativeLateFeeInstallment(
      installmentSyncId: (map['installmentSyncId'] ?? '').toString(),
      installmentNumber: _asInt(map['installmentNumber']),
      dueDate: map['dueDate']?.toString(),
      grossLateFee: _asDouble(map['grossLateFee']),
      waivedLateFee: _asDouble(map['waivedLateFee']),
      collectedLateFee: _asDouble(map['collectedLateFee']),
      outstandingLateFee: _asDouble(map['outstandingLateFee']),
    );
  }
}

class AuthoritativeLateFeeSummary {
  const AuthoritativeLateFeeSummary({
    required this.saleId,
    required this.saleSyncId,
    required this.asOfDate,
    required this.policyEnabled,
    required this.grossLateFees,
    required this.collectedLateFees,
    required this.waivedLateFees,
    required this.outstandingLateFees,
    required this.installments,
  });

  final String saleId;
  final String saleSyncId;
  final String asOfDate;
  final bool policyEnabled;

  /// Mora acumulada (bruta) de las cuotas vencidas.
  final double grossLateFees;

  /// Mora ya cobrada historicamente en la venta.
  final double collectedLateFees;

  /// Mora condonada vigente.
  final double waivedLateFees;

  /// Mora realmente cobrable.
  final double outstandingLateFees;

  final List<AuthoritativeLateFeeInstallment> installments;

  bool get hasWaiver => waivedLateFees > 0.009;

  /// Mora cobrable de una cuota concreta. Cero si la cuota no esta vencida o no
  /// figura en el calculo autoritativo.
  double outstandingForInstallmentNumber(int? installmentNumber) {
    if (installmentNumber == null) return 0;
    for (final row in installments) {
      if (row.installmentNumber == installmentNumber) {
        return row.outstandingLateFee;
      }
    }
    return 0;
  }

  factory AuthoritativeLateFeeSummary.fromMap(Map<String, dynamic> map) {
    final rawInstallments = map['installments'];
    final installments = <AuthoritativeLateFeeInstallment>[];
    if (rawInstallments is List) {
      for (final entry in rawInstallments) {
        if (entry is Map) {
          installments.add(
            AuthoritativeLateFeeInstallment.fromMap(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }
    return AuthoritativeLateFeeSummary(
      saleId: (map['saleId'] ?? '').toString(),
      saleSyncId: (map['saleSyncId'] ?? '').toString(),
      asOfDate: (map['asOfDate'] ?? '').toString(),
      policyEnabled: map['policyEnabled'] != false,
      grossLateFees: _asDouble(map['grossLateFees']),
      collectedLateFees: _asDouble(map['collectedLateFees']),
      waivedLateFees: _asDouble(map['waivedLateFees']),
      outstandingLateFees: _asDouble(map['outstandingLateFees']),
      installments: installments,
    );
  }
}

/// Resultado de consultar la mora autoritativa.
class LateFeeAuthority {
  const LateFeeAuthority._({
    required this.isAvailable,
    required this.summary,
    required this.reason,
  });

  const LateFeeAuthority.available(AuthoritativeLateFeeSummary summary)
    : this._(isAvailable: true, summary: summary, reason: null);

  const LateFeeAuthority.unavailable({String? reason})
    : this._(isAvailable: false, summary: null, reason: reason);

  final bool isAvailable;
  final AuthoritativeLateFeeSummary? summary;
  final String? reason;
}

/// Politica de mutacion financiera frente a la mora autoritativa.
class LateFeeMutationPolicy {
  const LateFeeMutationPolicy({
    required this.allowMutation,
    required this.usesAuthoritativeLateFee,
    required this.message,
  });

  final bool allowMutation;
  final bool usesAuthoritativeLateFee;
  final String? message;
}

/// Decide si se puede registrar un pago y que mora mostrar.
///
/// Reglas:
/// - Autoridad disponible -> manda el backend y se permite el pago.
/// - Sin autoridad y venta SIN condonacion conocida -> se conserva el
///   comportamiento offline historico (calculo local) y solo se advierte.
/// - Sin autoridad y venta CON condonacion conocida -> se BLOQUEA la mutacion:
///   cobrar mora ya condonada seria un cobro indebido.
LateFeeMutationPolicy evaluateLateFeeMutationPolicy({
  required LateFeeAuthority authority,
  required bool knownSaleHasWaiver,
}) {
  if (authority.isAvailable) {
    return const LateFeeMutationPolicy(
      allowMutation: true,
      usesAuthoritativeLateFee: true,
      message: null,
    );
  }
  if (knownSaleHasWaiver) {
    return const LateFeeMutationPolicy(
      allowMutation: false,
      usesAuthoritativeLateFee: false,
      message:
          'Esta venta tiene mora condonada y no se pudo confirmar el monto con el servidor. '
          'Conectate para registrar el pago con el monto correcto.',
    );
  }
  return const LateFeeMutationPolicy(
    allowMutation: true,
    usesAuthoritativeLateFee: false,
    message: 'Mora calculada localmente: no se pudo confirmar con el servidor.',
  );
}

/// Mora COBRABLE de una cuota: autoritativa si esta disponible, local si no.
double resolveCollectibleLateFee({
  required double localLateFee,
  required AuthoritativeLateFeeSummary? authoritative,
  required int? installmentNumber,
}) {
  if (authoritative == null) return localLateFee;
  final authoritativeValue = authoritative.outstandingForInstallmentNumber(
    installmentNumber,
  );
  return authoritativeValue < 0 ? 0 : authoritativeValue;
}

/// Resultado de una condonacion de mora aplicada por el backend.
///
/// Contrato: `POST /authoritative/sales/:saleId/late-fee-waiver`
/// `{ data: { saleId, saleSyncId, waiverId, cutoffAt,
///            windowGrossLateFees, collectedLateFees,
///            waivedAmount, outstandingAfter } }`
class LateFeeWaiverResult {
  const LateFeeWaiverResult({
    required this.waiverId,
    required this.cutoffAt,
    required this.waivedAmount,
    required this.outstandingAfter,
    required this.collectedLateFees,
    required this.windowGrossLateFees,
    this.outstandingBefore = 0,
    this.isPartial = false,
  });

  final String waiverId;
  final String cutoffAt;

  /// Mora efectivamente condonada por el backend en este corte.
  final double waivedAmount;

  /// Mora exigible que quedo despues de la condonacion (normalmente 0).
  final double outstandingAfter;

  final double collectedLateFees;
  final double windowGrossLateFees;

  /// Mora exigible justo antes de la condonacion.
  final double outstandingBefore;

  /// `true` si la condonacion fue parcial (monto indicado por el OWNER).
  final bool isPartial;

  factory LateFeeWaiverResult.fromMap(Map<String, dynamic> map) {
    return LateFeeWaiverResult(
      waiverId: (map['waiverId'] ?? '').toString(),
      cutoffAt: (map['cutoffAt'] ?? '').toString(),
      waivedAmount: _asDouble(map['waivedAmount']),
      outstandingAfter: _asDouble(map['outstandingAfter']),
      collectedLateFees: _asDouble(map['collectedLateFees']),
      windowGrossLateFees: _asDouble(map['windowGrossLateFees']),
      outstandingBefore: _asDouble(map['outstandingBefore']),
      isPartial: map['isPartial'] == true,
    );
  }
}
