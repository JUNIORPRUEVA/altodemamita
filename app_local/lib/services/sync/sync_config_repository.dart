import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  static const syncDeviceIsPrimaryKey = 'sync.device_is_primary';
  static const syncDeviceCanWriteKey = 'sync.device_can_write';
  static const syncDeviceLastValidatedAtKey = 'sync.device_last_validated_at';
  static const syncDeviceReasonKey = 'sync.device_reason';
  static const syncLocalUploadBootstrapCompletedKey =
      'sync.local_upload_bootstrap_completed';
  static const syncLocalUploadBootstrapCompletedAtKey =
      'sync.local_upload_bootstrap_completed_at';
  static const syncLocalUploadBootstrapBackendUrlKey =
      'sync.local_upload_bootstrap_backend_url';
  static const syncLocalUploadBootstrapAppBuildKey =
      'sync.local_upload_bootstrap_app_build';
  static const syncLocalUploadBootstrapDatabaseNameKey =
      'sync.local_upload_bootstrap_database_name';
  static const syncLocalUploadBootstrapDatabaseHostKey =
      'sync.local_upload_bootstrap_database_host';
  static const syncLocalUploadBootstrapCloudFingerprintKey =
      'sync.local_upload_bootstrap_cloud_fingerprint';
  static const _legacySyncLocalUploadBootstrapVersionKey =
      'sync.local_upload_bootstrap_version';

  static const _jwtTokenPreferenceKey = 'sync.jwt_token';
  static const _deviceIdPreferenceKey = 'sync.device_id';
  static const _deviceIdFallbackKey = 'sync.device_id_fallback';
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
      syncBaseUrlKey,
      syncQueueRetrySecondsKey,
      syncRealtimePollingSecondsKey,
      syncConflictStrategyKey,
    ]);

    final configuredBaseUrl = values[syncBaseUrlKey]?.value;
    final baseUrl = normalizeBackendBaseUrl(
      (configuredBaseUrl == null || configuredBaseUrl.trim().isEmpty)
          ? defaultSyncBaseUrl
          : configuredBaseUrl,
    );

    final token = await _sensitiveStorage.read(_jwtTokenPreferenceKey) ?? '';
    final retrySeconds =
        int.tryParse(values[syncQueueRetrySecondsKey]?.value ?? '3') ?? 3;
    final pollingSeconds =
        int.tryParse(values[syncRealtimePollingSecondsKey]?.value ?? '2') ?? 2;

    return SyncSettings(
      baseUrl: baseUrl,
      jwtToken: token,
      queueRetryInterval: Duration(seconds: retrySeconds.clamp(1, 300)),
      realtimePollingInterval: Duration(seconds: pollingSeconds.clamp(1, 300)),
      conflictStrategy: SyncConflictStrategy.fromStorage(
        values[syncConflictStrategyKey]?.value,
      ),
      deviceId: await getOrCreateDeviceId(),
    );
  }

  Future<void> saveBaseUrl(String baseUrl) {
    final normalized = normalizeBackendBaseUrl(baseUrl);
    return _settingsRepository.upsert(syncBaseUrlKey, normalized);
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
      interval.inSeconds.clamp(1, 300).toString(),
    );
  }

  Future<void> saveRealtimePollingInterval(Duration interval) {
    return _settingsRepository.upsert(
      syncRealtimePollingSecondsKey,
      interval.inSeconds.clamp(1, 300).toString(),
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

  /// Devuelve la decisión local de bootstrap para la URL y nube actuales.
  Future<LocalUploadBootstrapDiagnostics> loadLocalUploadBootstrapDiagnostics({
    String? backendUrl,
    CloudIdentity? cloudIdentity,
  }) async {
    final prefs = await _tryPreferences();
    final completed =
        prefs?.getBool(syncLocalUploadBootstrapCompletedKey) ?? false;
    final savedUrl =
        prefs?.getString(syncLocalUploadBootstrapBackendUrlKey) ?? '';
    final savedDatabaseName =
        prefs?.getString(syncLocalUploadBootstrapDatabaseNameKey) ?? '';
    final savedDatabaseHost =
        prefs?.getString(syncLocalUploadBootstrapDatabaseHostKey) ?? '';
    final savedCloudFingerprint =
        prefs?.getString(syncLocalUploadBootstrapCloudFingerprintKey) ?? '';
    final normalizedSaved = normalizeBackendBaseUrl(savedUrl);
    final normalizedCurrent = normalizeBackendBaseUrl(backendUrl ?? '');
    final currentDatabaseName = cloudIdentity?.databaseName ?? '';
    final currentDatabaseHost = cloudIdentity?.databaseHost ?? '';
    final currentCloudFingerprint = cloudIdentity?.cloudFingerprint ?? '';
    final currentCloudData = cloudIdentity?.cloudData;
    final currentInitialUploadRequired =
        cloudIdentity?.initialUploadRequired ?? false;
    final reason = _resolveLocalUploadBootstrapReason(
      completed: completed,
      savedBackendUrl: normalizedSaved,
      currentBackendUrl: normalizedCurrent,
      savedDatabaseName: savedDatabaseName,
      currentDatabaseName: currentDatabaseName,
      savedCloudFingerprint: savedCloudFingerprint,
      currentCloudFingerprint: currentCloudFingerprint,
      currentCloudData: currentCloudData,
      currentInitialUploadRequired: currentInitialUploadRequired,
      requireCloudIdentity: cloudIdentity != null,
    );
    return LocalUploadBootstrapDiagnostics(
      completedFlag: completed,
      savedBackendUrl: normalizedSaved,
      currentBackendUrl: normalizedCurrent,
      savedDatabaseName: savedDatabaseName,
      savedDatabaseHost: savedDatabaseHost,
      savedCloudFingerprint: savedCloudFingerprint,
      currentDatabaseName: currentDatabaseName,
      currentDatabaseHost: currentDatabaseHost,
      currentCloudFingerprint: currentCloudFingerprint,
      currentCloudData: currentCloudData,
      currentInitialUploadRequired: currentInitialUploadRequired,
      shouldRun: reason != 'already_completed_same_cloud',
      reason: reason,
    );
  }

  Future<bool> isLocalUploadBootstrapCompleted({
    String? backendUrl,
    CloudIdentity? cloudIdentity,
  }) async {
    final diagnostics = await loadLocalUploadBootstrapDiagnostics(
      backendUrl: backendUrl,
      cloudIdentity: cloudIdentity,
    );
    if (diagnostics.reason == 'backend_url_changed') {
      debugPrint(
        '[SyncConfig] initial upload completed for different URL: '
        'saved="${diagnostics.savedBackendUrl}" '
        'current="${diagnostics.currentBackendUrl}" -> will re-run',
      );
    }
    return !diagnostics.shouldRun;
  }

  String _resolveLocalUploadBootstrapReason({
    required bool completed,
    required String savedBackendUrl,
    required String currentBackendUrl,
    required String savedDatabaseName,
    required String currentDatabaseName,
    required String savedCloudFingerprint,
    required String currentCloudFingerprint,
    required CloudData? currentCloudData,
    required bool currentInitialUploadRequired,
    required bool requireCloudIdentity,
  }) {
    if (!completed) {
      return 'not_completed';
    }
    if (currentInitialUploadRequired) {
      return 'backend_initial_upload_required';
    }
    if (currentCloudData?.isPrincipalDataEmpty == true) {
      return 'cloud_main_data_empty';
    }
    if (currentBackendUrl.isNotEmpty && savedBackendUrl != currentBackendUrl) {
      return 'backend_url_changed';
    }
    if (savedDatabaseName.trim().isEmpty &&
        savedCloudFingerprint.trim().isEmpty) {
      return 'old_completed_without_cloud_identity';
    }
    if (savedDatabaseName.trim().isEmpty) {
      return 'missing_saved_database_name';
    }
    if (savedCloudFingerprint.trim().isEmpty) {
      return 'missing_saved_cloud_fingerprint';
    }
    if (!requireCloudIdentity) {
      return 'already_completed_same_cloud';
    }
    if (currentDatabaseName.trim().isEmpty) {
      return 'missing_current_database_name';
    }
    if (currentCloudFingerprint.trim().isEmpty) {
      return 'missing_current_cloud_fingerprint';
    }
    if (savedDatabaseName != currentDatabaseName) {
      return 'database_name_changed';
    }
    if (savedCloudFingerprint != currentCloudFingerprint) {
      return 'cloud_fingerprint_changed';
    }
    return 'already_completed_same_cloud';
  }

  /// Marca la sincronización inicial como completada, guardando metadatos.
  Future<void> markLocalUploadBootstrapCompleted({
    String? backendUrl,
    CloudIdentity? cloudIdentity,
    String? version,
  }) async {
    final prefs = await _tryPreferences();
    if (prefs == null) return;

    await prefs.setBool(syncLocalUploadBootstrapCompletedKey, true);
    await prefs.setString(
      syncLocalUploadBootstrapCompletedAtKey,
      DateTime.now().toIso8601String(),
    );
    if (backendUrl != null && backendUrl.trim().isNotEmpty) {
      await prefs.setString(
        syncLocalUploadBootstrapBackendUrlKey,
        normalizeBackendBaseUrl(backendUrl),
      );
    }
    if (version != null && version.trim().isNotEmpty) {
      await prefs.setString(syncLocalUploadBootstrapAppBuildKey, version);
    }
    if (cloudIdentity != null) {
      await prefs.setString(
        syncLocalUploadBootstrapDatabaseNameKey,
        cloudIdentity.databaseName,
      );
      await prefs.setString(
        syncLocalUploadBootstrapDatabaseHostKey,
        cloudIdentity.databaseHost,
      );
      await prefs.setString(
        syncLocalUploadBootstrapCloudFingerprintKey,
        cloudIdentity.cloudFingerprint,
      );
    }
  }

  /// Resetea la bandera de sincronización inicial para DEV/testing.
  Future<void> resetLocalUploadBootstrapCompleted() async {
    final prefs = await _tryPreferences();
    if (prefs == null) return;

    await prefs.remove(syncLocalUploadBootstrapCompletedKey);
    await prefs.remove(syncLocalUploadBootstrapCompletedAtKey);
    await prefs.remove(syncLocalUploadBootstrapBackendUrlKey);
    await prefs.remove(syncLocalUploadBootstrapAppBuildKey);
    await prefs.remove(_legacySyncLocalUploadBootstrapVersionKey);
    await prefs.remove(syncLocalUploadBootstrapDatabaseNameKey);
    await prefs.remove(syncLocalUploadBootstrapDatabaseHostKey);
    await prefs.remove(syncLocalUploadBootstrapCloudFingerprintKey);
  }

  Future<void> saveLastRun({
    String? errorMessage,
    SyncRuntimeStatus status = SyncRuntimeStatus.ok,
  }) async {
    if (SystemConfigService.instance.isReadOnly ||
        !SystemConfigService.instance.canWrite) {
      return;
    }

    try {
      await _settingsRepository.saveMultiple({
        syncLastRunAtKey: DateTime.now().toIso8601String(),
        syncLastErrorKey: errorMessage ?? '',
        syncLastStatusKey: status.name,
      });
    } on DeviceWriteBlockedException {
      return;
    } on DatabaseException catch (error) {
      if (_isDatabaseClosedError(error)) {
        return;
      }
      rethrow;
    }
  }

  bool _isDatabaseClosedError(Object error) {
    return error.toString().toLowerCase().contains('database_closed');
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
    final normalizedStatus = values[syncLastStatusKey]?.value
        .trim()
        .toLowerCase();
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

  Future<DeviceWriteState> loadDeviceWriteState() async {
    final prefs = await _tryPreferences();
    if (prefs == null) {
      return const DeviceWriteState(
        isPrimary: false,
        canWrite: false,
        lastValidatedAt: null,
        reason: '',
      );
    }

    return DeviceWriteState(
      isPrimary:
          (prefs.getString(syncDeviceIsPrimaryKey) ?? '').trim() == 'true',
      canWrite: (prefs.getString(syncDeviceCanWriteKey) ?? '').trim() == 'true',
      lastValidatedAt: DateTime.tryParse(
        prefs.getString(syncDeviceLastValidatedAtKey) ?? '',
      ),
      reason: (prefs.getString(syncDeviceReasonKey) ?? '').trim(),
    );
  }

  Future<void> saveDeviceWriteState(DeviceWriteState state) async {
    final prefs = await _tryPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(syncDeviceIsPrimaryKey, state.isPrimary.toString());
    await prefs.setString(syncDeviceCanWriteKey, state.canWrite.toString());
    await prefs.setString(
      syncDeviceLastValidatedAtKey,
      state.lastValidatedAt?.toIso8601String() ?? '',
    );
    await prefs.setString(syncDeviceReasonKey, state.reason);
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
      debugPrint(
        '[device-id] source=SharedPreferences value=${current.trim()}',
      );
      // Backup to SQLite for cross-login recovery; ignored if device not yet
      // authorized (bootstrap state — SharedPreferences is the primary store).
      try {
        await _settingsRepository.upsert(_deviceIdFallbackKey, current.trim());
      } on DeviceWriteBlockedException {
        // Not yet authorized — silently skip SQLite backup.
      }
      return current;
    }

    final fallback = (await _settingsRepository.fetchByKeys([
      _deviceIdFallbackKey,
    ]))[_deviceIdFallbackKey]?.value.trim();
    if (fallback != null && fallback.isNotEmpty) {
      debugPrint('[device-id] source=SQLite fallback value=$fallback');
      await prefs?.setString(_deviceIdPreferenceKey, fallback);
      return fallback;
    }

    await prefs?.setString(_deviceIdPreferenceKey, generated);
    debugPrint('[device-id] source=generated value=$generated');
    try {
      await _settingsRepository.upsert(_deviceIdFallbackKey, generated);
    } on DeviceWriteBlockedException {
      // Not yet authorized — device ID is safely persisted in SharedPreferences.
    }
    return generated;
  }

  Future<void> clearSyncRuntimeState() async {
    final prefs = await _tryPreferences();
    if (prefs != null) {
      final cursorKeys = prefs
          .getKeys()
          .where((key) => key.startsWith(_cursorPreferencePrefix))
          .toList(growable: false);
      for (final key in cursorKeys) {
        await prefs.remove(key);
      }

      await prefs.remove(syncDeviceIsPrimaryKey);
      await prefs.remove(syncDeviceCanWriteKey);
      await prefs.remove(syncDeviceLastValidatedAtKey);
      await prefs.remove(syncDeviceReasonKey);
      await resetLocalUploadBootstrapCompleted();
    }

    await _settingsRepository.saveMultiple({
      syncLastErrorKey: '',
      syncLastRunAtKey: '',
      syncLastStatusKey: SyncRuntimeStatus.pending.name,
    });
  }

  Future<String> rotateDeviceId() async {
    final random = Random.secure();
    final generated = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

    final prefs = await _tryPreferences();
    await prefs?.setString(_deviceIdPreferenceKey, generated);
    try {
      await _settingsRepository.upsert(_deviceIdFallbackKey, generated);
    } on DeviceWriteBlockedException {
      // Device not yet authorized; SharedPreferences holds the new ID safely.
    }
    await clearSyncRuntimeState();
    return generated;
  }
}

class LocalUploadBootstrapDiagnostics {
  const LocalUploadBootstrapDiagnostics({
    required this.completedFlag,
    required this.savedBackendUrl,
    required this.currentBackendUrl,
    required this.savedDatabaseName,
    required this.savedDatabaseHost,
    required this.savedCloudFingerprint,
    required this.currentDatabaseName,
    required this.currentDatabaseHost,
    required this.currentCloudFingerprint,
    required this.currentCloudData,
    required this.currentInitialUploadRequired,
    required this.shouldRun,
    required this.reason,
  });

  final bool completedFlag;
  final String savedBackendUrl;
  final String currentBackendUrl;
  final String savedDatabaseName;
  final String savedDatabaseHost;
  final String savedCloudFingerprint;
  final String currentDatabaseName;
  final String currentDatabaseHost;
  final String currentCloudFingerprint;
  final CloudData? currentCloudData;
  final bool currentInitialUploadRequired;
  final bool shouldRun;
  final String reason;
}

class CloudIdentity {
  const CloudIdentity({
    required this.databaseName,
    required this.databaseHost,
    required this.cloudFingerprint,
    required this.cloudData,
    required this.initialUploadRequired,
  });

  final String databaseName;
  final String databaseHost;
  final String cloudFingerprint;
  final CloudData? cloudData;
  final bool initialUploadRequired;

  bool get isComplete =>
      databaseName.trim().isNotEmpty && cloudFingerprint.trim().isNotEmpty;
}

class CloudData {
  const CloudData({
    required this.clients,
    required this.sellers,
    required this.lots,
    required this.sales,
    required this.installments,
    required this.payments,
    required this.syncBatches,
  });

  final int clients;
  final int sellers;
  final int lots;
  final int sales;
  final int installments;
  final int payments;
  final int syncBatches;

  bool get isPrincipalDataEmpty =>
      clients == 0 &&
      sellers == 0 &&
      lots == 0 &&
      sales == 0 &&
      installments == 0 &&
      payments == 0 &&
      syncBatches == 0;

  @override
  String toString() {
    return 'clients=$clients sellers=$sellers lots=$lots sales=$sales '
        'installments=$installments payments=$payments syncBatches=$syncBatches';
  }
}

class DeviceWriteState {
  const DeviceWriteState({
    required this.isPrimary,
    required this.canWrite,
    required this.lastValidatedAt,
    required this.reason,
  });

  final bool isPrimary;
  final bool canWrite;
  final DateTime? lastValidatedAt;
  final String reason;
}
