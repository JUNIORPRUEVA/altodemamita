enum SyncConflictStrategy {
  manual,
  lastWriteWins;

  String get storageValue {
    switch (this) {
      case SyncConflictStrategy.manual:
        return 'manual';
      case SyncConflictStrategy.lastWriteWins:
        return 'last_write_wins';
    }
  }

  String get apiValue => storageValue;

  static SyncConflictStrategy fromStorage(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'last_write_wins':
      case 'lastwritewins':
      case 'lww':
        return SyncConflictStrategy.lastWriteWins;
      case 'manual':
      default:
        return SyncConflictStrategy.manual;
    }
  }
}
