enum SyncRuntimeStatus { ok, error, pending, syncing }

class SyncRuntimeState {
  const SyncRuntimeState({
    required this.isSyncing,
    required this.status,
    this.lastSyncAt,
    this.lastError,
    this.pendingCount = 0,
  });

  final bool isSyncing;
  final SyncRuntimeStatus status;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int pendingCount;

  bool get hasError => status == SyncRuntimeStatus.error;
  bool get hasPending => status == SyncRuntimeStatus.pending;
}