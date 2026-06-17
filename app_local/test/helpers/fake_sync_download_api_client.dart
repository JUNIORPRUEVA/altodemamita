import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';

class FakeSyncDownloadApiClient extends SyncApiClient {
  int downloadCalls = 0;
  DateTime? requestedUpdatedSince;
  Map<String, DateTime?> requestedUpdatedSinceByScope = const {};
  Map<String, List<Map<String, dynamic>>> recordsByScope = {};
  DateTime serverTime = DateTime.utc(2026, 5, 5, 12);
  bool filterByScopeCursor = true;

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    downloadCalls += 1;
    requestedUpdatedSince = updatedSince;
    requestedUpdatedSinceByScope = Map<String, DateTime?>.from(
      updatedSinceByScope ?? const {},
    );

    final filtered = <String, List<Map<String, dynamic>>>{};
    final cursors = <String, DateTime?>{};
    for (final entry in recordsByScope.entries) {
      final scopeCursor = updatedSinceByScope?[entry.key] ?? updatedSince;
      final scopeRecords = entry.value
          .where((record) {
            if (!filterByScopeCursor || scopeCursor == null) {
              return true;
            }
            final updatedAt = DateTime.tryParse(
              record['updated_at']?.toString() ?? '',
            );
            return updatedAt != null && updatedAt.isAfter(scopeCursor);
          })
          .map((record) => Map<String, dynamic>.from(record))
          .toList(growable: false);
      filtered[entry.key] = scopeRecords;
      cursors[entry.key] = _resolveCursor(scopeRecords);
    }

    return SyncDownloadResponse(
      recordsByScope: filtered,
      serverTime: serverTime,
      scopeCursors: cursors,
    );
  }

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    return const SyncUploadResponse(returnedRecordsByScope: {});
  }

  DateTime _resolveCursor(List<Map<String, dynamic>> records) {
    var latest = serverTime;
    for (final record in records) {
      final updatedAt = DateTime.tryParse(
        record['updated_at']?.toString() ?? '',
      );
      if (updatedAt != null && updatedAt.isAfter(latest)) {
        latest = updatedAt;
      }
    }
    return latest;
  }
}
