const businessTimezone = 'America/Santo_Domingo';
const moneyTolerance = 0.009;

class InstallmentSummaryCounts {
  const InstallmentSummaryCounts({
    required this.total,
    required this.paid,
    required this.overdue,
    required this.partial,
    required this.pending,
  });

  final int total;
  final int paid;
  final int overdue;
  final int partial;
  final int pending;
}

class InstallmentStatusInput {
  const InstallmentStatusInput({
    required this.dueDate,
    required this.totalAmount,
    required this.paidAmount,
    this.storedStatus,
    this.remainingAmount,
  });

  final DateTime dueDate;
  final double totalAmount;
  final double paidAmount;
  final double? remainingAmount;
  final String? storedStatus;
}

class InstallmentStatusResolver {
  const InstallmentStatusResolver._();

  static String effectiveStatus({
    required DateTime dueDate,
    required double totalAmount,
    required double paidAmount,
    DateTime? businessDate,
    String? storedStatus,
    double? remainingAmount,
  }) {
    final normalizedStored = _normalizeStatus(storedStatus);
    if (normalizedStored == 'ajustada' ||
        normalizedStored == 'adjusted' ||
        normalizedStored == 'cancelada' ||
        normalizedStored == 'cancelled' ||
        normalizedStored == 'canceled') {
      return normalizedStored == 'ajustada' || normalizedStored == 'adjusted'
          ? 'ajustada'
          : 'cancelada';
    }

    final remaining = (remainingAmount ?? (totalAmount - paidAmount)).clamp(
      0,
      double.infinity,
    );
    if (normalizedStored == 'pagada' ||
        normalizedStored == 'pagado' ||
        normalizedStored == 'paid' ||
        remaining <= moneyTolerance) {
      return 'pagada';
    }

    if (isPastDue(dueDate: dueDate, businessDate: businessDate)) {
      return 'vencida';
    }

    if (paidAmount > moneyTolerance) {
      return 'parcial';
    }

    return 'pendiente';
  }

  /// Estado que se PERSISTE en la columna `estado` de la cuota.
  ///
  /// A diferencia de [effectiveStatus], el atraso no se persiste: una cuota
  /// con pago parcial conserva `parcial` aunque su vencimiento ya haya
  /// pasado, porque el atraso es un estado EFECTIVO que se deriva en lectura.
  /// Persistirlo reescribiria el historial de cuotas ya guardado.
  static String persistedStatus({
    required DateTime dueDate,
    required double totalAmount,
    required double paidAmount,
    required DateTime businessDate,
  }) {
    if (paidAmount >= totalAmount - moneyTolerance) {
      return 'pagada';
    }
    if (paidAmount > moneyTolerance) {
      return 'parcial';
    }
    return isPastDue(dueDate: dueDate, businessDate: businessDate)
        ? 'vencida'
        : 'pendiente';
  }

  static bool isPastDue({required DateTime dueDate, DateTime? businessDate}) {
    return businessDateKey(dueDate).compareTo(
          businessDate == null
              ? currentBusinessDateKey()
              : businessDateKey(businessDate),
        ) <
        0;
  }

  /// Offset fijo del negocio.
  ///
  /// America/Santo_Domingo es UTC-4 TODO el ano (no observa DST), por lo que un
  /// offset constante es exacto y no depende de la base tzdata del equipo.
  static const Duration businessUtcOffset = Duration(hours: 4);

  /// Clave de dia de negocio (YYYY-MM-DD).
  ///
  /// Convencion de almacenamiento del producto (clave para no desplazar dias):
  /// - Un valor **UTC** (los que llegan del backend como `...Z`) es un INSTANTE:
  ///   se convierte al reloj de Republica Dominicana restando el offset fijo.
  /// - Un valor **naive** (los que construye y persiste la app, `fecha_venta`,
  ///   `fecha_vencimiento`) NO lleva zona horaria: representa hora de pared de
  ///   RD tal como se capturo. Se usan sus componentes tal cual, de modo que el
  ///   resultado NO depende de la zona horaria del equipo.
  static String businessDateKey(DateTime value) {
    final businessDate = value.isUtc
        ? value.toUtc().subtract(businessUtcOffset)
        : value;
    return '${businessDate.year.toString().padLeft(4, '0')}-'
        '${businessDate.month.toString().padLeft(2, '0')}-'
        '${businessDate.day.toString().padLeft(2, '0')}';
  }

  /// Dia de negocio ACTUAL en America/Santo_Domingo.
  ///
  /// Se deriva del INSTANTE real (UTC), no del reloj/zona del equipo: un PC en
  /// otra zona horaria ya no puede adelantar ni atrasar el dia de negocio.
  static String currentBusinessDateKey([DateTime? now]) {
    final instant = (now ?? DateTime.now()).toUtc();
    return businessDateKey(instant);
  }

  static InstallmentSummaryCounts summarize(
    Iterable<InstallmentStatusInput> installments, {
    DateTime? businessDate,
  }) {
    var total = 0;
    var paid = 0;
    var overdue = 0;
    var partial = 0;
    var pending = 0;

    for (final installment in installments) {
      total += 1;
      final status = effectiveStatus(
        dueDate: installment.dueDate,
        totalAmount: installment.totalAmount,
        paidAmount: installment.paidAmount,
        remainingAmount: installment.remainingAmount,
        storedStatus: installment.storedStatus,
        businessDate: businessDate,
      );
      switch (status) {
        case 'pagada':
        case 'ajustada':
        case 'cancelada':
          paid += 1;
          break;
        case 'vencida':
          overdue += 1;
          break;
        case 'parcial':
          partial += 1;
          break;
        default:
          pending += 1;
      }
    }

    return InstallmentSummaryCounts(
      total: total,
      paid: paid,
      overdue: overdue,
      partial: partial,
      pending: pending,
    );
  }

  static String _normalizeStatus(String? status) =>
      (status ?? '').trim().toLowerCase();
}
