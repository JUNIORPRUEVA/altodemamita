class DiskInfo {
  const DiskInfo({
    required this.drive,
    required this.label,
    required this.totalSize,
    required this.freeSize,
    required this.isAvailable,
    this.isSystemDrive = false,
  });

  final String drive; // e.g., "C:", "D:"
  final String label; // Drive label/name
  final int totalSize; // in bytes
  final int freeSize; // in bytes
  final bool isAvailable;
  final bool isSystemDrive;

  double get usedPercentage {
    if (totalSize == 0) return 0;
    return ((totalSize - freeSize) / totalSize) * 100;
  }

  String get formattedTotal {
    return _formatBytes(totalSize);
  }

  String get formattedFree {
    return _formatBytes(freeSize);
  }

  String get formattedUsed {
    return _formatBytes(totalSize - freeSize);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get hasEnoughSpace => freeSize > 100 * 1024 * 1024; // At least 100 MB

  @override
  String toString() => '$drive ($label) - Free: $formattedFree / Total: $formattedTotal';
}
