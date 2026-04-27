import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/backend_config.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
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
  static const bool _downloadFromCloudEnabled = true;

  SyncService({
    required List<SyncRepository> repositories,
    Future<void> Function(SyncReport report)? onSyncFinished,
    Future<void> Function(String reason)? onCloudSessionExpired,
    SyncConfigRepository? configRepository,
    SyncApiClient? apiClient,
    SyncQueueService? syncQueueService,
  }) : _repositories = repositories,
       _onSyncFinished = onSyncFinished,
       _onCloudSessionExpired = onCloudSessionExpired,
       _configRepository = configRepository ?? SyncConfigRepository(),
       _apiClient = apiClient ?? SyncApiClient(),
       _syncQueueService = syncQueueService ?? SyncQueueService.instance {
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
  final AppDatabase _appDatabase = AppDatabase.instance;
  final SyncLogger _syncLogger = SyncLogger.instance;
  List<String> _lastScopeWarnings = const [];
  bool _isSyncing = false;
  bool _cloudSessionInvalidated = false;
  SyncReport? _lastReport;

  bool get isSyncing => _isSyncing;
  SyncReport? get lastReport => _lastReport;

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

      final uploadedCount = await uploadPendingData();
      final downloadedCount = _downloadFromCloudEnabled
          ? await downloadUpdates(forceFullDownload: forceFullDownload)
          : 0;
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
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 8);
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

  Future<int> downloadUpdatesForScopes(
    Iterable<String> scopes, {
    bool forceFullDownload = false,
  }) async {
    if (!_downloadFromCloudEnabled) {
      return 0;
    }
    final settings = await _configRepository.loadSettings();
    final targetScopes = scopes.toSet();
    _lastScopeWarnings = const [];
    if (!settings.isConfigured) {
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

    DateTime? earliestCursor;
    for (final scope in targetScopes) {
      final cursor = await _configRepository.loadCursor(scope);
      if (cursor == null) {
        earliestCursor = null;
        break;
      }
      if (earliestCursor == null || cursor.isBefore(earliestCursor)) {
        earliestCursor = cursor;
      }
    }

    late final SyncDownloadResponse response;
    try {
      response = await _apiClient.downloadChanges(
        settings: settings,
        updatedSince: earliestCursor,
      );
    } on HttpException catch (error) {
      if (_isUnauthorizedSyncError(error)) {
        await _invalidateCloudSession(
          'La sesion de nube vencio o fue rechazada por el backend.',
        );
      }
      rethrow;
    }

    var downloadedRecords = 0;
    final scopeWarnings = <String>[];

    for (final repository in _repositories) {
      if (!targetScopes.contains(repository.scope)) {
        continue;
      }

      try {
        final scopeRecords = response.recordsForScope(repository.scope);

        if (scopeRecords.isNotEmpty) {
          await repository.mergeRemoteRecords(scopeRecords);
          downloadedRecords += scopeRecords.length;
        }

        await _syncLogger.log(
          action: 'download-scope',
          entity: repository.scope,
          result: scopeRecords.isNotEmpty ? 'ok' : 'idle',
          extra: {'records': scopeRecords.length},
        );

        final nextCursor = _findLatestTimestamp(scopeRecords);
        if (nextCursor != null) {
          await _configRepository.saveCursor(repository.scope, nextCursor);
        }
      } catch (error) {
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

    return downloadedRecords;
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

    await repository.mergeRemoteRecords(records);
    final resolvedCursor = cursor ?? _findLatestTimestamp(records);
    if (resolvedCursor != null) {
      await _configRepository.saveCursor(scope, resolvedCursor);
    }
    return records.length;
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
      return 'La app local necesita reautenticarse con la nube. Inicia sesion en linea nuevamente para reunificar la sincronizacion.';
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
    return clientsCount > 0 && lotsCount == 0;
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
}
