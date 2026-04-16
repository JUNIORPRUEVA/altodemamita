import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/sync/sync_manager_state.dart';
import '../../models/sync/sync_report.dart';
import '../realtime_sync_service.dart';
import 'sync_conflict_service.dart';
import 'sync_queue_service.dart';
import 'sync_service.dart';

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

  Stream<SyncManagerState> get stream => _stateController.stream;
  SyncManagerState get state => _state;

  Future<void> start({bool runInitialSync = true}) async {
    if (_started) {
      return;
    }

    _started = true;
    _queueSubscription = _syncQueueService.stateStream.listen(_handleQueueState);
    _realtimeSubscription = _realtimeSyncService.stateStream.listen(
      _handleRealtimeState,
    );
    _dataChangedSubscription = _realtimeSyncService.dataChangedStream.listen((_) {
      _setState(
        _state.copyWith(
          dataVersion: _state.dataVersion + 1,
          lastRealtimeEventAt: DateTime.now(),
        ),
      );
      unawaited(_syncConflictService.unresolvedConflictCount());
    });
    _conflictSubscription = _syncConflictService.unresolvedCountStream.listen(
      (count) {
        _setState(_state.copyWith(unresolvedConflictCount: count));
      },
    );

    await _syncQueueService.start();
    await _realtimeSyncService.start();
    await _syncConflictService.unresolvedConflictCount();
    _handleQueueState(_syncQueueService.state);
    _handleRealtimeState(_realtimeSyncService.state);
    _setState(_state.copyWith(unresolvedConflictCount: _syncConflictService.unresolvedCount));

    if (runInitialSync) {
      unawaited(syncNow(showAsBusy: false));
    }
  }

  Future<SyncReport> syncNow({bool showAsBusy = true}) async {
    if (showAsBusy) {
      _setState(_state.copyWith(isSyncing: true));
    }

    final report = await _syncService.syncNow();
    final errors = _combineErrors(
      queueError: _syncQueueService.state.lastError,
      realtimeError: _realtimeSyncService.state.lastError,
      syncError: report.errorMessage,
    );

    _setState(
      _state.copyWith(
        isSyncing: false,
        pendingCount: report.pendingRecords,
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
    _setState(
      _state.copyWith(
        pendingCount: queueState.pendingCount,
        isSyncing: _state.isSyncing || queueState.isProcessing,
        currentErrors: _combineErrors(
          queueError: queueState.lastError,
          realtimeError: _realtimeSyncService.state.lastError,
        ),
      ),
    );
  }

  void _handleRealtimeState(RealtimeSyncState realtimeState) {
    _setState(
      _state.copyWith(
        connectionStatus: realtimeState.connectionStatus,
        currentErrors: _combineErrors(
          queueError: _syncQueueService.state.lastError,
          realtimeError: realtimeState.lastError,
        ),
        dataVersion: realtimeState.dataVersion > _state.dataVersion
            ? realtimeState.dataVersion
            : _state.dataVersion,
        lastRealtimeEventAt:
            realtimeState.lastDataChangedAt ?? _state.lastRealtimeEventAt,
      ),
    );
  }

  List<String> _combineErrors({
    String? queueError,
    String? realtimeError,
    String? syncError,
  }) {
    return <String>{
      if (queueError != null && queueError.trim().isNotEmpty) queueError.trim(),
      if (realtimeError != null && realtimeError.trim().isNotEmpty)
        realtimeError.trim(),
      if (syncError != null && syncError.trim().isNotEmpty) syncError.trim(),
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