import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/sync/sync_connection_status.dart';
import 'sync/sync_config_repository.dart';
import 'sync/sync_service.dart';

class RealtimeSyncService {
  RealtimeSyncService({
    required SyncService syncService,
    SyncConfigRepository? configRepository,
    VoidCallback? onDataChanged,
  }) : _syncService = syncService,
       _configRepository = configRepository ?? SyncConfigRepository(),
       _onDataChanged = onDataChanged;

  final SyncService _syncService;
  final SyncConfigRepository _configRepository;
  final VoidCallback? _onDataChanged;

  io.Socket? _socket;
  Future<void> _eventQueue = Future<void>.value();
  final Map<String, DateTime> _recentEvents = {};
  final StreamController<RealtimeSyncState> _stateController =
      StreamController<RealtimeSyncState>.broadcast();
  final StreamController<void> _dataChangedController =
      StreamController<void>.broadcast();
  bool _isApplyingRealtimeEvent = false;
  RealtimeSyncState _state = const RealtimeSyncState();

  Stream<RealtimeSyncState> get stateStream => _stateController.stream;
  Stream<void> get dataChangedStream => _dataChangedController.stream;
  RealtimeSyncState get state => _state;

  Future<void> start() async {
    final settings = await _configRepository.loadSettings();
    if (!settings.isConfigured) {
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
      return;
    }

    _disposeSocket();
    _emitState(
      RealtimeSyncState(
        connectionStatus: SyncConnectionStatus.connecting,
        dataVersion: _state.dataVersion,
        lastDataChangedAt: _state.lastDataChangedAt,
      ),
    );

    final socket = io.io(
      '${settings.normalizedBaseUrl}/realtime',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1 << 20)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setTimeout(10000)
          .setAuth({'token': settings.jwtToken, 'deviceId': settings.deviceId})
          .build(),
    );

    socket.onConnect((_) {
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.connected,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
      unawaited(_syncFromServer());
    });
    socket.onReconnect((_) {
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.connected,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
      unawaited(_syncFromServer());
    });
    socket.onDisconnect((_) {
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
    });
    socket.onConnectError((error) {
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.error,
          lastError: error.toString(),
        ),
      );
    });
    socket.onError((error) {
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.error,
          lastError: error?.toString(),
        ),
      );
    });
    socket.on('sale.created', (payload) {
      _enqueueEvent('sale.created', payload);
    });
    socket.on('payment.created', (payload) {
      _enqueueEvent('payment.created', payload);
    });
    socket.on('entity.updated', (payload) {
      _enqueueEvent('entity.updated', payload);
    });

    _socket = socket;
  }

  Future<int> pollNow() async {
    return _syncFromServer();
  }

  void dispose() {
    _disposeSocket();
    if (!_stateController.isClosed) {
      unawaited(_stateController.close());
    }
    if (!_dataChangedController.isClosed) {
      unawaited(_dataChangedController.close());
    }
  }

  void _enqueueEvent(String eventName, dynamic payload) {
    _eventQueue = _eventQueue.then((_) => _handleEvent(eventName, payload));
  }

  Future<int> _syncFromServer() async {
    if (_isApplyingRealtimeEvent) {
      return 0;
    }

    _isApplyingRealtimeEvent = true;
    try {
      final downloadedCount = await _syncService.downloadUpdates();
      if (downloadedCount > 0) {
        _notifyDataChanged();
        _onDataChanged?.call();
      }
      return downloadedCount;
    } finally {
      _isApplyingRealtimeEvent = false;
    }
  }

  Future<void> _handleEvent(String eventName, dynamic payload) async {
    final eventKey = _buildEventKey(eventName, payload);
    if (_isDuplicateEvent(eventKey)) {
      return;
    }

    final scopes = _resolveScopes(eventName, payload);
    if (scopes.isEmpty) {
      await _syncFromServer();
      return;
    }

    int totalUpdated = 0;
    for (final scope in scopes) {
      totalUpdated += await _syncService.downloadUpdatesForScopes([scope]);
    }

    if (totalUpdated > 0) {
      _notifyDataChanged();
      _onDataChanged?.call();
    }
  }

  List<String> _resolveScopes(String eventName, dynamic payload) {
    switch (eventName) {
      case 'sale.created':
        return const ['clients', 'products', 'sales', 'installments'];
      case 'payment.created':
        return const ['sales', 'installments', 'payments'];
      case 'entity.updated':
        final inferredScope = _inferScope(payload);
        if (inferredScope == null || !_syncService.hasScope(inferredScope)) {
          return const [];
        }
        switch (inferredScope) {
          case 'sales':
            return const ['clients', 'products', 'sales', 'installments'];
          case 'payments':
            return const ['sales', 'installments', 'payments'];
          case 'installments':
            return const ['sales', 'installments'];
          default:
            return [inferredScope];
        }
      default:
        return const [];
    }
  }

  String? _inferScope(dynamic payload) {
    if (payload is! Map) {
      return null;
    }
    final normalized = payload.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final candidates =
        [
              normalized['scope'],
              normalized['entity'],
              normalized['entityType'],
              normalized['table'],
            ]
            .map((value) => value?.toString().trim().toLowerCase())
            .whereType<String>();

    for (final candidate in candidates) {
      switch (candidate) {
        case 'client':
        case 'clients':
          return 'clients';
        case 'product':
        case 'products':
        case 'lot':
        case 'lots':
          return 'products';
        case 'sale':
        case 'sales':
          return 'sales';
        case 'installment':
        case 'installments':
        case 'quota':
        case 'quotas':
          return 'installments';
        case 'payment':
        case 'payments':
          return 'payments';
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _extractRecordsForScope(
    String scope,
    dynamic payload,
  ) {
    if (payload is Map) {
      final normalized = payload.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final explicitScope = _inferScope(normalized);
      final records = normalized['records'];
      if (records is List) {
        return records
            .whereType<Map>()
            .map((record) {
              return record.map(
                (key, value) => MapEntry(key.toString(), value),
              );
            })
            .toList(growable: false);
      }

      final record = normalized['record'] ?? normalized['data'];
      if (record is Map && (explicitScope == null || explicitScope == scope)) {
        return [record.map((key, value) => MapEntry(key.toString(), value))];
      }

      if ((explicitScope == null || explicitScope == scope) &&
          (normalized.containsKey('sync_id') || normalized.containsKey('id'))) {
        return [normalized];
      }
    }

    return const [];
  }

  DateTime? _extractCursor(dynamic payload) {
    if (payload is! Map) {
      return null;
    }
    final normalized = payload.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final value = normalized['server_time'] ?? normalized['updated_at'];
    return DateTime.tryParse(value?.toString() ?? '');
  }

  bool _canApplyInlineRecords(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return false;
    }

    return records.every((record) {
      final syncId =
          record['sync_id']?.toString().trim() ??
          record['record_sync_id']?.toString().trim() ??
          '';
      final updatedAt = record['updated_at']?.toString().trim() ?? '';
      return syncId.isNotEmpty && updatedAt.isNotEmpty;
    });
  }

  String _buildEventKey(String eventName, dynamic payload) {
    final buffer = StringBuffer(eventName);
    if (payload is Map) {
      final normalized = payload.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final eventId =
          normalized['event_id'] ??
          normalized['record_sync_id'] ??
          normalized['sync_id'] ??
          normalized['id'] ??
          normalized['updated_at'];
      buffer.write('::${eventId ?? payload.hashCode}');
    } else {
      buffer.write('::${payload.hashCode}');
    }
    return buffer.toString();
  }

  bool _isDuplicateEvent(String eventKey) {
    final now = DateTime.now();
    _recentEvents.removeWhere(
      (_, timestamp) => now.difference(timestamp) > const Duration(minutes: 2),
    );
    if (_recentEvents.containsKey(eventKey)) {
      return true;
    }
    _recentEvents[eventKey] = now;
    return false;
  }

  void _disposeSocket() {
    final socket = _socket;
    _socket = null;
    socket?.dispose();
    socket?.disconnect();
  }

  void _notifyDataChanged() {
    final nextState = RealtimeSyncState(
      connectionStatus: _state.connectionStatus,
      lastError: _state.lastError,
      dataVersion: _state.dataVersion + 1,
      lastDataChangedAt: DateTime.now(),
    );
    _emitState(nextState);
    if (!_dataChangedController.isClosed) {
      _dataChangedController.add(null);
    }
  }

  void _emitState(RealtimeSyncState nextState) {
    _state = nextState;
    if (!_stateController.isClosed) {
      _stateController.add(nextState);
    }
  }
}

typedef VoidCallback = void Function();

class RealtimeSyncState {
  const RealtimeSyncState({
    this.connectionStatus = SyncConnectionStatus.disconnected,
    this.lastError,
    this.dataVersion = 0,
    this.lastDataChangedAt,
  });

  final SyncConnectionStatus connectionStatus;
  final String? lastError;
  final int dataVersion;
  final DateTime? lastDataChangedAt;
}
