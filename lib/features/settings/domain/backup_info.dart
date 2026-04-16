/// Información de backup
class BackupInfo {
  const BackupInfo({
    this.id,
    required this.nombreArchivo,
    required this.fechaCreacion,
    required this.tamanoBytes,
    this.descripcion,
  });

  final int? id;
  final String nombreArchivo;
  final DateTime fechaCreacion;
  final int tamanoBytes;
  final String? descripcion;

  factory BackupInfo.fromMap(Map<String, Object?> map) {
    return BackupInfo(
      id: map['id'] as int?,
      nombreArchivo: map['nombre_archivo'] as String? ?? '',
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      tamanoBytes: map['tamano_bytes'] as int? ?? 0,
      descripcion: map['descripcion'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'nombre_archivo': nombreArchivo,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'tamano_bytes': tamanoBytes,
      'descripcion': descripcion,
    };
  }

  BackupInfo copyWith({
    int? id,
    String? nombreArchivo,
    DateTime? fechaCreacion,
    int? tamanoBytes,
    String? descripcion,
  }) {
    return BackupInfo(
      id: id ?? this.id,
      nombreArchivo: nombreArchivo ?? this.nombreArchivo,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      tamanoBytes: tamanoBytes ?? this.tamanoBytes,
      descripcion: descripcion ?? this.descripcion,
    );
  }

  String get tamanoFormato {
    if (tamanoBytes < 1024) return '$tamanoBytes B';
    if (tamanoBytes < 1024 * 1024) {
      return '${(tamanoBytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(tamanoBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get fechaFormato => _formatDateTime(fechaCreacion);

  static String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Información sobre el último backup
class BackupPreferences {
  const BackupPreferences({
    this.id,
    required this.ultimaFechaBackup,
    required this.autoBackupEnabled,
    required this.autoBackupIntervalDays,
    this.rutaBackupPersonalizada,
  });

  final int? id;
  final DateTime ultimaFechaBackup;
  final bool autoBackupEnabled;
  final int autoBackupIntervalDays;
  final String? rutaBackupPersonalizada;

  factory BackupPreferences.defaults() {
    return BackupPreferences(
      ultimaFechaBackup: DateTime.now(),
      autoBackupEnabled: true,
      autoBackupIntervalDays: 7,
    );
  }

  factory BackupPreferences.fromMap(Map<String, Object?> map) {
    return BackupPreferences(
      id: map['id'] as int?,
      ultimaFechaBackup: DateTime.parse(map['ultima_fecha_backup'] as String),
      autoBackupEnabled: (map['auto_backup_habilitado'] as int?) == 1,
      autoBackupIntervalDays: map['intervalo_dias'] as int? ?? 7,
      rutaBackupPersonalizada: map['ruta_personalizada'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'ultima_fecha_backup': ultimaFechaBackup.toIso8601String(),
      'auto_backup_habilitado': autoBackupEnabled ? 1 : 0,
      'intervalo_dias': autoBackupIntervalDays,
      'ruta_personalizada': rutaBackupPersonalizada,
    };
  }

  BackupPreferences copyWith({
    int? id,
    DateTime? ultimaFechaBackup,
    bool? autoBackupEnabled,
    int? autoBackupIntervalDays,
    String? rutaBackupPersonalizada,
  }) {
    return BackupPreferences(
      id: id ?? this.id,
      ultimaFechaBackup: ultimaFechaBackup ?? this.ultimaFechaBackup,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupIntervalDays: autoBackupIntervalDays ?? this.autoBackupIntervalDays,
      rutaBackupPersonalizada: rutaBackupPersonalizada ?? this.rutaBackupPersonalizada,
    );
  }
}
