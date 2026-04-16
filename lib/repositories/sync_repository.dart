abstract class SyncRepository {
  String get scope;
  String get uploadPath;
  String get downloadPath;

  Future<List<Map<String, Object?>>> getPendingRecords();

  Future<void> markAsSynced(Iterable<String> syncIds);

  Future<void> markAsConflict(Iterable<String> syncIds);

  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records);
}
