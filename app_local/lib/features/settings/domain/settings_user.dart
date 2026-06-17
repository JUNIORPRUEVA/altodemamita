/// Modelo de usuario para el módulo de settings
class SettingsUser {
  const SettingsUser({
    this.id,
    required this.nombre,
    required this.rol,
    this.telefono,
    this.email,
    this.activo = true,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int? id;
  final String nombre;
  final String rol; // 'admin' o 'operador'
  final String? telefono;
  final String? email;
  final bool activo;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  static const List<String> roles = ['admin', 'operador'];

  factory SettingsUser.empty() {
    final now = DateTime.now();
    return SettingsUser(
      nombre: '',
      rol: 'operador',
      fechaCreacion: now,
      fechaActualizacion: now,
    );
  }

  factory SettingsUser.fromMap(Map<String, Object?> map) {
    return SettingsUser(
      id: map['id'] as int?,
      nombre: map['nombre'] as String? ?? '',
      rol: map['rol'] as String? ?? 'operador',
      telefono: map['telefono'] as String?,
      email: map['email'] as String?,
      activo: (map['activo'] as int?) == 1,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaActualizacion: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'nombre': nombre,
      'rol': rol,
      'telefono': telefono,
      'email': email,
      'activo': activo ? 1 : 0,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_actualizacion': fechaActualizacion.toIso8601String(),
    };
  }

  SettingsUser copyWith({
    int? id,
    String? nombre,
    String? rol,
    String? telefono,
    String? email,
    bool? activo,
    DateTime? fechaCreacion,
    DateTime? fechaActualizacion,
  }) {
    return SettingsUser(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      rol: rol ?? this.rol,
      telefono: telefono ?? this.telefono,
      email: email ?? this.email,
      activo: activo ?? this.activo,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
    );
  }
}
