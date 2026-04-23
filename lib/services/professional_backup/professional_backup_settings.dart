class ProfessionalBackupSettings {
  const ProfessionalBackupSettings({
    required this.localBackupEnabled,
    required this.cloudBackupEnabled,
    required this.cloudBackupHour,
    required this.cloudBackupMinute,
    required this.lastCloudBackupDate,
  });

  final bool localBackupEnabled;
  final bool cloudBackupEnabled;
  final int cloudBackupHour;
  final int cloudBackupMinute;

  /// ISO-8601 calendar date: YYYY-MM-DD (local time).
  final String? lastCloudBackupDate;

  static const defaultHour = 2;
  static const defaultMinute = 0;

  factory ProfessionalBackupSettings.defaults() {
    return const ProfessionalBackupSettings(
      localBackupEnabled: true,
      cloudBackupEnabled: false,
      cloudBackupHour: defaultHour,
      cloudBackupMinute: defaultMinute,
      lastCloudBackupDate: null,
    );
  }

  ProfessionalBackupSettings copyWith({
    bool? localBackupEnabled,
    bool? cloudBackupEnabled,
    int? cloudBackupHour,
    int? cloudBackupMinute,
    String? lastCloudBackupDate,
  }) {
    return ProfessionalBackupSettings(
      localBackupEnabled: localBackupEnabled ?? this.localBackupEnabled,
      cloudBackupEnabled: cloudBackupEnabled ?? this.cloudBackupEnabled,
      cloudBackupHour: cloudBackupHour ?? this.cloudBackupHour,
      cloudBackupMinute: cloudBackupMinute ?? this.cloudBackupMinute,
      lastCloudBackupDate: lastCloudBackupDate ?? this.lastCloudBackupDate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'localBackupEnabled': localBackupEnabled,
      'cloudBackupEnabled': cloudBackupEnabled,
      'cloudBackupHour': cloudBackupHour,
      'cloudBackupMinute': cloudBackupMinute,
      'lastCloudBackupDate': lastCloudBackupDate,
    };
  }

  factory ProfessionalBackupSettings.fromJson(Map<String, dynamic> json) {
    final hour = (json['cloudBackupHour'] as num?)?.toInt() ?? defaultHour;
    final minute = (json['cloudBackupMinute'] as num?)?.toInt() ?? defaultMinute;

    int clampInt(int value, int min, int max) {
      if (value < min) return min;
      if (value > max) return max;
      return value;
    }

    final normalizedHour = clampInt(hour, 0, 23);
    final normalizedMinute = clampInt(minute, 0, 59);

    return ProfessionalBackupSettings(
      localBackupEnabled: (json['localBackupEnabled'] as bool?) ?? true,
      cloudBackupEnabled: (json['cloudBackupEnabled'] as bool?) ?? false,
      cloudBackupHour: normalizedHour,
      cloudBackupMinute: normalizedMinute,
      lastCloudBackupDate: (json['lastCloudBackupDate'] as String?)?.trim().isEmpty == true
          ? null
          : (json['lastCloudBackupDate'] as String?),
    );
  }

  String get cloudBackupTimeLabel {
    final hh = cloudBackupHour.toString().padLeft(2, '0');
    final mm = cloudBackupMinute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
