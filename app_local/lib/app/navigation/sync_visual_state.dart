import '../../models/sync/sync_connection_status.dart';

enum SyncVisualState {
  hidden,
  offline,
}

class SyncVisualStateInput {
  const SyncVisualStateInput({
    required this.hasInternet,
    required this.backendReachable,
    required this.syncQueuePendingCount,
    required this.syncQueueFailedCount,
    required this.isSyncing,
    this.lastSyncAt,
  });

  final bool hasInternet;
  final bool backendReachable;
  final int syncQueuePendingCount;
  final int syncQueueFailedCount;
  final bool isSyncing;
  final DateTime? lastSyncAt;
}

SyncVisualStateInput buildSyncVisualStateInput({
  required SyncConnectionStatus connectionStatus,
  required int pendingCount,
  required int failedCount,
  required bool isSyncing,
  DateTime? lastSyncAt,
}) {
  final hasInternet = connectionStatus != SyncConnectionStatus.disconnected;
  final backendReachable = connectionStatus == SyncConnectionStatus.connected;

  return SyncVisualStateInput(
    hasInternet: hasInternet,
    backendReachable: backendReachable,
    syncQueuePendingCount: pendingCount,
    syncQueueFailedCount: failedCount,
    isSyncing: isSyncing,
    lastSyncAt: lastSyncAt,
  );
}

SyncVisualState getSyncVisualState(SyncVisualStateInput input) {
  if (!input.hasInternet) {
    return SyncVisualState.offline;
  }
  return SyncVisualState.hidden;
}

bool shouldShowOfflineChip({required bool hasInternet}) {
  return !hasInternet;
}

int countRealSyncFailures(Iterable<String> errors) {
  var total = 0;
  for (final raw in errors) {
    if (!isOfflineConnectivityMessage(raw)) {
      total += 1;
    }
  }
  return total;
}

bool isOfflineConnectivityMessage(String? message) {
  if (message == null) {
    return false;
  }

  final normalized = message.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }

  return normalized.contains('sin conexion') ||
      normalized.contains('sin conexión') ||
      normalized.contains('error de conexion con el servidor') ||
      normalized.contains('error de conexión con el servidor') ||
      normalized.contains('backend no disponible') ||
      normalized.contains('socket');
}

bool shouldShowLargeSyncBanner(SyncVisualState state) {
  return false;
}
