import 'sync_conflict_strategy.dart';

class SyncSettings {
  const SyncSettings({
    required this.baseUrl,
    required this.jwtToken,
    required this.queueRetryInterval,
    required this.realtimePollingInterval,
    required this.conflictStrategy,
    required this.deviceId,
  });

  final String baseUrl;
  final String jwtToken;
  final Duration queueRetryInterval;
  final Duration realtimePollingInterval;
  final SyncConflictStrategy conflictStrategy;
  final String deviceId;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get normalizedBaseUrl {
    final normalized = baseUrl.trim();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
