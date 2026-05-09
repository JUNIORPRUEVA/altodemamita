import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_flags.dart';
import '../../models/sync/sync_connection_status.dart';
import '../../models/sync/sync_manager_state.dart';
import '../../models/sync/sync_report.dart';
import '../realtime_sync_service.dart';
import 'sync_conflict_service.dart';
import 'sync_queue_service.dart';
import 'sync_service.dart';

@visibleForTesting
SyncConnectionStatus resolveEffectiveSyncConnectionStatus({
  required RealtimeSyncState realtimeState,
  required SyncQueueState queueState,
}) {
  if (realtimeState.connectionStatus == SyncConnectionStatus.disconnected) {
    final queueError = queueState.lastError?.trim();
    final isQueueHealthy =
        !queueState.isProcessing &&
        queueState.pendingCount == 0 &&
        (queueError == null || queueError.isEmpty);

    if (isQueueHealthy) {
      return SyncConnectionStatus.connected;
    }
  }

  return realtimeState.connectionStatus;
}

class SyncManager extends ChangeNotifier {
  SyncManager({
    required SyncService syncService,
    required SyncQueueService syncQueueService,
    required RealtimeSyncService realtimeSyncService,
    required SyncConflictService syncConflictService,
  }) : _syncService = syncService,
       _syncQueueService = syncQueueService,
       _realtimeSyncService = realtimeSyncService,
       _syncConflictService = syncConflictService;

  final SyncService _syncService;
  final SyncQueueService _syncQueueService;
  final RealtimeSyncService _realtimeSyncService;
  final SyncConflictService _syncConflictService;
  final StreamController<SyncManagerState> _stateController =
      StreamController<SyncManagerState>.broadcast();

  StreamSubscription<SyncQueueState>? _queueSubscription;
  StreamSubscription<RealtimeSyncState>? _realtimeSubscription;
  StreamSubscription<void>? _dataChangedSubscription;
  StreamSubscription<int>? _conflictSubscription;
  SyncManagerState _state = const SyncManagerState();
  bool _started = false;
  bool _manualSyncInProgress = false;

  Stream<SyncManagerState> get stream => _stateController.stream;
  SyncManagerState get state => _state;

  Future<void> start({bool runInitialSync = true}) async {
    if (_started) {
      return;
    }

    final startupBlockReason = await _syncService.startupBlockReason();
    if (startupBlockReason != null && startupBlockReason.trim().isNotEmpty) {
      _setState(
        _state.copyWith(
          connectionStatus: SyncConnectionStatus.disconnected,
          isSyncing: false,
          currentErrors: <String>[startupBlockReason],
          lastSyncIssues: <String>[startupBlockReason],
        ),
      );
      return;
    }

    _started = true;
    _queueSubscription = _syncQueueService.stateStream.listen(
      _handleQueueState,
    );
    _realtimeSubscription = _realtimeSyncService.stateStream.listen(
      _handleRealtimeState,
    );
    _dataChangedSubscription = _realtimeSyncService.dataChangedStream.listen((
      _,
    ) {
      _setState(
        _state.copyWith(
          dataVersion: _state.dataVersion + 1,
          lastRealtimeEventAt: DateTime.now(),
        ),
      );
      unawaited(_syncConflictService.unresolvedConflictCount());
    });
    _conflictSubscription = _syncConflictService.unresolvedCountStream.listen((
      count,
    ) {
      _setState(_state.copyWith(unresolvedConflictCount: count));
    });

    await _syncQueueService.start();
    await _realtimeSyncService.start();
    await _syncConflictService.unresolvedConflictCount();
    _handleQueueState(_syncQueueService.state);
    _handleRealtimeState(_realtimeSyncService.state);
    _setState(
      _state.copyWith(
        unresolvedConflictCount: _syncConflictService.unresolvedCount,
      ),
    );

    if (runInitialSync && !manualCloudSyncOnly && allowCloudPull) {
      unawaited(syncNow(showAsBusy: false));
    }
  }

  Future<void> stop({String? reason}) async {
    _started = false;
    _manualSyncInProgress = false;
    await _queueSubscription?.cancel();
    await _realtimeSubscription?.cancel();
    await _dataChangedSubscription?.cancel();
    await _conflictSubscription?.cancel();
    _queueSubscription = null;
    _realtimeSubscription = null;
    _dataChangedSubscription = null;
    _conflictSubscription = null;
    await _syncQueueService.stop();
    await _realtimeSyncService.stop(reason: reason);
    final normalizedReason = reason?.trim();
    _setState(
      _state.copyWith(
        connectionStatus: SyncConnectionStatus.disconnected,
        isSyncing: false,
        currentErrors: normalizedReason == null || normalizedReason.isEmpty
            ? const <String>[]
            : <String>[normalizedReason],
        lastSyncIssues: normalizedReason == null || normalizedReason.isEmpty
            ? const <String>[]
            : <String>[normalizedReason],
      ),
    );
  }

  Future<SyncReport> syncNow({bool showAsBusy = true}) async {
    _manualSyncInProgress = showAsBusy;
    _setState(
      _state.copyWith(
        isSyncing:
            _manualSyncInProgress || _syncQueueService.state.isProcessing,
      ),
    );

    final report = await _syncService.syncNow();
    // Warnings are non-fatal and should not force the global badge into "Error".
    final syncIssues = <String>[
      if (report.errorMessage != null && report.errorMessage!.trim().isNotEmpty)
        report.errorMessage!.trim(),
    ];
    final errors = _combineErrors(
      queueError: _syncQueueService.state.lastError,
      realtimeError: _realtimeSyncService.state.lastError,
      syncIssues: syncIssues,
    );

    _manualSyncInProgress = false;

    _setState(
      _state.copyWith(
        isSyncing: _syncQueueService.state.isProcessing,
        pendingCount: report.pendingRecords,
        lastSyncIssues: syncIssues,
        currentErrors: errors,
      ),
    );
    await _syncConflictService.unresolvedConflictCount();
    return report;
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _realtimeSubscription?.cancel();
    _dataChangedSubscription?.cancel();
    _conflictSubscription?.cancel();
    if (!_stateController.isClosed) {
      unawaited(_stateController.close());
    }
    super.dispose();
  }

  void _handleQueueState(SyncQueueState queueState) {
    final realtimeState = _realtimeSyncService.state;
    final shouldClearStaleIssues = _shouldClearStaleSyncIssues(
      queueState: queueState,
      realtimeState: realtimeState,
    );
    final effectiveSyncIssues = shouldClearStaleIssues
        ? const <String>[]
        : _state.lastSyncIssues;

    _setState(
      _state.copyWith(
        pendingCount: queueState.pendingCount,
        isSyncing: _manualSyncInProgress || queueState.isProcessing,
        lastSyncIssues: effectiveSyncIssues,
        currentErrors: _combineErrors(
          queueError: queueState.lastError,
          realtimeError: realtimeState.lastError,
          syncIssues: effectiveSyncIssues,
        ),
      ),
    );
  }

  void _handleRealtimeState(RealtimeSyncState realtimeState) {
    final queueState = _syncQueueService.state;
    final shouldClearStaleIssues = _shouldClearStaleSyncIssues(
      queueState: queueState,
      realtimeState: realtimeState,
    );
    final effectiveSyncIssues = shouldClearStaleIssues
        ? const <String>[]
        : _state.lastSyncIssues;

    _setState(
      _state.copyWith(
        connectionStatus: resolveEffectiveSyncConnectionStatus(
          realtimeState: realtimeState,
          queueState: queueState,
        ),
        lastSyncIssues: effectiveSyncIssues,
        currentErrors: _combineErrors(
          queueError: queueState.lastError,
          realtimeError: realtimeState.lastError,
          syncIssues: effectiveSyncIssues,
        ),
        dataVersion: realtimeState.dataVersion > _state.dataVersion
            ? realtimeState.dataVersion
            : _state.dataVersion,
        lastRealtimeEventAt:
            realtimeState.lastDataChangedAt ?? _state.lastRealtimeEventAt,
      ),
    );
  }

  bool _shouldClearStaleSyncIssues({
    required SyncQueueState queueState,
    required RealtimeSyncState realtimeState,
  }) {
    if (_state.lastSyncIssues.isEmpty) {
      return false;
    }
    if (_manualSyncInProgress) {
      return false;
    }

    final queueError = queueState.lastError?.trim();
    final realtimeError = realtimeState.lastError?.trim();
    final hasActiveError =
        (queueError != null && queueError.isNotEmpty) ||
        (realtimeError != null && realtimeError.isNotEmpty);
    if (hasActiveError) {
      return false;
    }

    final isHealthy =
        realtimeState.connectionStatus == SyncConnectionStatus.connected &&
        !queueState.isProcessing &&
        queueState.pendingCount == 0;
    return isHealthy;
  }

  List<String> _combineErrors({
    String? queueError,
    String? realtimeError,
    List<String> syncIssues = const [],
  }) {
    return <String>{
      if (queueError != null && queueError.trim().isNotEmpty) queueError.trim(),
      if (realtimeError != null && realtimeError.trim().isNotEmpty)
        realtimeError.trim(),
      ...syncIssues
          .where((issue) => issue.trim().isNotEmpty)
          .map((issue) => issue.trim()),
    }.toList(growable: false);
  }

  void _setState(SyncManagerState nextState) {
    _state = nextState;
    if (!_stateController.isClosed) {
      _stateController.add(nextState);
    }
    notifyListeners();
  }
}
