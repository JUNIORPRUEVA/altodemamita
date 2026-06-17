class SyncReport {
  const SyncReport({
    required this.startedAt,
    required this.finishedAt,
    this.uploadedRecords = 0,
    this.downloadedRecords = 0,
    this.pendingRecords = 0,
    this.warnings = const [],
    this.wasSkipped = false,
    this.hadConnectivityError = false,
    this.errorMessage,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int uploadedRecords;
  final int downloadedRecords;
  final int pendingRecords;
  final List<String> warnings;
  final bool wasSkipped;
  final bool hadConnectivityError;
  final String? errorMessage;

  bool get isSuccess => !wasSkipped && errorMessage == null;

  String get summary {
    if (wasSkipped) {
      return errorMessage ??
          'La sincronizacion fue omitida porque falta configuracion.';
    }
    if (errorMessage != null) {
      return errorMessage!;
    }
    if (warnings.isNotEmpty) {
      return 'Sincronizacion completada con advertencias. Subidos: $uploadedRecords, descargados: $downloadedRecords. ${warnings.join(' | ')}';
    }
    return 'Sincronizacion completada. Subidos: $uploadedRecords, descargados: $downloadedRecords.';
  }
}
