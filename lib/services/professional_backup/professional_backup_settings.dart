class ProfessionalBackupSettings {
  const ProfessionalBackupSettings({
    required this.localBackupEnabled,
  });

  final bool localBackupEnabled;

  factory ProfessionalBackupSettings.defaults() {
    return const ProfessionalBackupSettings(
      localBackupEnabled: true,
    );
  }

  ProfessionalBackupSettings copyWith({
    bool? localBackupEnabled,
  }) {
    return ProfessionalBackupSettings(
      localBackupEnabled: localBackupEnabled ?? this.localBackupEnabled,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'localBackupEnabled': localBackupEnabled,
    };
  }

  factory ProfessionalBackupSettings.fromJson(Map<String, dynamic> json) {
    return ProfessionalBackupSettings(
      localBackupEnabled: (json['localBackupEnabled'] as bool?) ?? true,
    );
  }
}
