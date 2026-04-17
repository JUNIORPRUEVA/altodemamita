import 'dart:async';
import 'dart:io';

import '../../core/system/system_config_service.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_report.dart';
import '../../repositories/sync_repository.dart';
import 'sync_api_client.dart';
import 'sync_config_repository.dart';
import 'sync_queue_service.dart';

class SyncService {
  SyncService({
    required List<SyncRepository> repositories,
    SyncConfigRepository? configRepository,
    SyncApiClient? apiClient,
    SyncQueueService? syncQueueService,
  }) : _repositories = repositories,
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
  final SyncConfigRepository _configRepository;
  final SyncApiClient _apiClient;
  final SyncQueueService _syncQueueService;
  List<String> _lastScopeWarnings = const [];
  bool _isSyncing = false;
  SyncReport? _lastReport;

  bool get isSyncing => _isSyncing;
  SyncReport? get lastReport => _lastReport;

  Future<SyncReport> syncNow() async {
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
    try {
      final settings = await _configRepository.loadSettings();
      if (!settings.isConfigured) {
        final skipped = SyncReport(
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          wasSkipped: true,
          errorMessage:
              'Configura sync.base_url y el token JWT antes de sincronizar.',
        );
        _lastReport = skipped;
        return skipped;
      }

      final uploadedCount = await uploadPendingData();
      final downloadedCount = await downloadUpdates();
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
      _lastReport = report;
      return report;
    } on SocketException catch (error) {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        hadConnectivityError: true,
        errorMessage:
            'No se pudo completar la sincronizacion por falta de conectividad: ${error.message}',
      );
      await _configRepository.saveLastRun(errorMessage: report.errorMessage);
      _lastReport = report;
      return report;
    } on HttpException catch (error) {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        errorMessage: error.message,
      );
      await _configRepository.saveLastRun(errorMessage: report.errorMessage);
      _lastReport = report;
      return report;
    } on ReadOnlyModeException {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        wasSkipped: true,
        errorMessage: 'Sistema en modo solo lectura',
      );
      await _configRepository.saveLastRun(errorMessage: report.errorMessage);
      _lastReport = report;
      return report;
    } catch (error) {
      _lastScopeWarnings = const [];
      final report = SyncReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        errorMessage: 'La sincronizacion fallo: $error',
      );
      await _configRepository.saveLastRun(errorMessage: report.errorMessage);
      _lastReport = report;
      return report;
    } finally {
      _isSyncing = false;
    }
  }

  Future<int> uploadPendingData() async {
    return _syncQueueService.processQueue();
  }

  Future<int> downloadUpdates() async {
    return downloadUpdatesForScopes(_repositoriesByScope.keys);
  }

  Future<int> downloadUpdatesForScopes(Iterable<String> scopes) async {
    final settings = await _configRepository.loadSettings();
    final targetScopes = scopes.toSet();
    _lastScopeWarnings = const [];
    if (targetScopes.isEmpty) {
      return 0;
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

    final response = await _apiClient.downloadChanges(
      settings: settings,
      updatedSince: earliestCursor,
    );

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

        final nextCursor =
            response.serverTime ?? _findLatestTimestamp(scopeRecords);
        if (nextCursor != null) {
          await _configRepository.saveCursor(repository.scope, nextCursor);
        }
      } catch (error) {
        scopeWarnings.add(
          'No se pudieron aplicar cambios remotos de ${repository.scope}: $error',
        );
      }
    }

    _lastScopeWarnings = scopeWarnings;

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
      if (cursor != null) {
        await _configRepository.saveCursor(scope, cursor);
      }
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
}
