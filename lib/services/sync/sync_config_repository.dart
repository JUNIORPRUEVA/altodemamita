import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/backend_config.dart' as backend_config;
import '../../core/security/sensitive_storage.dart';
import '../../core/system/system_config_service.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_settings.dart';
import '../../models/sync/sync_runtime_state.dart';

class SyncConfigRepository {
  SyncConfigRepository({
    SettingsRepository? settingsRepository,
    Future<SharedPreferences> Function()? preferencesFactory,
    SensitiveStorage? sensitiveStorage,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _sensitiveStorage =
           sensitiveStorage ??
           SensitiveStorage(preferencesFactory: preferencesFactory),
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  static const syncBaseUrlKey = 'sync.base_url';
  static const defaultSyncBaseUrl = backend_config.BASE_URL;
  static const syncQueueRetrySecondsKey = 'sync.queue_retry_seconds';
  static const syncRealtimePollingSecondsKey = 'sync.realtime_polling_seconds';
  static const syncConflictStrategyKey = 'sync.conflict_strategy';
  static const syncLastErrorKey = 'sync.last_error';
  static const syncLastRunAtKey = 'sync.last_run_at';
  static const syncLastStatusKey = 'sync.last_status';

  static const _jwtTokenPreferenceKey = 'sync.jwt_token';
  static const _deviceIdPreferenceKey = 'sync.device_id';
  static const _cursorPreferencePrefix = 'sync.cursor.';

  static String normalizeBackendBaseUrl(String baseUrl) {
    return backend_config.normalizeBackendBaseUrl(baseUrl);
  }

  final SettingsRepository _settingsRepository;
  final SensitiveStorage _sensitiveStorage;
  final Future<SharedPreferences> Function() _preferencesFactory;

  Future<SharedPreferences?> _tryPreferences() async {
    try {
      return await _preferencesFactory();
    } on MissingPluginException {
      return null;
    }
  }

  Future<SyncSettings> loadSettings() async {
    final values = await _settingsRepository.fetchByKeys([
      syncQueueRetrySecondsKey,
      syncRealtimePollingSecondsKey,
      syncConflictStrategyKey,
    ]);
    final baseUrl = normalizeBackendBaseUrl(defaultSyncBaseUrl);

    final token = await _sensitiveStorage.read(_jwtTokenPreferenceKey) ?? '';
    final retrySeconds =
        int.tryParse(values[syncQueueRetrySecondsKey]?.value ?? '10') ?? 10;
    final pollingSeconds =
        int.tryParse(values[syncRealtimePollingSecondsKey]?.value ?? '5') ?? 5;

    return SyncSettings(
      baseUrl: baseUrl,
      jwtToken: token,
      queueRetryInterval: Duration(seconds: retrySeconds.clamp(3, 300)),
      realtimePollingInterval: Duration(seconds: pollingSeconds.clamp(3, 300)),
      conflictStrategy: SyncConflictStrategy.fromStorage(
        values[syncConflictStrategyKey]?.value,
      ),
      deviceId: await getOrCreateDeviceId(),
    );
  }

  Future<void> saveBaseUrl(String baseUrl) async {}

  Future<void> saveJwtToken(String jwtToken) async {
    await _sensitiveStorage.write(_jwtTokenPreferenceKey, jwtToken);
  }

  Future<void> clearJwtToken() async {
    await _sensitiveStorage.delete(_jwtTokenPreferenceKey);
  }

  Future<void> saveQueueRetryInterval(Duration interval) {
    return _settingsRepository.upsert(
      syncQueueRetrySecondsKey,
      interval.inSeconds.clamp(3, 300).toString(),
    );
  }

  Future<void> saveRealtimePollingInterval(Duration interval) {
    return _settingsRepository.upsert(
      syncRealtimePollingSecondsKey,
      interval.inSeconds.clamp(3, 300).toString(),
    );
  }

  Future<void> saveConflictStrategy(SyncConflictStrategy strategy) {
    return _settingsRepository.upsert(
      syncConflictStrategyKey,
      strategy.storageValue,
    );
  }

  Future<DateTime?> loadCursor(String scope) async {
    final prefs = await _tryPreferences();
    if (prefs == null) {
      return null;
    }
    final value = prefs.getString('$_cursorPreferencePrefix$scope');
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Future<void> saveCursor(String scope, DateTime timestamp) async {
    final prefs = await _tryPreferences();
    if (prefs == null) {
      return;
    }
    await prefs.setString(
      '$_cursorPreferencePrefix$scope',
      timestamp.toIso8601String(),
    );
  }

  Future<void> clearCursor(String scope) async {
    final prefs = await _tryPreferences();
    if (prefs == null) {
      return;
    }
    await prefs.remove('$_cursorPreferencePrefix$scope');
  }

  Future<void> clearCursors(Iterable<String> scopes) async {
    final normalizedScopes = scopes
        .map((scope) => scope.trim())
        .where((scope) => scope.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedScopes.isEmpty) {
      return;
    }

    final prefs = await _tryPreferences();
    if (prefs == null) {
      return;
    }
    for (final scope in normalizedScopes) {
      await prefs.remove('$_cursorPreferencePrefix$scope');
    }
  }

  Future<void> saveLastRun({
    String? errorMessage,
    SyncRuntimeStatus status = SyncRuntimeStatus.ok,
  }) async {
    if (SystemConfigService.instance.isReadOnly) {
      return;
    }

    await _settingsRepository.saveMultiple({
      syncLastRunAtKey: DateTime.now().toIso8601String(),
      syncLastErrorKey: errorMessage ?? '',
      syncLastStatusKey: status.name,
    });
  }

  Future<SyncRuntimeState> loadRuntimeState({
    bool isSyncing = false,
    int pendingCount = 0,
  }) async {
    final values = await _settingsRepository.fetchByKeys([
      syncLastRunAtKey,
      syncLastErrorKey,
      syncLastStatusKey,
    ]);
    final lastRunAt = DateTime.tryParse(values[syncLastRunAtKey]?.value ?? '');
    final lastError = values[syncLastErrorKey]?.value.trim();
    final normalizedStatus = values[syncLastStatusKey]?.value.trim().toLowerCase();
    final status = switch (normalizedStatus) {
      'error' => SyncRuntimeStatus.error,
      'pending' => SyncRuntimeStatus.pending,
      'syncing' => SyncRuntimeStatus.syncing,
      _ => SyncRuntimeStatus.ok,
    };

    return SyncRuntimeState(
      isSyncing: isSyncing,
      status: isSyncing ? SyncRuntimeStatus.syncing : status,
      lastSyncAt: lastRunAt,
      lastError: (lastError == null || lastError.isEmpty) ? null : lastError,
      pendingCount: pendingCount,
    );
  }

  Future<String> getOrCreateDeviceId() async {
    final random = Random.secure();
    final generated = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

    final prefs = await _tryPreferences();
    final current = prefs?.getString(_deviceIdPreferenceKey);
    if (current != null && current.trim().isNotEmpty) {
      return current;
    }

    await prefs?.setString(_deviceIdPreferenceKey, generated);
    return generated;
  }
}
