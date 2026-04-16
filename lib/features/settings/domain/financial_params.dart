/// Parámetros financieros del sistema
class FinancialParams {
  const FinancialParams({
    this.id,
    required this.initialPercentageDefault,
    required this.monthlyInterestDefault,
    required this.installmentCountDefault,
    this.currencySymbol = 'RD\$',
    this.decimalPlaces = 2,
    required this.fechaActualizacion,
  });

  final int? id;
  final double initialPercentageDefault; // Porcentaje inicial por defecto
  final double monthlyInterestDefault; // Interés mensual por defecto
  final int installmentCountDefault; // Cantidad de cuotas por defecto
  final String currencySymbol;
  final int decimalPlaces;
  final DateTime fechaActualizacion;

  factory FinancialParams.defaults() {
    return FinancialParams(
      initialPercentageDefault: 10.0,
      monthlyInterestDefault: 1.0,
      installmentCountDefault: 12,
      currencySymbol: 'RD\$',
      decimalPlaces: 2,
      fechaActualizacion: DateTime.now(),
    );
  }

  factory FinancialParams.fromMap(Map<String, Object?> map) {
    return FinancialParams(
      id: map['id'] as int?,
      initialPercentageDefault: double.parse(map['inicial_porcentaje'] as String? ?? '10.0'),
      monthlyInterestDefault: double.parse(map['interes_mensual'] as String? ?? '1.0'),
      installmentCountDefault: int.parse(map['cantidad_cuotas'] as String? ?? '12'),
      currencySymbol: map['simbolo_moneda'] as String? ?? 'RD\$',
      decimalPlaces: int.parse(map['lugares_decimales'] as String? ?? '2'),
      fechaActualizacion: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'inicial_porcentaje': initialPercentageDefault.toString(),
      'interes_mensual': monthlyInterestDefault.toString(),
      'cantidad_cuotas': installmentCountDefault.toString(),
      'simbolo_moneda': currencySymbol,
      'lugares_decimales': decimalPlaces.toString(),
      'fecha_actualizacion': fechaActualizacion.toIso8601String(),
    };
  }

  FinancialParams copyWith({
    int? id,
    double? initialPercentageDefault,
    double? monthlyInterestDefault,
    int? installmentCountDefault,
    String? currencySymbol,
    int? decimalPlaces,
    DateTime? fechaActualizacion,
  }) {
    return FinancialParams(
      id: id ?? this.id,
      initialPercentageDefault: initialPercentageDefault ?? this.initialPercentageDefault,
      monthlyInterestDefault: monthlyInterestDefault ?? this.monthlyInterestDefault,
      installmentCountDefault: installmentCountDefault ?? this.installmentCountDefault,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
    );
  }
}
