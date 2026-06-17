class BackupMetadata {
  const BackupMetadata({
    required this.id,
    required this.filename,
    required this.filepath,
    required this.timestamp,
    required this.type, // 'startup', 'shutdown', 'manual'
    required this.sizeBytes,
    required this.databaseSize,
    required this.success,
    this.errorMessage,
  });

  final String id;
  final String filename;
  final String filepath;
  final DateTime timestamp;
  final String type;
  final int sizeBytes;
  final int databaseSize;
  final bool success;
  final String? errorMessage;

  String get formattedDate {
    return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024)
      return '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get localized {
    switch (type) {
      case 'module_entry':
        return 'Apertura de backup';
      case 'startup':
        return 'Inicio de aplicación';
      case 'shutdown':
        return 'Cierre de aplicación';
      case 'manual':
        return 'Manual';
      default:
        return type;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'filepath': filepath,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'sizeBytes': sizeBytes,
      'databaseSize': databaseSize,
      'success': success,
      'errorMessage': errorMessage,
    };
  }

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      id: json['id'] as String,
      filename: json['filename'] as String,
      filepath: json['filepath'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] as String,
      sizeBytes: json['sizeBytes'] as int,
      databaseSize: json['databaseSize'] as int,
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
