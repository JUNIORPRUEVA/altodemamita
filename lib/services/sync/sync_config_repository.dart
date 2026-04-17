import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/sensitive_storage.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_settings.dart';

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
  static const defaultSyncBaseUrl =
      'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api';
  static const syncQueueRetrySecondsKey = 'sync.queue_retry_seconds';
  static const syncRealtimePollingSecondsKey = 'sync.realtime_polling_seconds';
  static const syncConflictStrategyKey = 'sync.conflict_strategy';
  static const syncLastErrorKey = 'sync.last_error';
  static const syncLastRunAtKey = 'sync.last_run_at';

  static const _jwtTokenPreferenceKey = 'sync.jwt_token';
  static const _deviceIdPreferenceKey = 'sync.device_id';
  static const _cursorPreferencePrefix = 'sync.cursor.';

  final SettingsRepository _settingsRepository;
  final SensitiveStorage _sensitiveStorage;
  final Future<SharedPreferences> Function() _preferencesFactory;

  Future<SyncSettings> loadSettings() async {
    await _settingsRepository.ensureDefaults({
      syncBaseUrlKey: defaultSyncBaseUrl,
      syncQueueRetrySecondsKey: '10',
      syncRealtimePollingSecondsKey: '5',
      syncConflictStrategyKey: SyncConflictStrategy.manual.storageValue,
    });

    final values = await _settingsRepository.fetchByKeys([
      syncBaseUrlKey,
      syncQueueRetrySecondsKey,
      syncRealtimePollingSecondsKey,
      syncConflictStrategyKey,
    ]);
    final prefs = await _preferencesFactory();
    final storedBaseUrl = values[syncBaseUrlKey]?.value ?? '';
    final baseUrl = storedBaseUrl.trim().isEmpty
        ? defaultSyncBaseUrl
        : storedBaseUrl.trim();
    if (storedBaseUrl.trim().isEmpty) {
      await _settingsRepository.upsert(syncBaseUrlKey, baseUrl);
    }
    final token = await _sensitiveStorage.read(_jwtTokenPreferenceKey) ?? '';
    final retrySeconds =
        int.tryParse(values[syncQueueRetrySecondsKey]?.value ?? '') ?? 10;
    final pollingSeconds =
        int.tryParse(values[syncRealtimePollingSecondsKey]?.value ?? '') ?? 5;

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

  Future<void> saveBaseUrl(String baseUrl) {
    return _settingsRepository.upsert(syncBaseUrlKey, baseUrl.trim());
  }

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
    final prefs = await _preferencesFactory();
    final value = prefs.getString('$_cursorPreferencePrefix$scope');
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Future<void> saveCursor(String scope, DateTime timestamp) async {
    final prefs = await _preferencesFactory();
    await prefs.setString(
      '$_cursorPreferencePrefix$scope',
      timestamp.toIso8601String(),
    );
  }

  Future<void> saveLastRun({String? errorMessage}) async {
    await _settingsRepository.saveMultiple({
      syncLastRunAtKey: DateTime.now().toIso8601String(),
      syncLastErrorKey: errorMessage ?? '',
    });
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await _preferencesFactory();
    final current = prefs.getString(_deviceIdPreferenceKey);
    if (current != null && current.trim().isNotEmpty) {
      return current;
    }

    final random = Random.secure();
    final generated = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_deviceIdPreferenceKey, generated);
    return generated;
  }
}
