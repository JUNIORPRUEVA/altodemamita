class SyncReport {
  const SyncReport({
    required this.startedAt,
    required this.finishedAt,
    this.uploadedRecords = 0,
    this.downloadedRecords = 0,
    this.pendingRecords = 0,
    this.wasSkipped = false,
    this.hadConnectivityError = false,
    this.errorMessage,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int uploadedRecords;
  final int downloadedRecords;
  final int pendingRecords;
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
    return 'Sincronizacion completada. Subidos: $uploadedRecords, descargados: $downloadedRecords.';
  }
}
