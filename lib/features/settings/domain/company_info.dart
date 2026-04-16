/// Información de empresa
class CompanyInfo {
  const CompanyInfo({
    this.id,
    required this.nombre,
    this.telefono,
    this.direccion,
    this.logoBytesBase64,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int? id;
  final String nombre;
  final String? telefono;
  final String? direccion;
  final String? logoBytesBase64; // Base64 encoded image
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  factory CompanyInfo.empty() {
    final now = DateTime.now();
    return CompanyInfo(
      nombre: '',
      fechaCreacion: now,
      fechaActualizacion: now,
    );
  }

  factory CompanyInfo.fromMap(Map<String, Object?> map) {
    return CompanyInfo(
      id: map['id'] as int?,
      nombre: map['nombre'] as String? ?? '',
      telefono: map['telefono'] as String?,
      direccion: map['direccion'] as String?,
      logoBytesBase64: map['logo_base64'] as String?,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaActualizacion: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'nombre': nombre,
      'telefono': telefono,
      'direccion': direccion,
      'logo_base64': logoBytesBase64,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_actualizacion': fechaActualizacion.toIso8601String(),
    };
  }

  CompanyInfo copyWith({
    int? id,
    String? nombre,
    String? telefono,
    String? direccion,
    String? logoBytesBase64,
    DateTime? fechaCreacion,
    DateTime? fechaActualizacion,
  }) {
    return CompanyInfo(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      direccion: direccion ?? this.direccion,
      logoBytesBase64: logoBytesBase64 ?? this.logoBytesBase64,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
    );
  }
}
