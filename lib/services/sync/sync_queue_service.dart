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

  static const List<String> _syncOrder = [
    'clients',
    'products',
    'sellers',
    'sales',
    'installments',
    'payments',
  ];
  static const Map<String, List<String>> _scopeDependencies = {
    'clients': [],
    'products': ['clients'],
    'sellers': [],
    'sales': ['clients', 'products'],
    'installments': ['sales'],
    'payments': ['sales'],
  };

  Timer? _retryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isProcessing = false;
  SyncQueueState _state = const SyncQueueState();

  Stream<SyncQueueState> get stateStream => _stateController.stream;
  SyncQueueState get state => _state;

  void _log(String message) {
    developer.log(message, name: 'SistemaSolares.SyncQueue');
  }

  void registerRepository(SyncRepository repository) {
    _repositoriesByScope[repository.scope] = repository;
  }

  Future<void> start() async {
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
      unawaited(processQueue());
    });
    await _refreshState();
    unawaited(processQueue());
  }

  void dispose() {
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
  }) {
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
    );
  }

  Future<void> enqueueDelete({
    required String scope,
    required String recordSyncId,
    required Map<String, Object?> payload,
  }) {
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
    );
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
    } on DatabaseException catch (error) {
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

      final items = await _loadDueItems(
        limit: limit,
        includeDeferred: includeDeferred,
      );
      if (items.isEmpty) {
        return 0;
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

      var processedCount = 0;
      final unsupportedScopes = orderedItems
          .map((item) => item.scope)
          .where((scope) => !_repositoriesByScope.containsKey(scope))
          .toSet();
      if (unsupportedScopes.isNotEmpty) {
        await _deleteQueuedScopes(unsupportedScopes);
      }

      final unavailableScopes = <String>{};
      for (final item in orderedItems) {
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
        entryItems = await _pruneOrphanedUpserts(scope, entryItems, repository);
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
          final response = await _apiClient.uploadQueuedRecords(
            settings: settings,
            recordsByScope: {
              scope: [entryItems.single.toUploadPayload()],
            },
          );

          final returnedRecords = response.recordsForScope(scope);
          if (returnedRecords.isNotEmpty) {
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
            await repository.markAsSynced(acknowledgedSyncIds);
            await _deleteQueuedRecords(scope, acknowledgedSyncIds);
            await _conflictService.resolveConflicts(
              scope: scope,
              recordSyncIds: acknowledgedSyncIds,
              resolution: 'synced',
            );
            processedCount += acknowledgedSyncIds.length;
            await _syncLogger.log(
              action: 'upload',
              entity: scope,
              result: 'ok',
              extra: {'count': acknowledgedSyncIds.length},
            );
          }

          final unconfirmedIds = entryItems
              .where((item) => !acknowledgedSyncIds.contains(item.recordSyncId))
              .map((item) => item.recordSyncId)
              .toList(growable: false);
          if (unconfirmedIds.isNotEmpty) {
            await _scheduleRetry(
              scope: scope,
              recordSyncIds: unconfirmedIds,
              errorMessage:
                  'La API no confirmo todos los registros de la cola.',
            );
            unavailableScopes.add(scope);
          }

          final cursor = _findLatestTimestamp(returnedRecords);
          if (cursor != null) {
            await _configRepository.saveCursor(scope, cursor);
          }
        } on SyncConflictException catch (error) {
          await _syncLogger.log(
            action: 'upload',
            entity: scope,
            result: 'error',
            error: error.message,
            extra: {'type': 'conflict'},
          );
          if (error.returnedRecords.isNotEmpty) {
            await repository.mergeRemoteRecords(error.returnedRecords);
          }
          final cursor = _findLatestTimestamp(error.returnedRecords);
          if (cursor != null) {
            await _configRepository.saveCursor(scope, cursor);
          }

          final conflictIds = error.conflicts
              .map((item) => item.recordSyncId.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false);
          final affectedIds = conflictIds.isEmpty
              ? [entryItems.single.recordSyncId]
              : conflictIds;

          await repository.markAsConflict(affectedIds);
          await _conflictService.logUploadConflicts(
            scope: scope,
            queuedItems: entryItems,
            exception: error,
          );
          await _deleteQueuedRecords(scope, affectedIds);

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
          unavailableScopes.add(scope);
        } on SocketException catch (error) {
          await _syncLogger.log(
            action: 'upload',
            entity: scope,
            result: 'error',
            error: error.message,
            extra: {'type': 'socket'},
          );
          await _scheduleRetry(
            scope: scope,
            recordSyncIds: entryItems.map((item) => item.recordSyncId),
            errorMessage: 'Sin conexion: ${error.message}',
          );
          unavailableScopes.add(scope);
        } on HttpException catch (error) {
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

      return processedCount;
    } on DatabaseException catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log(
          'SQLite se cerro durante processQueue -> se omite ciclo y se reintentara',
        );
        await _configRepository.saveLastRun(
          errorMessage: null,
          status: SyncRuntimeStatus.pending,
        );
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
      for (final scope in targetScopes) {
        await refreshScope(scope);
      }

      return processQueue(includeDeferred: true);
    } on DatabaseException catch (error) {
      if (_isDatabaseClosedError(error)) {
        _log('SQLite se cerro durante syncPending -> se reintentara luego');
        await _refreshState();
        return 0;
      }
      rethrow;
    }
  }

  Future<void> _enqueue({
    required String scope,
    required String recordSyncId,
    required String operation,
    required Map<String, Object?> payload,
  }) async {
    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    final existingRows = await db.query(
      DatabaseSchema.syncQueueTable,
      columns: ['id'],
      where: 'scope = ? AND record_sync_id = ?',
      whereArgs: [scope, recordSyncId],
      limit: 1,
    );

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

    if (existingRows.isEmpty) {
      await db.insert(DatabaseSchema.syncQueueTable, {
        ...values,
        'created_at': now,
      });
    } else {
      await db.update(
        DatabaseSchema.syncQueueTable,
        values,
        where: 'scope = ? AND record_sync_id = ?',
        whereArgs: [scope, recordSyncId],
      );
    }

    await _refreshState();
    unawaited(processQueue());
  }

  Future<void> _waitForIdle() async {
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    final hasInternet = results.any(
      (result) => result != ConnectivityResult.none,
    );
    if (!hasInternet) {
      _log('Sin internet -> la cola queda pendiente hasta reconectar');
      return;
    }

    _log('Internet detectado -> reintentando sincronizacion pendiente');
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
      if (connectivityResults.contains(ConnectivityResult.none)) {
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
    final ids = recordSyncIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawDelete(
      'DELETE FROM ${DatabaseSchema.syncQueueTable} '
      'WHERE scope = ? AND record_sync_id IN ($placeholders)',
      [scope, ...ids],
    );
    await _refreshState();
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
    await _configRepository.saveLastRun(
      errorMessage: errorMessage,
      status: SyncRuntimeStatus.pending,
    );
    await _refreshState(lastError: errorMessage);
  }

  Future<void> _refreshState({String? lastError}) async {
    final pending = await pendingCount();
    final resolvedError = lastError ?? (pending == 0 ? null : _state.lastError);
    final nextState = SyncQueueState(
      pendingCount: pending,
      isProcessing: _isProcessing,
      lastError: resolvedError,
    );
    _state = nextState;
    if (!_stateController.isClosed) {
      _stateController.add(nextState);
    }
  }

  bool _isDatabaseClosedError(DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('database_closed');
  }

  Future<List<SyncQueueItem>> _pruneOrphanedUpserts(
    String scope,
    List<SyncQueueItem> entryItems,
    SyncRepository repository,
  ) async {
    final pendingRecords = await repository.getPendingRecords();
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
