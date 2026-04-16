enum SyncStatus {
  pending,
  conflict,
  synced;

  String get storageValue => name;

  bool get isPending => this == SyncStatus.pending;
  bool get isConflict => this == SyncStatus.conflict;

  static SyncStatus fromStorage(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'pending':
        return SyncStatus.pending;
      case 'conflict':
        return SyncStatus.conflict;
      case 'synced':
      default:
        return SyncStatus.synced;
    }
  }
}
