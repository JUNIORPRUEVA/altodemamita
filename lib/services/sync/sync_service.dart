import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/config/app_flags.dart';
import '../../core/config/backend_config.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import '../../core/network/backend_http_client.dart';
import '../../core/system/system_config_service.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_report.dart';
import '../../models/sync/sync_settings.dart';
import '../../models/sync/sync_runtime_state.dart';
import '../../repositories/sync_repository.dart';
import 'sync_api_client.dart';
import 'sync_config_repository.dart';
import 'sync_logger.dart';
import 'sync_queue_service.dart';

class SyncService {
  static const bool _downloadFromCloudEnabled = allowCloudPull;
  static const Set<String> _tombstoneRepairScopes = {
    'products',
    'sales',
    'installments',
    'payments',
  };
  static const String cloudLoginRequiredMessage =
      'Debe iniciar sesión en la nube para sincronizar.';
  static const String deviceAuthorizationRequiredMessage =
      'La sincronizacion cloud anterior esta desactivada.';

  SyncService({
    required List<SyncRepository> repositories,
    Future<void> Function(SyncReport report)? onSyncFinished,
    Future<void> Function(String reason)? onCloudSessionExpired,
    SyncConfigRepository? configRepository,
    SyncApiClient? apiClient,
    SyncQueueService? syncQueueService,
    AppDatabase? appDatabase,
  }) : _repositories = repositories,
       _onSyncFinished = onSyncFinished,
       _onCloudSessionExpired = onCloudSessionExpired,
       _configRepository = configRepository ?? SyncConfigRepository(),
       _apiClient = apiClient ?? SyncApiClient(),
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _appDatabase = appDatabase ?? AppDatabase.instance {
    for (final repository in repositories) {
      _syncQueueService.registerRepository(repository);
      _repositoriesByScope[repository.scope] = repository;
    }
  }

  final List<SyncRepository> _repositories;
  final Map<String, SyncRepository> _repositoriesByScope = {};
  final Future<void> Function(SyncReport report)? _onSyncFinished;
  final Future<void> Function(String reason)? _onCloudSessionExpired;
  final SyncConfigRepository _configRepository;
  final SyncApiClient _apiClient;
  final SyncQueueService _syncQueueService;
  final AppDatabase _appDatabase;
  final SyncLogger _syncLogger = SyncLogger.instance;
  List<String> _lastScopeWarnings = const [];
  bool _isSyncing = false;
  bool _cloudSessionInvalidated = false;
  bool _didExecuteCloudDownloadRequest = false;
  SyncReport? _lastReport;

  bool get isSyncing => _isSyncing;
  SyncReport? get lastReport => _lastReport;

  Future<String?> startupBlockReason() async {
    final settings = await _configRepository.loadSettings();
    if (!settings.isConfigured) {
      return _buildMissingConfigurationMessage(settings);
    }
    return null;
  }

  /// Reinicia el estado de sesión de nube para que un nuevo JWT pueda
  /// activar la sincronización. Llamar después de vincular exitosamente.
  void resetCloudSession() {
    _cloudSessionInvalidated = false;
  }

  Future<SyncRuntimeState> get runtimeState async {
    return _configRepository.loadRuntimeState(
      isSyncing: _isSyncing,
      pendingCount: await _syncQueueService.pendingCount(),
    );
  }

  Future<SyncReport> fullSync() {
    return syncNow(forceFullDownload: true);
  }

  Future<SyncReport> syncNow({bool forceFullDownload = false}) async {
    if (_isSyncing) {
      return _lastReport ??
          SyncReport(
            startedAt: DateTime.now(),
            finishedAt: DateTime.now(),
            wasSkipped: true,
            errorMessage: 'Ya hay una sincronizacion en progreso.',
          );
    }

    _isSyncing = true;
    final startedAt = DateTime.now();
    await _configRepository.saveLastRun(status: SyncRuntimeStatus.syncing);
    await _syncLogger.log(
      action: forceFullDownload ? 'fullSync' : 'syncNow',
      entity: 'sync',
      result: 'started',
    );
    try {
      final settings = await _configRepository.loadSettings();
      if (!settings.isConfigured) {
        debugPrint(
          '[Sync] sync blocked because no jwt/config. '
          'hasBaseUrl=${settings.baseUrl.trim().isNotEmpty}, '
          'hasJwt=${settings.jwtToken.trim().isNotEmpty}',
        );
        final skipped = SyncReport(
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          wasSkipped: true,
          errorMessage: _buildMissingConfigurationMessage(settings),
        );
        await _configRepository.saveLastRun(
          errorMessage: skipped.errorMessage,
          status: SyncRuntimeStatus.pending,
        );
        _lastReport = skipped;
        final notify = _onSyncFinished;
        if (notify != null) {
          unawaited(notify(skipped));
        }
        return skipped;
      }

      await _refreshJwtTokenIfNeeded(settings);
      final refreshedSettings = await _configRepository.loadSettings();
      if (refreshedSettings.jwtToken.trim().isEmpty) {
        debugPrint('[Sync] sync blocked because no jwt after refresh check.');
        final skipped = SyncReport(
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          wasSkipped: true,
          errorMessage: cloudLoginRequiredMessage,
        );
        await _configRepository.saveLastRun(
          errorMessage: skipped.errorMessage,
          status: SyncRuntimeStatus.pending,
        );
        _lastReport = skipped;
        final notify = _onSyncFinished;
        if (notify != null) {
          unawaited(notify(skipped));
        }
        return skipped;
      }
      debugPrint('[Sync] sync started with valid jwt.');

      final shouldRunPreUploadFullDownload =
          _downloadFromCloudEnabled &&
          (forceFullDownload ||
              await _syncQueueService.hasLegacyDeleteBacklog(
                scopes: _repositoriesByScope.keys,
              ));

      var uploadedCount = 0;
      var downloadedCount = 0;
      if (shouldRunPreUploadFullDownload) {
        downloadedCount += await downloadUpdates(forceFullDownload: true);
        uploadedCount = await uploadPendingData();
        downloadedCount += await downloadUpdates();
      } else {
        uploadedCount = await uploadPendingData();
        downloadedCount = _downloadFromCloudEnabled
            ? await downloadUpdates(forceFullDownload: forceFullDownload)
            : 0;
      }
      final warnings = List<String>.of(_lastScopeWarnings);
      final pendingRecords = await _syncQueueService.pendingCount();
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        uploadedRecords: uploadedCount,
        downloadedRecords: downloadedCount,
        pendingRecords: pendingRecords,
        warnings: warnings,
      );
      await _configRepository.saveLastRun();
      await _syncLogger.log(
        action: forceFullDownload ? 'fullSync' : 'syncNow',
        entity: 'sync',
        result: pendingRecords > 0 ? 'pending' : 'ok',
        extra: {
          'uploadedRecords': uploadedCount,
          'downloadedRecords': downloadedCount,
          'pendingRecords': pendingRecords,
        },
      );
      await _configRepository.saveLastRun(
        status: pendingRecords > 0
            ? SyncRuntimeStatus.pending
            : SyncRuntimeStatus.ok,
      );
      _lastReport = report;
      final notify = _onSyncFinished;
      if (notify != null) {
        unawaited(notify(report));
      }
      return report;
    } on SocketException {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        hadConnectivityError: true,
        errorMessage: serverConnectionErrorMessage,
      );
      await _configRepository.saveLastRun(
        errorMessage: report.errorMessage,
        status: SyncRuntimeStatus.error,
      );
      await _syncLogger.log(
        action: forceFullDownload ? 'fullSync' : 'syncNow',
        entity: 'sync',
        result: 'error',
        error: report.errorMessage,
      );
      _lastReport = report;
      final notify = _onSyncFinished;
      if (notify != null) {
        unawaited(notify(report));
      }
      return report;
    } on HttpException catch (error) {
      _lastScopeWarnings = const [];
      if (_isDeviceUnauthorizedSyncError(error)) {
        final report = SyncReport(
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          wasSkipped: true,
          errorMessage: deviceAuthorizationRequiredMessage,
        );
        await _configRepository.saveLastRun(
          errorMessage: report.errorMessage,
          status: SyncRuntimeStatus.pending,
        );
        await _syncLogger.log(
          action: forceFullDownload ? 'fullSync' : 'syncNow',
          entity: 'sync',
          result: 'pending',
          error: report.errorMessage,
          extra: {'reason': 'device_not_authorized'},
        );
        _lastReport = report;
        final notify = _onSyncFinished;
        if (notify != null) {
          unawaited(notify(report));
        }
        return report;
      }

      if (_isUnauthorizedSyncError(error)) {
        await _invalidateCloudSession(
          'La sesion de nube vencio o fue rechazada por el backend.',
        );
        final report = SyncReport(
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          wasSkipped: true,
          errorMessage:
              'La nube rechazo la sincronizacion con la credencial actual. Inicia sesion en linea nuevamente para reactivar la sincronizacion y reunificar los datos.',
        );
        await _configRepository.saveLastRun(
          errorMessage: report.errorMessage,
          status: SyncRuntimeStatus.error,
        );
        await _syncLogger.log(
          action: forceFullDownload ? 'fullSync' : 'syncNow',
          entity: 'sync',
          result: 'error',
          error: report.errorMessage,
        );
        _lastReport = report;
        final notify = _onSyncFinished;
        if (notify != null) {
          unawaited(notify(report));
        }
        return report;
      }

      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        errorMessage: serverConnectionErrorMessage,
      );
      await _configRepository.saveLastRun(
        errorMessage: report.errorMessage,
        status: SyncRuntimeStatus.error,
      );
      await _syncLogger.log(
        action: forceFullDownload ? 'fullSync' : 'syncNow',
        entity: 'sync',
        result: 'error',
        error: report.errorMessage,
      );
      _lastReport = report;
      final notify = _onSyncFinished;
      if (notify != null) {
        unawaited(notify(report));
      }
      return report;
    } on ReadOnlyModeException {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        wasSkipped: true,
        errorMessage: 'Sistema en modo solo lectura',
      );
      await _configRepository.saveLastRun(
        errorMessage: report.errorMessage,
        status: SyncRuntimeStatus.pending,
      );
      _lastReport = report;
      final notify = _onSyncFinished;
      if (notify != null) {
        unawaited(notify(report));
      }
      return report;
    } catch (error) {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        errorMessage: serverConnectionErrorMessage,
      );
      await _configRepository.saveLastRun(
        errorMessage: report.errorMessage,
        status: SyncRuntimeStatus.error,
      );
      await _syncLogger.log(
        action: forceFullDownload ? 'fullSync' : 'syncNow',
        entity: 'sync',
        result: 'error',
        error: report.errorMessage,
      );
      _lastReport = report;
      final notify = _onSyncFinished;
      if (notify != null) {
        unawaited(notify(report));
      }
      return report;
    } finally {
      _isSyncing = false;
    }
  }

  static const Duration _jwtRefreshThreshold = Duration(hours: 6);

  bool _isJwtExpiringSoon(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return false;
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (payload is! Map) {
        return false;
      }
      final expRaw = payload['exp'];
      final expSeconds = expRaw is num
          ? expRaw.toInt()
          : int.tryParse('$expRaw');
      if (expSeconds == null) {
        return false;
      }
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000);
      return expiresAt.isBefore(DateTime.now().add(_jwtRefreshThreshold));
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshJwtTokenIfNeeded(SyncSettings settings) async {
    final token = settings.jwtToken.trim();
    if (token.isEmpty) {
      return;
    }

    if (!_isJwtExpiringSoon(token)) {
      return;
    }

    try {
      final refreshed = await _requestJwtRefresh(settings);
      if (refreshed != null && refreshed.trim().isNotEmpty) {
        await _configRepository.saveJwtToken(refreshed.trim());
      }
    } catch (_) {
      // If refresh fails, keep the current token and let sync proceed.
    }
  }

  Future<String?> _requestJwtRefresh(SyncSettings settings) async {
    final refreshUri = Uri.parse('${settings.normalizedBaseUrl}/auth/refresh');
    final httpClient = createBackendHttpClient(
      connectionTimeout: const Duration(seconds: 8),
      idleTimeout: const Duration(seconds: 10),
    );
    try {
      final request = await httpClient.postUrl(refreshUri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      request.write(
        jsonEncode({
          'token': settings.jwtToken.trim(),
          'clientType': 'desktop',
        }),
      );

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(responseBody);
      } catch (_) {
        return null;
      }

      final unwrapped =
          decoded is Map<String, dynamic> && decoded.containsKey('success')
          ? decoded['data']
          : decoded;

      if (unwrapped is! Map) {
        return null;
      }

      final newToken = unwrapped['accessToken']?.toString() ?? '';
      if (newToken.trim().isEmpty) {
        return null;
      }
      return newToken.trim();
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<int> uploadPendingData() async {
    return _syncQueueService.syncPending(scopes: _repositoriesByScope.keys);
  }

  Future<int> syncPending() {
    return _syncQueueService.syncPending(scopes: _repositoriesByScope.keys);
  }

  Future<int> downloadUpdates({bool forceFullDownload = false}) async {
    if (!_downloadFromCloudEnabled) {
      return 0;
    }
    return downloadUpdatesForScopes(
      _repositoriesByScope.keys,
      forceFullDownload: forceFullDownload,
    );
  }

  Future<int> forceFullDownloadFromCloud() async {
    if (!_downloadFromCloudEnabled) {
      throw StateError(
        'Descarga desde la nube deshabilitada (ALLOW_CLOUD_PULL=false).',
      );
    }
    _didExecuteCloudDownloadRequest = false;
    final downloaded = await downloadUpdates(forceFullDownload: true);
    if (!_didExecuteCloudDownloadRequest) {
      throw StateError('No se ejecutó descarga desde la nube.');
    }
    return downloaded;
  }

  Future<int> downloadUpdatesForScopes(
    Iterable<String> scopes, {
    bool forceFullDownload = false,
    bool allowRecoveryPass = true,
  }) async {
    if (!_downloadFromCloudEnabled) {
      return 0;
    }
    final settings = await _configRepository.loadSettings();
    final targetScopes = scopes.toSet();
    _lastScopeWarnings = const [];
    if (!settings.isConfigured) {
      debugPrint(
        '[Sync] download blocked because no jwt/config. '
        'hasBaseUrl=${settings.baseUrl.trim().isNotEmpty}, '
        'hasJwt=${settings.jwtToken.trim().isNotEmpty}',
      );
      await _syncLogger.log(
        action: 'download-blocked',
        entity: targetScopes.join(','),
        result: 'pending',
        error: _buildMissingConfigurationMessage(settings),
      );
      return 0;
    }
    if (targetScopes.isEmpty) {
      return 0;
    }

    await _syncLogger.log(
      action: forceFullDownload ? 'download-full-start' : 'download-start',
      entity: targetScopes.join(','),
      result: 'started',
      extra: {
        'scopeCount': targetScopes.length,
        'forceFullDownload': forceFullDownload,
      },
    );

    if (forceFullDownload) {
      await _configRepository.clearCursors(targetScopes);
    }

    if (await _shouldForceFullBusinessDownload(targetScopes)) {
      for (final scope in const [
        'sellers',
        'products',
        'sales',
        'installments',
        'payments',
      ]) {
        if (targetScopes.contains(scope)) {
          await _configRepository.clearCursor(scope);
        }
      }
    }

    final cursorBeforeByScope = <String, DateTime?>{};
    for (final scope in targetScopes) {
      cursorBeforeByScope[scope] = await _configRepository.loadCursor(scope);
    }
    final cascadedFullScopes = _buildDependentFullDownloadScopes(
      targetScopes,
      cursorBeforeByScope,
    );
    if (cascadedFullScopes.isNotEmpty) {
      await _configRepository.clearCursors(cascadedFullScopes);
      for (final scope in cascadedFullScopes) {
        cursorBeforeByScope[scope] = null;
      }
    }

    const requiredScopesForAudit = <String>{
      'sellers',
      'products',
      'clients',
      'sales',
      'payments',
      'installments',
    };

    debugPrint('[sync-download] START');
    debugPrint('[sync-download] URL=${settings.normalizedBaseUrl}/sync/download');
    debugPrint(
      '[sync-download] x-device-id=${settings.deviceId.trim().isEmpty ? '<empty>' : settings.deviceId.trim()}',
    );

    late final SyncDownloadResponse response;
    try {
      _didExecuteCloudDownloadRequest = true;
      response = await _apiClient.downloadChanges(
        settings: settings,
        updatedSinceByScope: cursorBeforeByScope,
      );
    } on HttpException catch (error) {
      if (_isUnauthorizedSyncError(error)) {
        await _invalidateCloudSession(
          'La sesion de nube vencio o fue rechazada por el backend.',
        );
      }
      rethrow;
    }

    final cloudCountsByScope = <String, int>{
      for (final scope in targetScopes)
        scope: response.supportsScope(scope)
            ? response.recordsForScope(scope).length
            : 0,
    };

    for (final scope in cloudCountsByScope.keys) {
      debugPrint(
        '[sync-download] CLOUD_COUNT scope=$scope records=${cloudCountsByScope[scope] ?? 0}',
      );
    }

    var downloadedRecords = 0;
    final scopeWarnings = <String>[];
    final retryScopes = <String>{};

    for (final repository in _repositories) {
      if (!targetScopes.contains(repository.scope)) {
        continue;
      }

      try {
        final cursorBefore = cursorBeforeByScope[repository.scope];
        await _syncLogger.log(
          action: 'download-scope-start',
          entity: repository.scope,
          result: 'started',
          extra: {'cursor_before': cursorBefore?.toIso8601String()},
        );

        if (!response.supportsScope(repository.scope)) {
          await _syncLogger.log(
            action: 'download-scope',
            entity: repository.scope,
            result: 'unsupported',
          );
          continue;
        }

        final scopeRecords = _prepareScopeRecordsForApply(
          repository.scope,
          response.recordsForScope(repository.scope),
        );

        if (scopeRecords.isNotEmpty) {
          await repository.mergeRemoteRecords(scopeRecords);
          downloadedRecords += scopeRecords.length;
        }

        debugPrint(
          '[sync-download] LOCAL_APPLY scope=${repository.scope} inserted_or_updated=${scopeRecords.length}',
        );

        final nextCursor =
            response.cursorForScope(repository.scope) ??
            _findLatestTimestamp(scopeRecords) ??
            response.serverTime;
        if (nextCursor != null) {
          await _configRepository.saveCursor(repository.scope, nextCursor);
        }

        await _syncLogger.log(
          action: 'download-scope',
          entity: repository.scope,
          result: scopeRecords.isNotEmpty ? 'ok' : 'idle',
          extra: {
            'records': scopeRecords.length,
            'cursor_before': cursorBefore?.toIso8601String(),
            'cursor_after': nextCursor?.toIso8601String(),
          },
        );
      } catch (error) {
        if (error is RemoteSyncDependencyException) {
          final recoveryScopes = _expandRecoveryScopes({
            repository.scope,
            ...error.missingScopes,
          }).intersection(targetScopes);
          if (recoveryScopes.isNotEmpty) {
            await _configRepository.clearCursors(recoveryScopes);
            retryScopes.addAll(recoveryScopes);
          }
          await _syncLogger.log(
            action: 'download-scope',
            entity: repository.scope,
            result: 'retry',
            error: error.toString(),
            extra: {'retry_scopes': recoveryScopes.toList()},
          );
          continue;
        }
        await _syncLogger.log(
          action: 'download-scope',
          entity: repository.scope,
          result: 'error',
          error: error.toString(),
        );
        scopeWarnings.add(
          'No se pudieron aplicar cambios remotos de ${repository.scope}: $error',
        );
      }
    }

    if (retryScopes.isNotEmpty && allowRecoveryPass) {
      downloadedRecords += await downloadUpdatesForScopes(
        retryScopes,
        forceFullDownload: true,
        allowRecoveryPass: false,
      );
    }

    if (forceFullDownload) {
      downloadedRecords += await _repairMissingRemoteTombstones(
        settings: settings,
        targetScopes: targetScopes,
      );
    }

    _lastScopeWarnings = scopeWarnings;

    await _syncLogger.log(
      action: forceFullDownload
          ? 'download-full-complete'
          : 'download-complete',
      entity: targetScopes.join(','),
      result: scopeWarnings.isEmpty ? 'ok' : 'warning',
      extra: {
        'downloadedRecords': downloadedRecords,
        'warnings': scopeWarnings.length,
      },
    );

    final requiredScopesAllZero = requiredScopesForAudit.every(
      (scope) => (cloudCountsByScope[scope] ?? 0) == 0,
    );
    if (requiredScopesAllZero) {
      debugPrint(
        '[sync-download] WARNING required scopes (sellers, products, clients, sales, payments, installments) returned 0 records.',
      );
    }

    return downloadedRecords;
  }

  Future<int> _repairMissingRemoteTombstones({
    required SyncSettings settings,
    required Set<String> targetScopes,
  }) async {
    final repairScopes = targetScopes.intersection(_tombstoneRepairScopes);
    if (repairScopes.isEmpty) {
      return 0;
    }

    final epochCursor = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final epochByScope = <String, DateTime?>{
      for (final scope in repairScopes) scope: epochCursor,
    };

    final response = await _apiClient.downloadChanges(
      settings: settings,
      updatedSinceByScope: epochByScope,
    );

    var repairedRecords = 0;
    for (final repository in _repositories) {
      if (!repairScopes.contains(repository.scope)) {
        continue;
      }
      if (!response.supportsScope(repository.scope)) {
        continue;
      }

      final tombstones = response
          .recordsForScope(repository.scope)
          .where(_isRemoteDeleteRecord)
          .toList(growable: false);
      if (tombstones.isEmpty) {
        continue;
      }

      final prepared = _prepareScopeRecordsForApply(repository.scope, tombstones);
      await repository.mergeRemoteRecords(prepared);
      repairedRecords += prepared.length;

      final repairCursor =
          response.cursorForScope(repository.scope) ??
          _findLatestTimestamp(tombstones);
      if (repairCursor != null) {
        final currentCursor = await _configRepository.loadCursor(repository.scope);
        if (currentCursor == null || repairCursor.isAfter(currentCursor)) {
          await _configRepository.saveCursor(repository.scope, repairCursor);
        }
      }

      await _syncLogger.log(
        action: 'download-scope-tombstone-repair',
        entity: repository.scope,
        result: 'ok',
        extra: {'records': prepared.length},
      );
    }

    if (repairedRecords > 0) {
      await _syncLogger.log(
        action: 'download-tombstone-repair-complete',
        entity: repairScopes.join(','),
        result: 'ok',
        extra: {'repairedRecords': repairedRecords},
      );
    }

    return repairedRecords;
  }

  Future<int> applyRemoteScopeRecords({
    required String scope,
    required List<Map<String, dynamic>> records,
    DateTime? cursor,
  }) async {
    final repository = _repositoriesByScope[scope];
    if (repository == null) {
      return 0;
    }

    if (records.isEmpty) {
      return 0;
    }

    final preparedRecords = _prepareScopeRecordsForApply(scope, records);
    await repository.mergeRemoteRecords(preparedRecords);
    final resolvedCursor = cursor ?? _findLatestTimestamp(records);
    if (resolvedCursor != null) {
      await _configRepository.saveCursor(scope, resolvedCursor);
    }
    return preparedRecords.length;
  }

  bool hasScope(String scope) => _repositoriesByScope.containsKey(scope);

  Future<void> reconfigure({
    String? baseUrl,
    String? jwtToken,
    Duration? queueRetryInterval,
    Duration? realtimePollingInterval,
    SyncConflictStrategy? conflictStrategy,
  }) async {
    if (baseUrl != null) {
      await _configRepository.saveBaseUrl(baseUrl);
    }
    if (jwtToken != null) {
      await _configRepository.saveJwtToken(jwtToken);
    }
    if (queueRetryInterval != null) {
      await _configRepository.saveQueueRetryInterval(queueRetryInterval);
    }
    if (realtimePollingInterval != null) {
      await _configRepository.saveRealtimePollingInterval(
        realtimePollingInterval,
      );
    }
    if (conflictStrategy != null) {
      await _configRepository.saveConflictStrategy(conflictStrategy);
    }
  }

  void dispose() {}

  Future<void> _invalidateCloudSession(String reason) async {
    if (_cloudSessionInvalidated) {
      return;
    }
    _cloudSessionInvalidated = true;
    await _configRepository.clearJwtToken();
    await _configRepository.saveLastRun(
      errorMessage: reason,
      status: SyncRuntimeStatus.pending,
    );
    await _syncLogger.log(
      action: 'cloud-session-expired',
      entity: 'auth',
      result: 'pending',
      error: reason,
    );
    final notify = _onCloudSessionExpired;
    if (notify != null) {
      await notify(reason);
    }
  }

  bool _isUnauthorizedSyncError(HttpException error) {
    final message = error.message.toLowerCase();
    return message.contains('401') || message.contains('unauthorized');
  }

  bool _isDeviceUnauthorizedSyncError(HttpException error) {
    final normalized = error.message.trim().toUpperCase();
    return normalized.contains('DEVICE_NOT_AUTHORIZED') ||
        normalized.contains('DEVICE_NOT_AUTHORIZED_FOR_WRITE');
  }

  Future<String> recoverAfterDeviceAuthorization() async {
    final unlockedJobs = await _syncQueueService.resetDeferredJobsForDeviceSwitch();
    await _configRepository.clearSyncRuntimeState();
    final report = await syncNow(forceFullDownload: true);
    final downloaded = report.downloadedRecords;
    final uploaded = report.uploadedRecords;
    return 'Recuperacion completada. Jobs desbloqueados: $unlockedJobs, descargados: $downloaded, subidos: $uploaded.';
  }

  Future<String> resetLocalDeviceIdentityForAdmin() async {
    final previousSettings = await _configRepository.loadSettings();
    final oldDeviceId = previousSettings.deviceId;
    final unlockedJobs = await _syncQueueService.resetDeferredJobsForDeviceSwitch();
    final newDeviceId = await _configRepository.rotateDeviceId();
    await _configRepository.saveDeviceWriteState(
      const DeviceWriteState(
        isPrimary: true,
        canWrite: true,
        lastValidatedAt: null,
        reason: '',
      ),
    );
    await SystemConfigService.instance.refresh();
    return 'Identificacion local reiniciada. ID anterior: $oldDeviceId. Nuevo ID: $newDeviceId. Jobs desbloqueados: $unlockedJobs.';
  }

  Future<Map<String, int>> resetLocalBusinessDataForAdmin() async {
    final businessScopes = const <String>{
      'clients',
      'sellers',
      'products',
      'sales',
      'installments',
      'payments',
    };
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final deleted = await db.transaction<Map<String, int>>((txn) async {
      final payments = await txn.delete(DatabaseSchema.paymentsTable);
      final installments = await txn.delete(DatabaseSchema.installmentsTable);
      final sales = await txn.delete(DatabaseSchema.salesTable);
      final clients = await txn.delete(DatabaseSchema.clientsTable);
      final sellers = await txn.delete(DatabaseSchema.sellersTable);
      final products = await txn.delete(DatabaseSchema.lotsTable);

      final placeholders = List.filled(businessScopes.length, '?').join(', ');
      final queueRows = await txn.rawDelete(
        'DELETE FROM ${DatabaseSchema.syncQueueTable} '
        'WHERE scope IN ($placeholders)',
        businessScopes.toList(growable: false),
      );
      await txn.rawUpdate(
        'UPDATE ${DatabaseSchema.conflictLogsTable} '
        'SET resolved_at = COALESCE(resolved_at, ?), '
        "resolution = COALESCE(resolution, 'business_reset') "
        'WHERE resolved_at IS NULL AND scope IN ($placeholders)',
        [now, ...businessScopes],
      );

      return {
        'payments': payments,
        'installments': installments,
        'sales': sales,
        'clients': clients,
        'sellers': sellers,
        'products': products,
        'sync_queue': queueRows,
      };
    });

    await _configRepository.clearCursors(businessScopes);
    await _configRepository.saveLastRun(
      errorMessage: '',
      status: SyncRuntimeStatus.pending,
    );
    return deleted;
  }

  String _buildMissingConfigurationMessage(SyncSettings settings) {
    final hasBaseUrl = settings.baseUrl.trim().isNotEmpty;
    final hasJwtToken = settings.jwtToken.trim().isNotEmpty;

    if (!hasBaseUrl && !hasJwtToken) {
      return 'Inicia sesion en linea para activar la sincronizacion.';
    }
    if (!hasBaseUrl) {
      return serverConnectionErrorMessage;
    }
    if (!hasJwtToken) {
      return cloudLoginRequiredMessage;
    }
    return 'La sincronizacion no esta configurada correctamente.';
  }

  DateTime? _findLatestTimestamp(List<Map<String, dynamic>> records) {
    DateTime? latest;
    for (final record in records) {
      final rawValue = record['updated_at'];
      final parsed = rawValue == null
          ? null
          : DateTime.tryParse(rawValue.toString());
      if (parsed == null) {
        continue;
      }
      if (latest == null || parsed.isAfter(latest)) {
        latest = parsed;
      }
    }
    return latest;
  }

  List<Map<String, dynamic>> _prepareScopeRecordsForApply(
    String scope,
    List<Map<String, dynamic>> records,
  ) {
    if (records.length <= 1) {
      _logPreparedScopeRecords(scope, records);
      return records;
    }

    final deletes = <Map<String, dynamic>>[];
    final upserts = <Map<String, dynamic>>[];

    for (final record in records) {
      if (_isRemoteDeleteRecord(record)) {
        deletes.add(record);
      } else {
        upserts.add(record);
      }
    }

    final ordered = <Map<String, dynamic>>[
      ...deletes,
      ...upserts,
    ];
    _logPreparedScopeRecords(scope, ordered);
    return ordered;
  }

  bool _isRemoteDeleteRecord(Map<String, dynamic> record) {
    final deletedAt = record['deleted_at']?.toString().trim() ?? '';
    return deletedAt.isNotEmpty;
  }

  void _logPreparedScopeRecords(
    String scope,
    List<Map<String, dynamic>> records,
  ) {
    for (final record in records) {
      final syncId = record['sync_id']?.toString().trim();
      if (syncId == null || syncId.isEmpty) {
        continue;
      }
      if (_isRemoteDeleteRecord(record)) {
        debugPrint('[SYNC] Applying remote delete: table=$scope id=$syncId');
      } else {
        debugPrint('[SYNC] Applying remote upsert: table=$scope id=$syncId');
      }
    }
  }

  Future<bool> _shouldForceFullBusinessDownload(
    Set<String> targetScopes,
  ) async {
    final touchesBusinessData =
        targetScopes.contains('products') ||
        targetScopes.contains('sales') ||
        targetScopes.contains('installments') ||
        targetScopes.contains('payments');
    if (!touchesBusinessData) {
      return false;
    }

    final db = await _appDatabase.database;
    final clientsCount = await _countRows(db, DatabaseSchema.clientsTable);
    final lotsCount = await _countRows(db, DatabaseSchema.lotsTable);
    final salesCount = await _countRows(db, DatabaseSchema.salesTable);
    if (clientsCount > 0 && lotsCount == 0) {
      return true;
    }
    if (clientsCount > 0 && lotsCount > 0 && salesCount == 0) {
      return _hasAnyBusinessCursor(targetScopes);
    }

    return false;
  }

  Future<bool> _hasAnyBusinessCursor(Set<String> targetScopes) async {
    for (final scope in const [
      'clients',
      'products',
      'sales',
      'installments',
      'payments',
    ]) {
      if (!targetScopes.contains(scope)) {
        continue;
      }
      final cursor = await _configRepository.loadCursor(scope);
      if (cursor != null) {
        return true;
      }
    }
    return false;
  }

  Future<int> _countRows(dynamic db, String tableName) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $tableName');
    if (rows.isEmpty) {
      return 0;
    }

    final value = rows.first['total'];
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Set<String> _buildDependentFullDownloadScopes(
    Set<String> targetScopes,
    Map<String, DateTime?> cursorBeforeByScope,
  ) {
    final incompleteScopes = <String>{};
    for (final scope in const ['clients', 'products', 'sales', 'installments']) {
      if (!targetScopes.contains(scope)) {
        continue;
      }
      if (cursorBeforeByScope[scope] == null) {
        incompleteScopes.add(scope);
      }
    }
    return _expandRecoveryScopes(incompleteScopes).intersection(targetScopes);
  }

  Set<String> _expandRecoveryScopes(Set<String> scopes) {
    final expanded = <String>{...scopes};
    var changed = true;
    while (changed) {
      changed = false;
      if ((expanded.contains('clients') ||
              expanded.contains('products') ||
              expanded.contains('sellers')) &&
          !expanded.contains('sales')) {
        expanded.add('sales');
        changed = true;
      }
      if (expanded.contains('sales')) {
        if (!expanded.contains('installments')) {
          expanded.add('installments');
          changed = true;
        }
        if (!expanded.contains('payments')) {
          expanded.add('payments');
          changed = true;
        }
      }
      if (expanded.contains('installments') && !expanded.contains('payments')) {
        expanded.add('payments');
        changed = true;
      }
    }
    return expanded;
  }
}
