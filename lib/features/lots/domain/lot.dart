class Lot {
  Lot({
    this.id,
    required this.blockNumber,
    required this.lotNumber,
    required this.area,
    double? pricePerSquareMeter,
    double? price,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  }) : pricePerSquareMeter = _resolvePricePerSquareMeter(
         area: area,
         pricePerSquareMeter: pricePerSquareMeter,
         legacyTotalPrice: price,
       );

  static const List<String> statuses = ['disponible', 'reservado', 'vendido'];

  final int? id;
  final String blockNumber;
  final String lotNumber;
  final double area;
  final double pricePerSquareMeter;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayCode => 'M$blockNumber-S$lotNumber';

  double get totalPrice => _roundCurrency(area * pricePerSquareMeter);

  @Deprecated(
    'Use pricePerSquareMeter for unit price or totalPrice for the computed lot amount.',
  )
  double get price => totalPrice;

  factory Lot.empty() {
    final now = DateTime.now();
    return Lot(
      blockNumber: '',
      lotNumber: '',
      area: 0,
      pricePerSquareMeter: 0,
      status: statuses.first,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Lot.fromMap(Map<String, Object?> map) {
    return Lot(
      id: map['id'] as int?,
      blockNumber: map['manzana_numero'] as String? ?? '',
      lotNumber: map['solar_numero'] as String? ?? '',
      area: _toDouble(map['metros_cuadrados']),
      pricePerSquareMeter: _resolvePricePerSquareMeter(
        area: _toDouble(map['metros_cuadrados']),
        pricePerSquareMeter: _toDoubleOrNull(map['precio_por_metro']),
        legacyTotalPrice: _toDoubleOrNull(map['precio']),
      ),
      status: map['estado'] as String? ?? statuses.first,
      createdAt: DateTime.parse(map['fecha_creacion'] as String),
      updatedAt: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Lot copyWith({
    int? id,
    String? blockNumber,
    String? lotNumber,
    double? area,
    double? pricePerSquareMeter,
    double? price,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Lot(
      id: id ?? this.id,
      blockNumber: blockNumber ?? this.blockNumber,
      lotNumber: lotNumber ?? this.lotNumber,
      area: area ?? this.area,
      pricePerSquareMeter: pricePerSquareMeter,
      price: price ?? (pricePerSquareMeter == null ? totalPrice : null),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'manzana_numero': blockNumber,
      'solar_numero': lotNumber,
      'metros_cuadrados': area,
      'precio_por_metro': pricePerSquareMeter,
      'estado': status,
      'fecha_creacion': createdAt.toIso8601String(),
      'fecha_actualizacion': updatedAt.toIso8601String(),
    };
  }

  static double _resolvePricePerSquareMeter({
    required double area,
    double? pricePerSquareMeter,
    double? legacyTotalPrice,
  }) {
    if (pricePerSquareMeter != null && pricePerSquareMeter > 0) {
      return pricePerSquareMeter;
    }
    if (legacyTotalPrice != null && legacyTotalPrice > 0 && area > 0) {
      return legacyTotalPrice / area;
    }
    return 0;
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  static double _roundCurrency(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static double? _toDoubleOrNull(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }
}
