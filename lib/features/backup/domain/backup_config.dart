class BackupConfig {
  const BackupConfig({
    required this.backupPath,
    required this.autoBackupEnabled,
    required this.autoBackupOnStartup,
    required this.autoBackupOnShutdown,
    required this.maxBackupRetention, // max number of auto backups to keep
    required this.lastBackupPath,
    required this.lastBackupTimestamp,
  });

  final String backupPath;
  final bool autoBackupEnabled;
  final bool autoBackupOnStartup;
  final bool autoBackupOnShutdown;
  final int maxBackupRetention;
  final String? lastBackupPath;
  final DateTime? lastBackupTimestamp;

  BackupConfig copyWith({
    String? backupPath,
    bool? autoBackupEnabled,
    bool? autoBackupOnStartup,
    bool? autoBackupOnShutdown,
    int? maxBackupRetention,
    String? lastBackupPath,
    DateTime? lastBackupTimestamp,
  }) {
    return BackupConfig(
      backupPath: backupPath ?? this.backupPath,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupOnStartup: autoBackupOnStartup ?? this.autoBackupOnStartup,
      autoBackupOnShutdown: autoBackupOnShutdown ?? this.autoBackupOnShutdown,
      maxBackupRetention: maxBackupRetention ?? this.maxBackupRetention,
      lastBackupPath: lastBackupPath ?? this.lastBackupPath,
      lastBackupTimestamp: lastBackupTimestamp ?? this.lastBackupTimestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'backupPath': backupPath,
      'autoBackupEnabled': autoBackupEnabled,
      'autoBackupOnStartup': autoBackupOnStartup,
      'autoBackupOnShutdown': autoBackupOnShutdown,
      'maxBackupRetention': maxBackupRetention,
      'lastBackupPath': lastBackupPath,
      'lastBackupTimestamp': lastBackupTimestamp?.toIso8601String(),
    };
  }

  factory BackupConfig.fromJson(Map<String, dynamic> json) {
    return BackupConfig(
      backupPath: json['backupPath'] as String,
      autoBackupEnabled: json['autoBackupEnabled'] as bool? ?? true,
      autoBackupOnStartup: json['autoBackupOnStartup'] as bool? ?? true,
      autoBackupOnShutdown: json['autoBackupOnShutdown'] as bool? ?? true,
      maxBackupRetention: json['maxBackupRetention'] as int? ?? 10,
      lastBackupPath: json['lastBackupPath'] as String?,
      lastBackupTimestamp: json['lastBackupTimestamp'] != null
          ? DateTime.parse(json['lastBackupTimestamp'] as String)
          : null,
    );
  }

  factory BackupConfig.defaults(String defaultBackupPath) {
    return BackupConfig(
      backupPath: defaultBackupPath,
      autoBackupEnabled: true,
      autoBackupOnStartup: true,
      autoBackupOnShutdown: true,
      maxBackupRetention: 10,
      lastBackupPath: null,
      lastBackupTimestamp: null,
    );
  }
}
