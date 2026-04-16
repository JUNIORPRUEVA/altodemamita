import 'sync_connection_status.dart';

class SyncManagerState {
  const SyncManagerState({
    this.connectionStatus = SyncConnectionStatus.disconnected,
    this.pendingCount = 0,
    this.unresolvedConflictCount = 0,
    this.currentErrors = const [],
    this.isSyncing = false,
    this.dataVersion = 0,
    this.lastRealtimeEventAt,
  });

  final SyncConnectionStatus connectionStatus;
  final int pendingCount;
  final int unresolvedConflictCount;
  final List<String> currentErrors;
  final bool isSyncing;
  final int dataVersion;
  final DateTime? lastRealtimeEventAt;

  bool get hasConflicts => unresolvedConflictCount > 0;
  bool get hasErrors => currentErrors.isNotEmpty;

  SyncManagerState copyWith({
    SyncConnectionStatus? connectionStatus,
    int? pendingCount,
    int? unresolvedConflictCount,
    List<String>? currentErrors,
    bool? isSyncing,
    int? dataVersion,
    DateTime? lastRealtimeEventAt,
  }) {
    return SyncManagerState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      pendingCount: pendingCount ?? this.pendingCount,
      unresolvedConflictCount:
          unresolvedConflictCount ?? this.unresolvedConflictCount,
      currentErrors: currentErrors ?? this.currentErrors,
      isSyncing: isSyncing ?? this.isSyncing,
      dataVersion: dataVersion ?? this.dataVersion,
      lastRealtimeEventAt: lastRealtimeEventAt ?? this.lastRealtimeEventAt,
    );
  }
}