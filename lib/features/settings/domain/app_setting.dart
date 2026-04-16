class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;

  factory AppSetting.fromMap(Map<String, Object?> map) {
    return AppSetting(
      key: map['clave'] as String? ?? '',
      value: map['valor'] as String? ?? '',
      updatedAt: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'clave': key,
      'valor': value,
      'fecha_actualizacion': updatedAt.toIso8601String(),
    };
  }
}
