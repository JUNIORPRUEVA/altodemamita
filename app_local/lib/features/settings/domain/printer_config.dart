import 'dart:convert';

/// Configuración de impresoras
class PrinterConfig {
  const PrinterConfig({
    this.id,
    required this.nombre,
    required this.modelo,
    required this.tipo, // 'térmica', 'laser', 'digital'
    this.esPredeterminada = false,
    required this.configuracionJson, // Almacena config específica de SO
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int? id;
  final String nombre;
  final String modelo;
  final String tipo;
  final bool esPredeterminada;
  final String configuracionJson; // JSON con parámetros específicos del SO
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  static const List<String> tipos = ['térmica', 'laser', 'digital'];

  Map<String, Object?> get configuracionMap {
    try {
      final decoded = jsonDecode(configuracionJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }

  String? get printerUrl => configuracionMap['url'] as String?;

  String? get printerLocation => configuracionMap['location'] as String?;

  String? get printerComment => configuracionMap['comment'] as String?;

  String? get defaultOrientation {
    final rawValue =
        configuracionMap['default_orientation'] ??
        configuracionMap['orientation'];
    final normalized = rawValue?.toString().trim().toLowerCase();
    if (normalized == 'portrait' || normalized == 'landscape') {
      return normalized;
    }
    return null;
  }

  bool get hasSystemSelection => (printerUrl ?? '').isNotEmpty;

  factory PrinterConfig.empty() {
    final now = DateTime.now();
    return PrinterConfig(
      nombre: '',
      modelo: '',
      tipo: 'térmica',
      configuracionJson: '{}',
      fechaCreacion: now,
      fechaActualizacion: now,
    );
  }

  factory PrinterConfig.fromMap(Map<String, Object?> map) {
    return PrinterConfig(
      id: map['id'] as int?,
      nombre: map['nombre'] as String? ?? '',
      modelo: map['modelo'] as String? ?? '',
      tipo: map['tipo'] as String? ?? 'térmica',
      esPredeterminada: (map['es_predeterminada'] as int?) == 1,
      configuracionJson: map['configuracion_json'] as String? ?? '{}',
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaActualizacion: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'nombre': nombre,
      'modelo': modelo,
      'tipo': tipo,
      'es_predeterminada': esPredeterminada ? 1 : 0,
      'configuracion_json': configuracionJson,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_actualizacion': fechaActualizacion.toIso8601String(),
    };
  }

  PrinterConfig copyWith({
    int? id,
    String? nombre,
    String? modelo,
    String? tipo,
    bool? esPredeterminada,
    String? configuracionJson,
    DateTime? fechaCreacion,
    DateTime? fechaActualizacion,
  }) {
    return PrinterConfig(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      modelo: modelo ?? this.modelo,
      tipo: tipo ?? this.tipo,
      esPredeterminada: esPredeterminada ?? this.esPredeterminada,
      configuracionJson: configuracionJson ?? this.configuracionJson,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
    );
  }
}
