abstract class SyncRepository {
  String get scope;
  String get uploadPath;
  String get downloadPath;

  Future<List<Map<String, Object?>>> getPendingRecords();

  Future<void> markAsSynced(Iterable<String> syncIds);

  Future<void> markAsConflict(Iterable<String> syncIds);

  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records);
}

class RemoteSyncDependencyException implements Exception {
  const RemoteSyncDependencyException({
    required this.scope,
    required this.recordSyncId,
    required this.missingScopes,
    required this.message,
  });

  final String scope;
  final String recordSyncId;
  final Set<String> missingScopes;
  final String message;

  @override
  String toString() => message;
}
