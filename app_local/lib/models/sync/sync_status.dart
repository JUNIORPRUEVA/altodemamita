enum SyncStatus {
  pending,
  failed,
  conflict,
  synced;

  String get storageValue => name;

  bool get isPending => this == SyncStatus.pending;
  bool get isFailed => this == SyncStatus.failed;
  bool get isConflict => this == SyncStatus.conflict;

  static SyncStatus fromStorage(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'pending':
      case 'pending_sync':
      case 'pending_create':
      case 'pending_update':
      case 'pending_delete':
        return SyncStatus.pending;
      case 'failed':
        return SyncStatus.failed;
      case 'conflict':
        return SyncStatus.conflict;
      case 'synced':
      default:
        return SyncStatus.synced;
    }
  }
}
