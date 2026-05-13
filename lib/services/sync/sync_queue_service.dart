import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import '../../core/config/app_flags.dart';
import '../../core/system/system_config_service.dart';
import '../../core/utils/client_data_guard.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_runtime_state.dart';
import '../../models/sync/sync_settings.dart';
import '../../repositories/sync_repository.dart';
import 'sync_conflict_service.dart';
import 'sync_api_client.dart';
import 'sync_config_repository.dart';
import 'sync_logger.dart';

class SyncOperationPendingException implements Exception {
  const SyncOperationPendingException(
    this.message, {
    this.pendingItems = const [],
  });

  final String message;
  final List<SyncQueueItem> pendingItems;

  @override
  String toString() => message;
}

class SyncQueueService {
  factory SyncQueueService.test({
    AppDatabase? appDatabase,
    SyncConfigRepository? configRepository,
    SyncApiClient? apiClient,
    SyncConflictService? conflictService,
    Future<bool> Function(SyncSettings settings)? connectivityProbe,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  }) {
    return SyncQueueService._(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: conflictService,
      connectivityProbe: connectivityProbe ?? ((_) async => true),
      connectivityChanges: connectivityChanges,
    );
  }

  SyncQueueService._({
    AppDatabase? appDatabase,
    SyncConfigRepository? configRepository,
    SyncApiClient? apiClient,
    SyncConflictService? conflictService,
    Future<bool> Function(SyncSettings settings)? connectivityProbe,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _configRepository = configRepository ?? SyncConfigRepository(),
       _apiClient = apiClient ?? SyncApiClient(),
       _conflictService = conflictService ?? SyncConflictService(),
       _connectivityProbe = connectivityProbe ?? _defaultConnectivityProbe,
       _connectivityChanges =
           connectivityChanges ?? Connectivity().onConnectivityChanged;

  static final SyncQueueService instance = SyncQueueService._();

  final AppDatabase _appDatabase;
  final SyncConfigRepository _configRepository;
  final SyncApiClient _apiClient;
  final SyncConflictService _conflictService;
  final Future<bool> Function(SyncSettings settings) _connectivityProbe;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  final SyncLogger _syncLogger = SyncLogger.instance;
  final Map<String, SyncRepository> _repositoriesByScope = {};
  final StreamController<SyncQueueState> _stateController =
      StreamController<SyncQueueState>.broadcast();
  final Set<String> _conflictRecoveryDownloadedScopes = {};
  Future<void> Function(String reason)? _onCloudSessionExpired;

  static const List<String> _syncOrder = [
    'users',
    'roles',
    'user_roles',
    'role_permissions',
    'permissions',
    'company_profiles',
    'clients',
    'products',
    'sellers',
    'sales',
    'installments',
    'payments',
  ];
  static const Map<String, List<String>> _scopeDependencies = {
    'users': [],
    'roles': [],
    'user_roles': ['users', 'roles'],
    'role_permissions': ['roles', 'permissions'],
    'permissions': ['users'],
    'company_profiles': [],
    'clients': [],
    'products': ['clients'],
    'sellers': [],
    'sales': ['clients', 'products'],
    'installments': ['sales'],
    'payments': ['sales'],
  };

  static const Map<String, String> _scopeTableMap = {
    'users': DatabaseSchema.usersTable,
    'roles': DatabaseSchema.rolesTable,
    'user_roles': DatabaseSchema.userRolesTable,
    'role_permissions': DatabaseSchema.rolePermissionsTable,
    'permissions': DatabaseSchema.permissionsTable,
    'company_profiles': DatabaseSchema.companyProfilesTable,
    'clients': DatabaseSchema.clientsTable,
    'products': DatabaseSchema.lotsTable,
    'sellers': DatabaseSchema.sellersTable,
    'sales': DatabaseSchema.salesTable,
    'installments': DatabaseSchema.installmentsTable,
    'payments': DatabaseSchema.paymentsTable,
  };
  static const Set<String> _deleteAckRepairScopes = {
    'products',
    'sales',
    'installments',
    'payments',
    'users',
    'sellers',
  };
  static const Set<String> _businessRepairScopes = {
    'products',
    'sales',
    'installments',
    'payments',
  };
  static const int _maxRetryAttempts = 12;

  Timer? _retryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isProcessing = false;
  bool _isDisposed = false;
  SyncQueueState _state = const SyncQueueState();

  Stream<SyncQueueState> get stateStream => _stateController.stream;
  SyncQueueState get state => _state;

  bool get isWorkerActive =>
      !_isDisposed &&
      !manualCloudSyncOnly &&
      _retryTimer != null &&
      _connectivitySubscription != null;

  void _log(String message) {
    developer.log(message, name: 'SistemaSolares.SyncQueue');
  }

  void registerRepository(SyncRepository repository) {
    _repositoriesByScope[repository.scope] = repository;
  }

  void setCloudSessionExpiredHandler(
    Future<void> Function(String reason)? handler,
  ) {
    _onCloudSessionExpired = handler;
  }

  Future<void> start() async {
    if (_isDisposed) {
      return;
    }
    if (manualCloudSyncOnly) {
      _retryTimer?.cancel();
      await _connectivitySubscription?.cancel();
      _connectivitySubscription = null;
      await _refreshState();
      return;
    }

    final settings = await _configRepository.loadSettings();
    _retryTimer?.cancel();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityChanges.listen(
      _handleConnectivityChanged,
    );
    _retryTimer = Timer.periodic(settings.queueRetryInterval, (_) {
      // Usamos syncPending en lugar de processQueue para que, en cada tick:
      // 1) refreshScope() re-encole registros pendientes en SQLite que no
      //    hayan llegado a la cola (incluyendo los que fallaron offline).
      // 2) processQueue(includeDeferred:true) procese TODOS los items,
      //    sin importar su next_attempt_at, garantizando que cuando el
      //    internet regresa, los items se envian en el siguiente tick.
      unawaited(syncPending());
    });
    await _refreshState();

    // Recovery: records marked as conflict are not enqueued by refreshScope()
    // (only pending records are). If the backend conflict payload is now
    // parseable, we can safely re-queue these so the queue can attempt upload
    // again and auto-resolve when the server returns authoritative records.
    unawaited(requeueUnresolvedConflicts());

    unawaited(processQueue());
  }

  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isProcessing = false;
    await _refreshState(clearLastError: true);
  }

  Future<int> resetDeferredJobsForDeviceSwitch() async {
    if (_isDisposed) {
      return 0;
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final affected = await db.rawUpdate(
      'UPDATE ${DatabaseSchema.syncQueueTable} '
      'SET attempt_count = 0, '
      'last_error = NULL, '
      'updated_at = ?, '
      'next_attempt_at = ? '
      'WHERE attempt_count > 0 '
      "OR TRIM(COALESCE(last_error, '')) != '' "
      'OR next_attempt_at > ?',
      [now, now, now],
    );
    await _refreshState(clearLastError: true);
    return affected;
  }

  Future<int> requeueUnresolvedConflicts({Iterable<String>? scopes}) async {
    if (SystemConfigService.instance.isReadOnly) {
      return 0;
    }

    final normalizedScopes = (scopes ?? _scopeTableMap.keys)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedScopes.isEmpty) {
      return 0;
    }

    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT scope, record_sync_id, strategy '
      'FROM ${DatabaseSchema.conflictLogsTable} '
      'WHERE resolved_at IS NULL',
    );

    final idsByScope = <String, Set<String>>{};
    for (final row in rows) {
      final scope = row['scope']?.toString().trim() ?? '';
      if (scope.isEmpty || !normalizedScopes.contains(scope)) {
        continue;
      }
      final strategy = row['strategy']?.toString().trim().toLowerCase() ?? '';
      // Manual conflicts require explicit server-wins reconciliation and should
      // not be auto-requeued, otherwise the same stale payload can loop in 409.
      if (strategy == SyncConflictStrategy.manual.storageValue) {
        continue;
      }
      final recordSyncId = row['record_sync_id']?.toString().trim() ?? '';
      if (recordSyncId.isEmpty) {
        continue;
      }
      idsByScope.putIfAbsent(scope, () => <String>{}).add(recordSyncId);
    }

    var updatedCount = 0;
    for (final entry in idsByScope.entries) {
      final scope = entry.key;
      final table = _scopeTableMap[scope];
      final repository = _repositoriesByScope[scope];
      if (table == null || repository == null) {
        continue;
      }

      try {
        final tableRows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table],
        );
        if (tableRows.isEmpty) {
          continue;
        }

        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final columnNames = columns
            .map((row) => row['name'])
            .whereType<String>()
            .toSet();
        if (!columnNames.contains('sync_id') ||
            !columnNames.contains('sync_status')) {
          continue;
        }
      } on DatabaseException catch (error) {
        _log(
          'requeueUnresolvedConflicts -> no se pudo inspeccionar tabla $table ($scope): $error',
        );
        continue;
      }

      final ids = entry.value.toList(growable: false);
      const chunkSize = 200;
      for (var offset = 0; offset < ids.length; offset += chunkSize) {
        final chunk = ids.sublist(
          offset,
          (offset + chunkSize) > ids.length ? ids.length : (offset + chunkSize),
        );
        final placeholders = List.filled(chunk.length, '?').join(', ');
        try {
          updatedCount += await db.rawUpdate(
            'UPDATE $table '
            'SET sync_status = ? '
            'WHERE sync_status = ? AND sync_id IN ($placeholders)',
            [
              DatabaseSchema.syncStatusPending,
              DatabaseSchema.syncStatusConflict,
              ...chunk,
            ],
          );
        } on DatabaseException catch (error) {
          _log(
            'requeueUnresolvedConflicts -> fallo UPDATE en $table ($scope): $error',
          );
        }
      }

      try {
        await refreshScope(scope);
      } catch (error) {
        _log(
          'requeueUnresolvedConflicts -> fallo refreshScope($scope): $error',
        );
      }
    }

    if (updatedCount > 0) {
      await _refreshState(clearLastError: true);
      unawaited(processQueue());
    }

    return updatedCount;
  }

  void dispose() {
    _isDisposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    if (!_stateController.isClosed) {
      unawaited(_stateController.close());
    }
  }

  Future<void> enqueueUpsert({
    required String scope,
    required String recordSyncId,
    required Map<String, Object?> payload,
    bool triggerProcessing = true,
  }) {
    SystemConfigService.instance.ensureWritable();
    unawaited(
      _syncLogger.log(
        action: 'enqueue',
        entity: scope,
        result: 'pending',
        extra: {'operation': 'upsert', 'recordSyncId': recordSyncId},
      ),
    );

    return _enqueue(
      scope: scope,
      recordSyncId: recordSyncId,
      operation: 'upsert',
      payload: payload,
      triggerProcessing: triggerProcessing,
    );
  }

  Future<void> enqueueDelete({
    required String scope,
    required String recordSyncId,
    required Map<String, Object?> payload,
    bool triggerProcessing = true,
  }) {
    SystemConfigService.instance.ensureWritable();
    unawaited(
      _syncLogger.log(
        action: 'enqueue',
        entity: scope,
        result: 'pending',
        extra: {'operation': 'delete', 'recordSyncId': recordSyncId},
      ),
    );

    return _enqueue(
      scope: scope,
      recordSyncId: recordSyncId,
      operation: 'delete',
      payload: payload,
      triggerProcessing: triggerProcessing,
    );
  }

  Future<void> enqueueDeleteBatch({
    required Iterable<
      ({String scope, String recordSyncId, Map<String, Object?> payload})
    >
    items,
    bool triggerProcessing = true,
  }) async {
    SystemConfigService.instance.ensureWritable();
    final normalizedItems = items
        .where(
          (item) =>
              item.scope.trim().isNotEmpty &&
              item.recordSyncId.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (normalizedItems.isEmpty) {
      return;
    }

    for (final item in normalizedItems) {
      unawaited(
        _syncLogger.log(
          action: 'enqueue',
          entity: item.scope,
          result: 'pending',
          extra: {
            'operation': 'delete',
            'recordSyncId': item.recordSyncId,
            'mode': 'batch',
          },
        ),
      );
    }

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final queuedByScope = <String, List<String>>{};

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final item in normalizedItems) {
        batch.insert(
          DatabaseSchema.syncQueueTable,
          <String, Object?>{
            'scope': item.scope,
            'record_sync_id': item.recordSyncId,
            'operation': 'delete',
            'payload_json': jsonEncode(item.payload),
            'updated_at': now,
            'next_attempt_at': now,
            'last_error': null,
            'attempt_count': 0,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        queuedByScope
            .putIfAbsent(item.scope, () => <String>[])
            .add(item.recordSyncId);
      }

      await batch.commit(noResult: true);
    });

    for (final entry in queuedByScope.entries) {
      await _markSourceRowsAsQueued(
        scope: entry.key,
        recordSyncIds: entry.value,
        payload: const {'deleted_at': true},
        queuedAt: now,
        operation: 'delete',
      );
    }

    await _refreshState();
    if (triggerProcessing) {
      unawaited(processQueue());
    }
  }

  Future<void> refreshScope(String scope) async {
    final repository = _repositoriesByScope[scope];
    if (repository == null) {
      return;
    }

    final pendingRecords = await repository.getPendingRecords();
    for (final record in pendingRecords) {
      final recordSyncId = record['sync_id']?.toString().trim() ?? '';
      if (recordSyncId.isEmpty) {
        continue;
      }
      final isDelete =
          (record['deleted_at']?.toString().trim().isNotEmpty ?? false);
      await _enqueue(
        scope: scope,
        recordSyncId: recordSyncId,
        operation: isDelete ? 'delete' : 'upsert',
        payload: record,
        triggerProcessing: false,
      );
    }
  }

  Future<int> pendingCount() async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) FROM ${DatabaseSchema.syncQueueTable}',
      );
      final value = rows.isEmpty ? 0 : rows.first.values.first;
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value.toString()) ?? 0;
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log(
          'SQLite cerrandose durante pendingCount -> se conserva estado local',
        );
        return _state.pendingCount;
      }
      rethrow;
    }
  }

  Future<void> syncScopesNowOrThrow(
    Iterable<String> scopes, {
    String? operationLabel,
  }) async {
    final normalizedScopes = scopes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedScopes.isEmpty) {
      return;
    }

    await _waitForIdle();
    await processQueue(includeDeferred: true);
    await _waitForIdle();

    final pendingItems = await _loadPendingItemsForScopes(normalizedScopes);
    if (pendingItems.isEmpty) {
      _log(
        'CONFIRMED -> ${operationLabel ?? normalizedScopes.join(',')} scopes=${normalizedScopes.join(',')}',
      );
      return;
    }

    final pendingSummary = pendingItems
        .map((item) {
          final resolvedError = item.lastError?.trim();
          final lastError = resolvedError == null || resolvedError.isEmpty
              ? null
              : resolvedError;
          return lastError == null
              ? '${item.scope}:${item.recordSyncId}'
              : '${item.scope}:${item.recordSyncId} -> $lastError';
        })
        .join(' | ');
    final message =
        'La nube no confirmo ${operationLabel ?? 'la operacion solicitada'}. Pendientes: $pendingSummary';
    _log('PENDING -> $message');
    await _configRepository.saveLastRun(
      errorMessage: message,
      status: SyncRuntimeStatus.pending,
    );
    await _syncLogger.log(
      action: operationLabel ?? 'syncScopesNowOrThrow',
      entity: normalizedScopes.join(','),
      result: 'pending',
      error: message,
    );
    throw SyncOperationPendingException(message, pendingItems: pendingItems);
  }

  Future<int> processQueue({
    int limit = 100,
    bool includeDeferred = false,
  }) async {
    if (_isDisposed) {
      return 0;
    }
    if (SystemConfigService.instance.isReadOnly) {
      await _refreshState();
      return 0;
    }

    if (_isProcessing) {
      return 0;
    }

    _isProcessing = true;
    await _refreshState();
    try {
      final settings = await _configRepository.loadSettings();
      if (!settings.isConfigured) {
        const message =
            'No se ejecuto subida hacia la nube. Falta configuracion de sincronizacion (JWT/baseUrl).';
        _log('[sync-upload] SKIPPED -> $message');
        await _configRepository.saveLastRun(
          errorMessage: message,
          status: SyncRuntimeStatus.pending,
        );
        await _refreshState(lastError: message);
        return 0;
      }

      final isOnline = await _connectivityProbe(settings);
      if (!isOnline) {
        await _configRepository.saveLastRun(
          errorMessage: 'Sin conexion con el backend. Cola en espera.',
          status: SyncRuntimeStatus.pending,
        );
        await _syncLogger.log(
          action: 'connectivity-check',
          entity: 'sync',
          result: 'pending',
          error: 'offline',
        );
        await _refreshState(lastError: 'Sin conexion con el backend.');
        return 0;
      }

      var processedCount = 0;
      while (true) {
        final items = await _loadDueItems(
          limit: limit,
          includeDeferred: includeDeferred,
        );
        if (items.isEmpty) {
          return processedCount;
        }

        final orderedItems = items.toList(growable: false)
          ..sort((left, right) {
            final leftIndex = _syncOrder.indexOf(left.scope);
            final rightIndex = _syncOrder.indexOf(right.scope);
            final normalizedLeft = leftIndex == -1
                ? _syncOrder.length
                : leftIndex;
            final normalizedRight = rightIndex == -1
                ? _syncOrder.length
                : rightIndex;
            final byScope = normalizedLeft.compareTo(normalizedRight);
            if (byScope != 0) {
              return byScope;
            }
            return left.createdAt.compareTo(right.createdAt);
          });

        var batchProcessedCount = 0;
        final unsupportedScopes = orderedItems
            .map((item) => item.scope)
            .where((scope) => !_repositoriesByScope.containsKey(scope))
            .toSet();
        if (unsupportedScopes.isNotEmpty) {
          await _deleteQueuedScopes(unsupportedScopes);
        }

        final unavailableScopes = <String>{};
        for (final item in orderedItems) {
          if (_isDisposed) {
            return processedCount + batchProcessedCount;
          }
          final scope = item.scope;
          if (unsupportedScopes.contains(scope)) {
            continue;
          }

          if (_hasUnavailableDependency(scope, unavailableScopes)) {
            unavailableScopes.add(scope);
            continue;
          }

          final repository = _repositoriesByScope[scope];
          if (repository == null) {
            continue;
          }

          var entryItems = [item];
          if (_deleteAckRepairScopes.contains(scope)) {
            await _repairFailedDeleteQueueEntries(scope, entryItems, settings);
            entryItems = await _retainQueuedItems(scope, entryItems);
          }

          entryItems = await _pruneOrphanedUpserts(
            scope,
            entryItems,
            repository,
          );
          if (entryItems.isEmpty) {
            continue;
          }

          if (isProductionMode && scope == 'clients') {
            entryItems = await _filterBlockedClientQueueItems(entryItems);
            if (entryItems.isEmpty) {
              continue;
            }
          }

          try {
            _log(
              '[sync-upload] START '
              'scope=$scope recordSyncId=${entryItems.single.recordSyncId} '
              'operation=${entryItems.single.operation} pending=${_state.pendingCount} '
              'includeDeferred=$includeDeferred',
            );
            final response = await _apiClient.uploadQueuedRecords(
              settings: settings,
              recordsByScope: {
                scope: [entryItems.single.toUploadPayload()],
              },
            );

            final returnedRecords = response.recordsForScope(scope);
            if (allowCloudPull && returnedRecords.isNotEmpty) {
              await repository.mergeRemoteRecords(returnedRecords);
            }

            final uploadedSyncIds = entryItems
                .map((item) => item.recordSyncId)
                .toSet();
            final acknowledgedSyncIds = returnedRecords
                .map(_readReturnedRecordSyncId)
                .where(
                  (value) => value != null && uploadedSyncIds.contains(value),
                )
                .cast<String>()
                .toSet()
                .toList(growable: false);

            if (acknowledgedSyncIds.isNotEmpty) {
              _log(
                '[sync-upload] ACK '
                'scope=$scope acked=${acknowledgedSyncIds.length} '
                'recordSyncIds=${acknowledgedSyncIds.join(',')}',
              );
              await repository.markAsSynced(acknowledgedSyncIds);
              await _deleteQueuedRecords(scope, acknowledgedSyncIds);
              if (scope == 'products') {
                await _syncLogger.log(
                  action: 'product_sync_queue_completed',
                  entity: scope,
                  result: 'ok',
                  extra: {'count': acknowledgedSyncIds.length},
                );
              }
              await _conflictService.resolveConflicts(
                scope: scope,
                recordSyncIds: acknowledgedSyncIds,
                resolution: 'synced',
              );
              batchProcessedCount += acknowledgedSyncIds.length;
              await _syncLogger.log(
                action: 'upload',
                entity: scope,
                result: 'ok',
                extra: {'count': acknowledgedSyncIds.length},
              );
            }

            final unconfirmedIds = entryItems
                .where(
                  (item) => !acknowledgedSyncIds.contains(item.recordSyncId),
                )
                .map((item) => item.recordSyncId)
                .toList(growable: false);
            if (unconfirmedIds.isNotEmpty) {
              _log(
                '[sync-upload] UNCONFIRMED '
                'scope=$scope count=${unconfirmedIds.length} '
                'recordSyncIds=${unconfirmedIds.join(',')}',
              );
              await _scheduleRetry(
                scope: scope,
                recordSyncIds: unconfirmedIds,
                errorMessage:
                    'La API no confirmo todos los registros de la cola.',
              );
              unavailableScopes.add(scope);
            }

            // Do not advance download cursors from upload responses.
            // Cursors must only move forward from download payloads to avoid
            // skipping historical records on first sync of a new device.
          } on SyncConflictException catch (error) {
            final isManualProductConflict = scope == 'products';
            final effectiveStrategy = isManualProductConflict
                ? SyncConflictStrategy.manual
                : error.strategy;
            _log(
              '[sync-upload] CONFLICT '
              'scope=$scope recordSyncId=${entryItems.single.recordSyncId} '
              'message=${error.message}',
            );
            await _syncLogger.log(
              action: 'upload',
              entity: scope,
              result: 'error',
              error: error.message,
              extra: {'type': 'conflict'},
            );
            if (!isManualProductConflict &&
                allowCloudPull &&
                error.returnedRecords.isNotEmpty) {
              await repository.mergeRemoteRecords(error.returnedRecords);
            }
            // Keep download cursors untouched on upload-conflict responses.
            // The authoritative cursor must come from a download cycle.

            final conflictIds = error.conflicts
                .map((item) => item.recordSyncId.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false);
            final affectedIds = <String>{
              entryItems.single.recordSyncId,
              ...conflictIds,
            }.toList(growable: false);

            final returnedSyncIds = error.returnedRecords
                .map(_readReturnedRecordSyncId)
                .whereType<String>()
                .toSet();
            final backendAcknowledgedIds = affectedIds
                .where((id) => returnedSyncIds.contains(id))
                .toList(growable: false);
            final stillConflictedIds = affectedIds
                .where((id) => !returnedSyncIds.contains(id))
                .toList(growable: false);

            final idsToMarkAsConflict = isManualProductConflict
                ? affectedIds
                : stillConflictedIds;

            if (idsToMarkAsConflict.isNotEmpty) {
              await repository.markAsConflict(idsToMarkAsConflict);
            }

            await _conflictService.logUploadConflicts(
              scope: scope,
              queuedItems: entryItems,
              exception: error,
              strategyOverride: effectiveStrategy.storageValue,
              serverTime: error.serverTime,
              conflictReason: error.message,
            );

            // FASE 0 containment: never auto-download cloud state during
            // conflict handling while cloud pull is blocked.
            if (!isManualProductConflict &&
                allowCloudPull &&
                stillConflictedIds.isNotEmpty &&
                error.returnedRecords.isEmpty) {
              await _attemptConflictRecoveryDownload(
                scope: scope,
                settings: settings,
                repository: repository,
                conflictedIds: stillConflictedIds,
              );
            }

            if (backendAcknowledgedIds.isNotEmpty &&
                effectiveStrategy != SyncConflictStrategy.manual) {
              await repository.markAsSynced(backendAcknowledgedIds);
              await _conflictService.resolveConflicts(
                scope: scope,
                recordSyncIds: backendAcknowledgedIds,
                resolution: effectiveStrategy.storageValue,
              );
            }

            if (scope == 'sales' && affectedIds.isNotEmpty) {
              await _handleDependentInstallmentConflictsForSales(
                saleSyncIds: affectedIds,
                settings: settings,
              );
            }

            await _deleteQueuedRecords(scope, affectedIds);

            if (isManualProductConflict) {
              _log(
                '[sync-upload] PRODUCT_CONFLICT_STORED '
                'scope=$scope count=${affectedIds.length} '
                'recordSyncIds=${affectedIds.join(',')}',
              );
              await _syncLogger.log(
                action: 'upload-conflict',
                entity: scope,
                result: 'pending',
                error: '1 conflicto de sincronizacion',
                extra: {'count': affectedIds.length, 'scope': scope},
              );
              await _refreshState(clearLastError: true);
              batchProcessedCount += affectedIds.length;
              continue;
            }

            final retryIds = entryItems
                .map((item) => item.recordSyncId)
                .where((id) => !affectedIds.contains(id))
                .toList(growable: false);
            if (retryIds.isNotEmpty) {
              await _scheduleRetry(
                scope: scope,
                recordSyncIds: retryIds,
                errorMessage: error.message,
              );
            }
            if (stillConflictedIds.isNotEmpty) {
              unavailableScopes.add(scope);
            }
          } on SocketException catch (error) {
            _log(
              '[sync-upload] SOCKET_ERROR '
              'scope=$scope recordSyncId=${entryItems.single.recordSyncId} '
              'message=${error.message}',
            );
            await _syncLogger.log(
              action: 'upload',
              entity: scope,
              result: 'error',
              error: error.message,
              extra: {'type': 'socket'},
            );
            // No diferimos el item por errores de conectividad.
            // next_attempt_at permanece en 'now', por lo que el siguiente
            // tick del timer lo reintentara inmediatamente cuando el internet
            // se restaure. Solo actualizamos last_error para diagnostico.
            await _markConnectivityError(
              scope: scope,
              recordSyncIds: entryItems.map((item) => item.recordSyncId),
              errorMessage: 'Sin conexion: ${error.message}',
            );
            unavailableScopes.add(scope);
          } on HttpException catch (error) {
            _log(
              '[sync-upload] HTTP_ERROR '
              'scope=$scope recordSyncId=${entryItems.single.recordSyncId} '
              'message=${error.message}',
            );
            if (_isUnauthorizedHttpError(error)) {
              await _pauseQueueForAuthRequired(
                scope: scope,
                recordSyncIds: entryItems.map((item) => item.recordSyncId),
                reason:
                    'AUTH_REQUIRED: sesion de nube vencida o rechazada por backend.',
              );
              await _handleCloudSessionExpired(
                'La sesion de nube vencio o fue rechazada por el backend.',
              );
              return processedCount;
            }
            if (_isDeviceWriteUnauthorizedError(error)) {
              final reason =
                  'Esta PC no está autorizada para sincronizar. Actívela desde Configuración.';
              await _syncLogger.log(
                action: 'upload',
                entity: scope,
                result: 'pending',
                error: reason,
                extra: {'type': 'device_write_blocked'},
              );
              await _pauseQueueForAuthRequired(
                scope: scope,
                recordSyncIds: entryItems.map((item) => item.recordSyncId),
                reason: reason,
              );
              unavailableScopes.add(scope);
              continue;
            }
            await _syncLogger.log(
              action: 'upload',
              entity: scope,
              result: 'error',
              error: error.message,
              extra: {'type': 'http'},
            );
            await _scheduleRetry(
              scope: scope,
              recordSyncIds: entryItems.map((item) => item.recordSyncId),
              errorMessage: error.message,
            );
            unavailableScopes.add(scope);
          } catch (error) {
            _log(
              '[sync-upload] UNEXPECTED_ERROR '
              'scope=$scope recordSyncId=${entryItems.single.recordSyncId} '
              'message=$error',
            );
            await _syncLogger.log(
              action: 'upload',
              entity: scope,
              result: 'error',
              error: error.toString(),
              extra: {'type': 'unexpected'},
            );
            await _scheduleRetry(
              scope: scope,
              recordSyncIds: entryItems.map((item) => item.recordSyncId),
              errorMessage: 'Error inesperado al procesar la cola: $error',
            );
            unavailableScopes.add(scope);
          }
        }

        processedCount += batchProcessedCount;
        if (orderedItems.length < limit || batchProcessedCount == 0) {
          return processedCount;
        }
      }
    } on DatabaseException catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log(
          'SQLite se cerro durante processQueue -> se omite ciclo y se reintentara',
        );
        await _refreshState(clearLastError: true);
        return 0;
      }
      rethrow;
    } finally {
      _isProcessing = false;
      await _refreshState();
    }
  }

  Future<int> syncPending({Iterable<String>? scopes}) async {
    final targetScopes = (scopes ?? _repositoriesByScope.keys)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    try {
      await _waitForIdle();

      for (final scope in targetScopes) {
        await refreshScope(scope);
      }

      return processQueue(includeDeferred: true);
    } on DatabaseException catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log('SQLite se cerro durante syncPending -> se reintentara luego');
        await _refreshState(clearLastError: true);
        return 0;
      }
      rethrow;
    }
  }

  Future<bool> hasLegacyDeleteBacklog({Iterable<String>? scopes}) async {
    final targetScopes = (scopes ?? _deleteAckRepairScopes)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .intersection(_deleteAckRepairScopes);
    if (targetScopes.isEmpty) {
      return false;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(targetScopes.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT 1 FROM ${DatabaseSchema.syncQueueTable} '
      'WHERE operation = ? '
      'AND scope IN ($placeholders) '
      'AND ('
      'last_error LIKE ? OR '
      'last_error LIKE ? OR '
      'last_error LIKE ?'
      ') '
      'LIMIT 1',
      [
        'delete',
        ...targetScopes,
        '%FOREIGN KEY constraint failed%',
        '%DELETE FROM solares WHERE deleted_at IS NOT NULL%',
        '%hard delete%',
      ],
    );
    return rows.isNotEmpty;
  }

  Future<void> _enqueue({
    required String scope,
    required String recordSyncId,
    required String operation,
    required Map<String, Object?> payload,
    required bool triggerProcessing,
  }) async {
    if (_isDisposed) {
      return;
    }
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final values = <String, Object?>{
      'scope': scope,
      'record_sync_id': recordSyncId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'updated_at': now,
      'next_attempt_at': now,
      'last_error': null,
      'attempt_count': 0,
    };

    await db.transaction((txn) async {
      final existingRows = await txn.query(
        DatabaseSchema.syncQueueTable,
        columns: ['id'],
        where: 'scope = ? AND record_sync_id = ?',
        whereArgs: [scope, recordSyncId],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        await txn.insert(DatabaseSchema.syncQueueTable, {
          ...values,
          'created_at': now,
        });
      } else {
        await txn.update(
          DatabaseSchema.syncQueueTable,
          values,
          where: 'scope = ? AND record_sync_id = ?',
          whereArgs: [scope, recordSyncId],
        );
      }
    });

    await _markSourceRowsAsQueued(
      scope: scope,
      recordSyncIds: [recordSyncId],
      payload: payload,
      queuedAt: now,
      operation: operation,
    );

    await _refreshState();
    if (triggerProcessing) {
      unawaited(processQueue());
    }
  }

  Future<void> _waitForIdle() async {
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    if (_isDisposed) {
      return;
    }
    final hasInternet = results.any(
      (result) => result != ConnectivityResult.none,
    );
    if (!hasInternet) {
      _log('Sin internet -> la cola queda pendiente hasta reconectar');
      return;
    }

    _log('Internet detectado -> reintentando sincronizacion pendiente');
    unawaited(SystemConfigService.instance.refresh());
    unawaited(syncPending());
  }

  bool _hasUnavailableDependency(String scope, Set<String> unavailableScopes) {
    return (_scopeDependencies[scope] ?? const <String>[]).any(
      unavailableScopes.contains,
    );
  }

  Future<List<SyncQueueItem>> _loadDueItems({
    required int limit,
    required bool includeDeferred,
  }) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: includeDeferred ? null : 'next_attempt_at <= ?',
      whereArgs: includeDeferred ? null : [DateTime.now().toIso8601String()],
      orderBy: 'created_at ASC, updated_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(SyncQueueItem.fromMap).toList(growable: false);
  }

  static Future<bool> _defaultConnectivityProbe(SyncSettings settings) async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasNetworkInterface = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasNetworkInterface) {
        return false;
      }

      final uri = Uri.parse(settings.normalizedBaseUrl);
      if (uri.host.trim().isEmpty) {
        return false;
      }
      final lookup = await InternetAddress.lookup(uri.host);
      return lookup.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<SyncQueueItem>> _loadPendingItemsForScopes(
    List<String> scopes,
  ) async {
    if (scopes.isEmpty) {
      return const <SyncQueueItem>[];
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(scopes.length, '?').join(', ');
    final rows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope IN ($placeholders)',
      whereArgs: scopes,
      orderBy: 'updated_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList(growable: false);
  }

  Future<List<SyncQueueItem>> _retainQueuedItems(
    String scope,
    Iterable<SyncQueueItem> items,
  ) async {
    final ids = items
        .map((item) => item.recordSyncId.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) {
      return const <SyncQueueItem>[];
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT record_sync_id FROM ${DatabaseSchema.syncQueueTable} '
      'WHERE scope = ? AND record_sync_id IN ($placeholders)',
      [scope, ...ids],
    );
    final survivingIds = rows
        .map((row) => row['record_sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    return items
        .where((item) => survivingIds.contains(item.recordSyncId))
        .toList(growable: false);
  }

  String? _readReturnedRecordSyncId(Map<String, dynamic> record) {
    final syncId =
        record['sync_id']?.toString().trim() ??
        record['record_sync_id']?.toString().trim() ??
        '';
    return syncId.isEmpty ? null : syncId;
  }

  Future<List<SyncQueueItem>> _filterBlockedClientQueueItems(
    List<SyncQueueItem> entryItems,
  ) async {
    final blocked = <String>[];
    final kept = <SyncQueueItem>[];

    for (final item in entryItems) {
      if (ClientDataGuard.shouldBlockClientUpload(item.payload)) {
        blocked.add(item.recordSyncId);
      } else {
        kept.add(item);
      }
    }

    if (blocked.isEmpty) {
      return entryItems;
    }

    await _softDeleteClients(blocked);
    await _deleteQueuedRecords('clients', blocked);
    await _refreshState();
    return kept;
  }

  Future<void> _softDeleteClients(Iterable<String> syncIds) async {
    final normalized = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(normalized.length, '?').join(', ');
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.clientsTable} '
      'SET deleted_at = ?, fecha_actualizacion = ?, sync_status = ? '
      'WHERE sync_id IN ($placeholders)',
      [now, now, DatabaseSchema.syncStatusSynced, ...normalized],
    );
  }

  Future<void> _deleteQueuedRecords(
    String scope,
    Iterable<String> recordSyncIds,
  ) async {
    if (_isDisposed) {
      return;
    }
    final ids = recordSyncIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    try {
      final db = await _appDatabase.database;
      final placeholders = List.filled(ids.length, '?').join(', ');
      await db.rawDelete(
        'DELETE FROM ${DatabaseSchema.syncQueueTable} '
        'WHERE scope = ? AND record_sync_id IN ($placeholders)',
        [scope, ...ids],
      );
      await _refreshState();
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log(
          'SQLite cerrandose durante deleteQueuedRecords -> se omite limpieza tardia',
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> _repairFailedDeleteQueueEntries(
    String scope,
    Iterable<SyncQueueItem> items,
    SyncSettings settings,
  ) async {
    final tableName = _scopeTableMap[scope];
    if (tableName == null) {
      return;
    }
    final deleteIds = items
        .where((item) => item.scope == scope && item.operation == 'delete')
        .map((item) => item.recordSyncId.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (deleteIds.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(deleteIds.length, '?').join(', ');
    final queueRows = await db.rawQuery(
      'SELECT record_sync_id, last_error, attempt_count '
      'FROM ${DatabaseSchema.syncQueueTable} '
      'WHERE scope = ? AND operation = ? '
      'AND record_sync_id IN ($placeholders)',
      [scope, 'delete', ...deleteIds],
    );
    if (queueRows.isEmpty) {
      return;
    }

    final sourceRows = await db.rawQuery(
      'SELECT sync_id, deleted_at, sync_status '
      'FROM $tableName '
      'WHERE sync_id IN ($placeholders)',
      deleteIds,
    );
    final sourceRowBySyncId = {
      for (final row in sourceRows)
        row['sync_id']?.toString().trim() ?? '': row,
    };
    final orphanQueueIds = queueRows
        .where((row) {
          final lastError = row['last_error']?.toString().trim() ?? '';
          final attempts = switch (row['attempt_count']) {
            final int value => value,
            final num value => value.toInt(),
            _ => int.tryParse(row['attempt_count']?.toString() ?? '0') ?? 0,
          };
          // Only prune orphan deletes that have already failed/retried.
          // Fresh deletes without source row still get one upload attempt.
          return lastError.isNotEmpty || attempts > 0;
        })
        .map((row) => row['record_sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .where((value) => !sourceRowBySyncId.containsKey(value))
        .toSet();
    final failedIds = sourceRows
        .where(
          (row) =>
              (row['deleted_at']?.toString().trim().isNotEmpty ?? false) &&
              row['sync_status'] == DatabaseSchema.syncStatusFailed,
        )
        .map((row) => row['sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    final syncedTombstoneIds = sourceRows
        .where(
          (row) =>
              (row['deleted_at']?.toString().trim().isNotEmpty ?? false) &&
              row['sync_status'] == DatabaseSchema.syncStatusSynced,
        )
        .map((row) => row['sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    final legacyQueueIds = queueRows
        .where(
          (row) => _hasLegacyHardDeleteError(row['last_error']?.toString()),
        )
        .map((row) => row['record_sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    final authoritativeCheckIds = syncedTombstoneIds
        .intersection(legacyQueueIds)
        .toList(growable: false);
    final remoteDeletedIds = authoritativeCheckIds.isEmpty
        ? const <String>{}
        : await _loadRemoteDeletedSyncIds(
            scope: scope,
            settings: settings,
            candidateIds: authoritativeCheckIds,
          );
    final acknowledgedQueueIds =
        legacyQueueIds.where((id) => remoteDeletedIds.contains(id)).toSet()
          ..addAll(orphanQueueIds);
    final retryQueueIds = legacyQueueIds.difference(acknowledgedQueueIds);
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      if (failedIds.isNotEmpty) {
        final failedPlaceholders = List.filled(
          failedIds.length,
          '?',
        ).join(', ');
        await txn.rawUpdate(
          'UPDATE $tableName '
          'SET sync_status = ?, '
          'last_modified_local = COALESCE(last_modified_local, ?), '
          'fecha_actualizacion = COALESCE(fecha_actualizacion, ?) '
          'WHERE deleted_at IS NOT NULL '
          'AND sync_status = ? '
          'AND sync_id IN ($failedPlaceholders)',
          [
            DatabaseSchema.syncStatusPendingDelete,
            now,
            now,
            DatabaseSchema.syncStatusFailed,
            ...failedIds,
          ],
        );
      }

      final resetQueueIds = {...failedIds, ...retryQueueIds};
      if (resetQueueIds.isNotEmpty) {
        final resetPlaceholders = List.filled(
          resetQueueIds.length,
          '?',
        ).join(', ');
        final sourceResetIds = resetQueueIds
            .where((id) {
              final row = sourceRowBySyncId[id];
              return row != null &&
                  (row['deleted_at']?.toString().trim().isNotEmpty ?? false);
            })
            .toList(growable: false);
        if (sourceResetIds.isNotEmpty) {
          final sourceResetPlaceholders = List.filled(
            sourceResetIds.length,
            '?',
          ).join(', ');
          await txn.rawUpdate(
            'UPDATE $tableName '
            'SET sync_status = ?, '
            'last_modified_local = COALESCE(last_modified_local, ?), '
            'fecha_actualizacion = COALESCE(fecha_actualizacion, ?) '
            'WHERE deleted_at IS NOT NULL '
            'AND sync_id IN ($sourceResetPlaceholders)',
            [
              DatabaseSchema.syncStatusPendingDelete,
              now,
              now,
              ...sourceResetIds,
            ],
          );
        }

        await txn.rawUpdate(
          'UPDATE ${DatabaseSchema.syncQueueTable} '
          'SET last_error = NULL, attempt_count = 0, updated_at = ?, next_attempt_at = ? '
          'WHERE scope = ? AND operation = ? AND record_sync_id IN ($resetPlaceholders)',
          [now, now, scope, 'delete', ...resetQueueIds],
        );
      }

      if (acknowledgedQueueIds.isNotEmpty) {
        final ackPlaceholders = List.filled(
          acknowledgedQueueIds.length,
          '?',
        ).join(', ');
        await txn.rawDelete(
          'DELETE FROM ${DatabaseSchema.syncQueueTable} '
          'WHERE scope = ? AND operation = ? AND record_sync_id IN ($ackPlaceholders)',
          [scope, 'delete', ...acknowledgedQueueIds],
        );
      }
    });

    if (failedIds.isNotEmpty || retryQueueIds.isNotEmpty) {
      await _syncLogger.log(
        action: scope == 'products'
            ? 'product_delete_skipped_hard_delete'
            : 'delete_skipped_hard_delete',
        entity: scope,
        result: 'warning',
        extra: {'count': failedIds.length + retryQueueIds.length},
      );
    }
    if (acknowledgedQueueIds.isNotEmpty) {
      await _conflictService.resolveConflicts(
        scope: scope,
        recordSyncIds: acknowledgedQueueIds,
        resolution: 'synced',
      );
      await _syncLogger.log(
        action: scope == 'products'
            ? 'product_delete_queue_repaired'
            : 'delete_queue_repaired',
        entity: scope,
        result: 'ok',
        extra: {'count': acknowledgedQueueIds.length},
      );
    }
    if (orphanQueueIds.isNotEmpty) {
      await _syncLogger.log(
        action: 'delete_queue_orphan_pruned',
        entity: scope,
        result: 'ok',
        extra: {'count': orphanQueueIds.length},
      );
    }
    if (failedIds.isNotEmpty ||
        retryQueueIds.isNotEmpty ||
        acknowledgedQueueIds.isNotEmpty) {
      await _configRepository.clearCursors(_businessRepairScopes);
    }
    await _refreshState(clearLastError: acknowledgedQueueIds.isNotEmpty);
  }

  Future<Set<String>> _loadRemoteDeletedSyncIds({
    required String scope,
    required SyncSettings settings,
    required Iterable<String> candidateIds,
  }) async {
    final normalizedIds = candidateIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedIds.isEmpty) {
      return const <String>{};
    }

    final response = await _apiClient.downloadChanges(
      settings: settings,
      updatedSinceByScope: {
        scope: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      },
    );
    final deletedIds = <String>{};
    for (final record in response.recordsForScope(scope)) {
      final syncId = _readReturnedRecordSyncId(record);
      final deletedAt = record['deleted_at']?.toString().trim() ?? '';
      if (syncId != null &&
          normalizedIds.contains(syncId) &&
          deletedAt.isNotEmpty) {
        deletedIds.add(syncId);
      }
    }
    return deletedIds;
  }

  bool _hasLegacyHardDeleteError(String? errorMessage) {
    final normalized = errorMessage?.trim().toLowerCase() ?? '';
    return normalized.contains('foreign key constraint failed') ||
        normalized.contains(
          'delete from solares where deleted_at is not null',
        ) ||
        normalized.contains('hard delete');
  }

  Future<void> _handleDependentInstallmentConflictsForSales({
    required Iterable<String> saleSyncIds,
    required SyncSettings settings,
  }) async {
    final installmentsRepository = _repositoriesByScope['installments'];
    if (installmentsRepository == null) {
      return;
    }

    final dependentInstallmentIds = await _findQueuedInstallmentIdsForSales(
      saleSyncIds,
    );
    if (dependentInstallmentIds.isEmpty) {
      return;
    }

    await installmentsRepository.markAsConflict(dependentInstallmentIds);
    await _deleteQueuedRecords('installments', dependentInstallmentIds);
    await _attemptConflictRecoveryDownload(
      scope: 'installments',
      settings: settings,
      repository: installmentsRepository,
      conflictedIds: dependentInstallmentIds,
    );
  }

  Future<List<String>> _findQueuedInstallmentIdsForSales(
    Iterable<String> saleSyncIds,
  ) async {
    final normalizedSaleIds = saleSyncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedSaleIds.isEmpty) {
      return const [];
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(normalizedSaleIds.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT DISTINCT sq.record_sync_id
      FROM ${DatabaseSchema.syncQueueTable} sq
      INNER JOIN ${DatabaseSchema.installmentsTable} i
        ON i.sync_id = sq.record_sync_id
      INNER JOIN ${DatabaseSchema.salesTable} s
        ON s.id = i.venta_id
      WHERE sq.scope = 'installments'
        AND s.sync_id IN ($placeholders)
      ''', normalizedSaleIds);

    return rows
        .map((row) => row['record_sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _deleteQueuedScopes(Iterable<String> scopes) async {
    final normalizedScopes = scopes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedScopes.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(normalizedScopes.length, '?').join(', ');
    await db.rawDelete(
      'DELETE FROM ${DatabaseSchema.syncQueueTable} '
      'WHERE scope IN ($placeholders)',
      normalizedScopes,
    );
    await _refreshState();
  }

  Future<void> _scheduleRetry({
    required String scope,
    required Iterable<String> recordSyncIds,
    required String errorMessage,
  }) async {
    final ids = recordSyncIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final settings = await _configRepository.loadSettings();
    final db = await _appDatabase.database;
    final now = DateTime.now();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final currentAttemptsRows = await db.rawQuery(
      'SELECT MAX(attempt_count) AS attempt_count FROM ${DatabaseSchema.syncQueueTable} '
      'WHERE scope = ? AND record_sync_id IN ($placeholders)',
      [scope, ...ids],
    );
    final currentAttemptsValue = currentAttemptsRows.isEmpty
        ? 0
        : currentAttemptsRows.first['attempt_count'];
    final currentAttempts = currentAttemptsValue is num
        ? currentAttemptsValue.toInt()
        : int.tryParse(currentAttemptsValue?.toString() ?? '') ?? 0;
    if (currentAttempts >= _maxRetryAttempts) {
      final terminalError =
          '$errorMessage | Maximos reintentos alcanzados ($_maxRetryAttempts).';
      final terminalAttemptAt = now
          .add(const Duration(hours: 24))
          .toIso8601String();
      await db.rawUpdate(
        'UPDATE ${DatabaseSchema.syncQueueTable} '
        'SET updated_at = ?, '
        'next_attempt_at = ?, '
        'last_error = ? '
        'WHERE scope = ? AND record_sync_id IN ($placeholders)',
        [
          now.toIso8601String(),
          terminalAttemptAt,
          terminalError,
          scope,
          ...ids,
        ],
      );
      await _markSourceRowsAsFailed(
        scope: scope,
        recordSyncIds: ids,
        failedAt: now.toIso8601String(),
      );
      await _configRepository.saveLastRun(
        errorMessage: terminalError,
        status: SyncRuntimeStatus.error,
      );
      await _refreshState(lastError: terminalError);
      return;
    }

    final retryNumber = currentAttempts + 1;
    final retryDelay = retryNumber <= 3
        ? Duration(seconds: settings.queueRetryInterval.inSeconds * retryNumber)
        : const Duration(minutes: 5);
    final nextAttemptAt = now.add(retryDelay).toIso8601String();
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.syncQueueTable} '
      'SET attempt_count = attempt_count + 1, '
      'updated_at = ?, '
      'next_attempt_at = ?, '
      'last_error = ? '
      'WHERE scope = ? AND record_sync_id IN ($placeholders)',
      [now.toIso8601String(), nextAttemptAt, errorMessage, scope, ...ids],
    );
    await _markSourceRowsAsFailed(
      scope: scope,
      recordSyncIds: ids,
      failedAt: now.toIso8601String(),
    );
    await _configRepository.saveLastRun(
      errorMessage: errorMessage,
      status: SyncRuntimeStatus.pending,
    );
    await _refreshState(lastError: errorMessage);
  }

  /// Registra un error de conectividad en la cola SIN diferir [next_attempt_at].
  /// Esto garantiza que los items sean reintentados en el siguiente tick del
  /// timer periodico en cuanto se restaure la conexion.
  Future<void> _markConnectivityError({
    required String scope,
    required Iterable<String> recordSyncIds,
    required String errorMessage,
  }) async {
    final ids = recordSyncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final now = DateTime.now();
    final placeholders = List.filled(ids.length, '?').join(', ');
    // Solo actualizamos updated_at y last_error; next_attempt_at queda
    // en su valor original (ya en el pasado) para que la cola lo considere
    // listo en el proximo ciclo.
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.syncQueueTable} '
      'SET last_error = ?, updated_at = ? '
      'WHERE scope = ? AND record_sync_id IN ($placeholders)',
      [errorMessage, now.toIso8601String(), scope, ...ids],
    );
    await _configRepository.saveLastRun(
      errorMessage: errorMessage,
      status: SyncRuntimeStatus.pending,
    );
    await _refreshState(lastError: errorMessage);
  }

  Future<void> _pauseQueueForAuthRequired({
    required String scope,
    required Iterable<String> recordSyncIds,
    required String reason,
  }) async {
    final ids = recordSyncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final now = DateTime.now();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.syncQueueTable} '
      'SET updated_at = ?, '
      'next_attempt_at = ?, '
      'last_error = ? '
      'WHERE scope = ? AND record_sync_id IN ($placeholders)',
      [
        now.toIso8601String(),
        now.add(const Duration(hours: 6)).toIso8601String(),
        reason,
        scope,
        ...ids,
      ],
    );

    await _configRepository.saveLastRun(
      errorMessage: reason,
      status: SyncRuntimeStatus.pending,
    );
    await _refreshState(lastError: reason);
  }

  Future<void> _markSourceRowsAsQueued({
    required String scope,
    required Iterable<String> recordSyncIds,
    required Map<String, Object?> payload,
    required String queuedAt,
    required String operation,
  }) async {
    final tableName = _scopeTableMap[scope];
    if (tableName == null) {
      return;
    }

    final ids = recordSyncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    final nextStatus = _resolveQueuedSyncStatus(payload, operation: operation);
    await db.rawUpdate(
      'UPDATE $tableName '
      'SET sync_status = ?, last_modified_local = COALESCE(last_modified_local, ?) '
      'WHERE sync_id IN ($placeholders) '
      'AND ('
      'COALESCE(sync_status, \'\') <> ? '
      'OR last_modified_local IS NULL '
      ')',
      [nextStatus, queuedAt, ...ids, nextStatus],
    );
  }

  Future<void> _markSourceRowsAsFailed({
    required String scope,
    required Iterable<String> recordSyncIds,
    required String failedAt,
  }) async {
    final tableName = _scopeTableMap[scope];
    if (tableName == null) {
      return;
    }

    final ids = recordSyncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE $tableName '
      'SET sync_status = ?, last_modified_local = COALESCE(last_modified_local, ?) '
      'WHERE sync_id IN ($placeholders) '
      'AND ('
      'COALESCE(sync_status, \'\') <> ? '
      'OR last_modified_local IS NULL '
      ')',
      [
        DatabaseSchema.syncStatusFailed,
        failedAt,
        ...ids,
        DatabaseSchema.syncStatusFailed,
      ],
    );
  }

  String _resolveQueuedSyncStatus(
    Map<String, Object?> payload, {
    required String operation,
  }) {
    if (operation == 'delete' ||
        (payload['deleted_at']?.toString().trim().isNotEmpty ?? false)) {
      return DatabaseSchema.syncStatusPendingDelete;
    }

    final currentStatus = payload['sync_status']
        ?.toString()
        .trim()
        .toLowerCase();
    if (currentStatus == DatabaseSchema.syncStatusPendingCreate ||
        currentStatus == DatabaseSchema.syncStatusPendingUpdate) {
      return currentStatus!;
    }

    final hasRemoteIdentity =
        (payload['id_remote']?.toString().trim().isNotEmpty ?? false) ||
        (payload['last_modified_remote']?.toString().trim().isNotEmpty ??
            false);
    return hasRemoteIdentity
        ? DatabaseSchema.syncStatusPendingUpdate
        : DatabaseSchema.syncStatusPendingCreate;
  }

  Future<void> _refreshState({
    String? lastError,
    bool clearLastError = false,
  }) async {
    if (_isDisposed) {
      return;
    }
    try {
      final pending = await pendingCount();
      final resolvedError = await _resolveLastError(
        pendingCount: pending,
        lastErrorOverride: lastError,
        clearLastError: clearLastError,
      );
      final nextState = SyncQueueState(
        pendingCount: pending,
        isProcessing: _isProcessing,
        lastError: resolvedError,
      );
      _state = nextState;
      if (!_stateController.isClosed) {
        _stateController.add(nextState);
      }
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log(
          'SQLite cerrandose durante refreshState -> se conserva ultimo estado',
        );
        return;
      }
      rethrow;
    }
  }

  Future<String?> _resolveLastError({
    required int pendingCount,
    required String? lastErrorOverride,
    required bool clearLastError,
  }) async {
    if (clearLastError || pendingCount == 0) {
      return null;
    }

    final override = lastErrorOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    // If there are pending items but none has a recorded `last_error`,
    // we should not show a global "Error" badge.
    // Instead, leave it null so the UI shows "Pendiente".
    final latestItemError = await _loadLatestQueueItemError();
    final normalized = latestItemError?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<String?> _loadLatestQueueItemError() async {
    if (_isDisposed) {
      return _state.lastError;
    }
    try {
      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.syncQueueTable,
        columns: ['last_error'],
        where: "last_error IS NOT NULL AND TRIM(last_error) != ''",
        orderBy: 'updated_at DESC, id DESC',
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return rows.first['last_error']?.toString();
    } on DatabaseException catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log(
          'SQLite cerrandose durante _loadLatestQueueItemError -> se conserva estado local',
        );
        return _state.lastError;
      }
      rethrow;
    }
  }

  Future<void> _handleCloudSessionExpired(String reason) async {
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
    await _refreshState(lastError: reason);
    final notify = _onCloudSessionExpired;
    if (notify != null) {
      await notify(reason);
    } else {
      await stop();
    }
  }

  bool _isUnauthorizedHttpError(HttpException error) {
    final message = error.message.toLowerCase();
    return message.contains('401') || message.contains('unauthorized');
  }

  bool _isDeviceWriteUnauthorizedError(HttpException error) {
    final normalized = error.message.trim().toUpperCase();
    return normalized.contains('DEVICE_NOT_AUTHORIZED') ||
        normalized.contains('DEVICE_NOT_AUTHORIZED_FOR_WRITE');
  }

  bool _isDatabaseClosedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database_closed');
  }

  Future<List<SyncQueueItem>> _pruneOrphanedUpserts(
    String scope,
    List<SyncQueueItem> entryItems,
    SyncRepository repository,
  ) async {
    final pendingRecords = await repository.getPendingRecords();
    // Conservative guard for sales: avoid dropping queued upserts when the
    // repository temporarily returns an empty set due to reference timing.
    if (scope == 'sales' && pendingRecords.isEmpty) {
      _log(
        '[sync-upload] ORPHAN_PRUNE_SKIPPED scope=sales reason=pending_records_empty',
      );
      return entryItems;
    }
    final validUpsertIds = pendingRecords
        .map((record) => record['sync_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();

    final orphanedUpserts = entryItems
        .where(
          (item) =>
              item.operation == 'upsert' &&
              !validUpsertIds.contains(item.recordSyncId.trim()),
        )
        .map((item) => item.recordSyncId)
        .toList(growable: false);

    if (orphanedUpserts.isNotEmpty) {
      await _deleteQueuedRecords(scope, orphanedUpserts);
      entryItems = entryItems
          .where((item) => !orphanedUpserts.contains(item.recordSyncId))
          .toList(growable: false);
    }

    return entryItems;
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

  Future<void> _attemptConflictRecoveryDownload({
    required String scope,
    required SyncSettings settings,
    required SyncRepository repository,
    required List<String> conflictedIds,
  }) async {
    if (!allowCloudPull) {
      _log(
        'CONFLICT RECOVERY SKIPPED -> scope=$scope motivo=ALLOW_CLOUD_PULL=false',
      );
      return;
    }
    if (_conflictRecoveryDownloadedScopes.contains(scope)) {
      return;
    }
    _conflictRecoveryDownloadedScopes.add(scope);

    try {
      _log(
        'CONFLICT RECOVERY -> scope=$scope conflicted=${conflictedIds.length} descargando estado remoto completo',
      );
      final response = await _apiClient.downloadChanges(
        settings: settings,
        updatedSince: null,
      );
      final scopeRecords = response.recordsForScope(scope);
      if (scopeRecords.isEmpty) {
        return;
      }

      await repository.mergeRemoteRecords(scopeRecords);

      final downloadedIds = scopeRecords
          .map(_readReturnedRecordSyncId)
          .whereType<String>()
          .toSet();
      final resolvedIds = conflictedIds
          .where((id) => downloadedIds.contains(id))
          .toList(growable: false);
      if (resolvedIds.isEmpty) {
        return;
      }

      await repository.markAsSynced(resolvedIds);
      await _conflictService.resolveConflicts(
        scope: scope,
        recordSyncIds: resolvedIds,
        resolution: 'server_won',
      );

      final cursor = _findLatestTimestamp(scopeRecords);
      if (cursor != null) {
        await _configRepository.saveCursor(scope, cursor);
      }
    } on HttpException catch (error) {
      if (_isUnauthorizedHttpError(error)) {
        await _handleCloudSessionExpired(
          'La sesion de nube vencio o fue rechazada por el backend.',
        );
        return;
      }
      _log('CONFLICT RECOVERY ERROR -> scope=$scope : $error');
    } catch (error) {
      _log('CONFLICT RECOVERY ERROR -> scope=$scope : $error');
    }
  }
}

class SyncQueueState {
  const SyncQueueState({
    this.pendingCount = 0,
    this.isProcessing = false,
    this.lastError,
  });

  final int pendingCount;
  final bool isProcessing;
  final String? lastError;
}

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.scope,
    required this.recordSyncId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.lastError,
  });

  final int id;
  final String scope;
  final String recordSyncId;
  final String operation;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final String? lastError;

  Map<String, Object?> toUploadPayload() {
    return payload;
  }

  factory SyncQueueItem.fromMap(Map<String, Object?> map) {
    final decoded = jsonDecode(map['payload_json'] as String? ?? '{}');
    final payload = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};

    return SyncQueueItem(
      id: map['id'] is int
          ? map['id'] as int
          : int.tryParse(map['id']?.toString() ?? '') ?? 0,
      scope: map['scope'] as String? ?? '',
      recordSyncId: map['record_sync_id'] as String? ?? '',
      operation: map['operation'] as String? ?? 'upsert',
      payload: payload,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastError: map['last_error'] as String?,
    );
  }
}
