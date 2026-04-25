import 'dart:async';
import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_flags.dart';
import '../models/sync/sync_connection_status.dart';
import 'sync/sync_config_repository.dart';
import 'sync/sync_logger.dart';
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
  Timer? _pollingTimer;
  Future<void> _eventQueue = Future<void>.value();
  final Map<String, _RecentRealtimeEvent> _recentEvents = {};
  final SyncLogger _syncLogger = SyncLogger.instance;
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
    if (manualCloudSyncOnly) {
      _disposeSocket();
      _stopPolling();
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
      return;
    }

    final settings = await _configRepository.loadSettings();
    if (!settings.isConfigured) {
      _stopPolling();
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
    _stopPolling();
    _emitState(
      RealtimeSyncState(
        connectionStatus: SyncConnectionStatus.connecting,
        dataVersion: _state.dataVersion,
        lastDataChangedAt: _state.lastDataChangedAt,
      ),
    );

    final realtimeBaseUrl = _resolveRealtimeBaseUrl(settings.normalizedBaseUrl);

    final socket = io.io(
      '$realtimeBaseUrl/realtime',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1 << 20)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setTimeout(10000)
          .setAuth({
            'token': settings.jwtToken,
            'deviceId': settings.deviceId,
            'clientType': 'desktop',
          })
          .build(),
    );

    socket.onConnect((_) {
      unawaited(
        _syncLogger.log(
          action: 'realtime-connect',
          entity: 'sync',
          result: 'ok',
          extra: {'transport': 'websocket'},
        ),
      );
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.connected,
          lastError: null,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
      _startPolling(settings.realtimePollingInterval);
      unawaited(_syncFromServer());
    });
    socket.onReconnect((_) {
      unawaited(
        _syncLogger.log(
          action: 'realtime-reconnect',
          entity: 'sync',
          result: 'ok',
          extra: {'transport': 'websocket'},
        ),
      );
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.connected,
          lastError: null,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
      _startPolling(settings.realtimePollingInterval);
      unawaited(_syncFromServer());
    });
    socket.onDisconnect((_) {
      _startPolling(settings.realtimePollingInterval);
      unawaited(
        _syncLogger.log(
          action: 'realtime-disconnect',
          entity: 'sync',
          result: 'pending',
          extra: {'transport': 'websocket'},
        ),
      );
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
          dataVersion: _state.dataVersion,
          lastDataChangedAt: _state.lastDataChangedAt,
        ),
      );
    });
    socket.onConnectError((error) {
      _startPolling(settings.realtimePollingInterval);
      unawaited(
        _syncLogger.log(
          action: 'realtime-connect-error',
          entity: 'sync',
          result: 'error',
          error: error.toString(),
        ),
      );
      _emitState(
        RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.error,
          lastError: error.toString(),
        ),
      );
    });
    socket.onError((error) {
      _startPolling(settings.realtimePollingInterval);
      unawaited(
        _syncLogger.log(
          action: 'realtime-error',
          entity: 'sync',
          result: 'error',
          error: error?.toString(),
        ),
      );
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

  String _resolveRealtimeBaseUrl(String normalizedBaseUrl) {
    final parsed = Uri.tryParse(normalizedBaseUrl.trim());
    if (parsed == null || parsed.host.trim().isEmpty) {
      return normalizedBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    }

    final segments = parsed.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
      segments.removeLast();
    }

    return parsed
        .replace(pathSegments: segments)
        .toString()
        .replaceAll(RegExp(r'/$'), '');
  }

  Future<int> pollNow() async {
    return _syncFromServer();
  }

  void dispose() {
    _stopPolling();
    _disposeSocket();
    if (!_stateController.isClosed) {
      unawaited(_stateController.close());
    }
    if (!_dataChangedController.isClosed) {
      unawaited(_dataChangedController.close());
    }
  }

  void _enqueueEvent(String eventName, dynamic payload) {
    // Never let an exception permanently break the event queue.
    // If a previous event failed, we still want to process future events.
    _eventQueue = _eventQueue
        .catchError((error, stackTrace) async {
          await _syncLogger.log(
            action: 'realtime-event-queue',
            entity: 'sync',
            result: 'error',
            error: error.toString(),
          );
        })
        .then((_) => _handleEvent(eventName, payload));
  }

  Future<int> _syncFromServer() async {
    if (_isApplyingRealtimeEvent) {
      return 0;
    }

    _isApplyingRealtimeEvent = true;
    try {
      final downloadedCount = await _syncService.downloadUpdates();
      await _syncLogger.log(
        action: 'realtime-download',
        entity: 'sync',
        result: downloadedCount > 0 ? 'ok' : 'idle',
        extra: {'downloadedRecords': downloadedCount},
      );
      if (downloadedCount > 0) {
        _notifyDataChanged();
        _onDataChanged?.call();
      }
      return downloadedCount;
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        await _syncLogger.log(
          action: 'realtime-download',
          entity: 'sync',
          result: 'idle',
          error: 'database_closed',
        );
        return 0;
      }
      await _syncLogger.log(
        action: 'realtime-download',
        entity: 'sync',
        result: 'error',
        error: error.toString(),
      );
      rethrow;
    } finally {
      _isApplyingRealtimeEvent = false;
    }
  }

  Future<void> _handleEvent(String eventName, dynamic payload) async {
    try {
      final deduplicationContext = _buildDeduplicationContext(
        eventName,
        payload,
      );
      if (_isDuplicateEvent(deduplicationContext)) {
        return;
      }

      final scopes = resolveAffectedScopes(eventName, payload);
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
    } catch (error) {
      if (_isDatabaseClosedError(error)) {
        await _syncLogger.log(
          action: 'realtime-event',
          entity: eventName,
          result: 'idle',
          error: 'database_closed',
        );
        return;
      }
      await _syncLogger.log(
        action: 'realtime-event',
        entity: eventName,
        result: 'error',
        error: error.toString(),
      );
      // Swallow to keep the queue alive; polling/manual sync will recover.
      return;
    }
  }

  bool _isDatabaseClosedError(Object error) {
    return error.toString().toLowerCase().contains('database_closed');
  }

  bool registerEventForDeduplication(String eventName, dynamic payload) {
    return !_isDuplicateEvent(_buildDeduplicationContext(eventName, payload));
  }

  void _startPolling(Duration interval) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) {
      unawaited(_pollServer(interval));
    });
  }

  Future<void> _pollServer(Duration interval) async {
    try {
      final downloadedCount = await _syncFromServer();
      await _syncLogger.log(
        action: 'realtime-poll',
        entity: 'sync',
        result: downloadedCount > 0 ? 'ok' : 'idle',
        extra: {
          'intervalSeconds': interval.inSeconds,
          'downloadedRecords': downloadedCount,
        },
      );
    } catch (error) {
      await _syncLogger.log(
        action: 'realtime-poll',
        entity: 'sync',
        result: 'error',
        error: error.toString(),
        extra: {'intervalSeconds': interval.inSeconds},
      );
    }
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  List<String> resolveAffectedScopes(String eventName, dynamic payload) {
    switch (eventName) {
      case 'sale.created':
        return const [
          'clients',
          'products',
          'sales',
          'installments',
          'payments',
        ];
      case 'payment.created':
        return const ['sales', 'installments', 'payments'];
      case 'entity.updated':
        final inferredScope = _inferScope(payload);
        if (inferredScope == null || !_syncService.hasScope(inferredScope)) {
          return const [];
        }
        switch (inferredScope) {
          case 'sales':
            return const [
              'clients',
              'products',
              'sales',
              'installments',
              'payments',
            ];
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

  _DeduplicationContext _buildDeduplicationContext(
    String eventName,
    dynamic payload,
  ) {
    final normalizedPayload = _normalizePayload(payload);
    final remoteJid = _firstString(normalizedPayload, const [
      'remoteJid',
      'remote_jid',
      'jid',
      'chatId',
      'chat_id',
    ]);
    final messageId = _firstString(normalizedPayload, const [
      'messageId',
      'message_id',
      'event_id',
      'record_sync_id',
      'sync_id',
      'id',
    ]);
    final timestamp = _firstString(normalizedPayload, const [
      'timestamp',
      'timestamp_ms',
      'updated_at',
      'created_at',
      'sentAt',
      'sent_at',
    ]);
    final pushName = _firstString(normalizedPayload, const [
      'pushName',
      'push_name',
      'senderName',
      'sender_name',
      'name',
    ]);
    final text = _firstString(normalizedPayload, const [
      'texto',
      'text',
      'body',
      'message',
      'content',
    ]);

    return _DeduplicationContext(
      key: [
        eventName,
        remoteJid ?? 'no-remoteJid',
        messageId ?? 'no-messageId',
        timestamp ?? 'no-timestamp',
      ].join('::'),
      contentSignature: _stableSerialize(normalizedPayload),
      messageId: messageId,
      remoteJid: remoteJid,
      timestamp: timestamp,
      pushName: pushName,
      text: text,
    );
  }

  bool _isDuplicateEvent(_DeduplicationContext context) {
    final now = DateTime.now();
    _recentEvents.removeWhere(
      (_, event) => now.difference(event.seenAt) > const Duration(minutes: 5),
    );

    final existing = _recentEvents[context.key];
    _logEventDiagnostics('Realtime event received', context);
    if (existing != null) {
      if (existing.contentSignature == context.contentSignature) {
        _logEventDiagnostics('Realtime duplicate ignored', context);
        return true;
      }
      _logEventDiagnostics(
        'Realtime duplicate key reused with different content',
        context,
      );
    }

    _recentEvents[context.key] = _RecentRealtimeEvent(
      seenAt: now,
      contentSignature: context.contentSignature,
    );
    return false;
  }

  Map<String, dynamic> _normalizePayload(dynamic payload) {
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{'value': payload};
  }

  String? _firstString(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) {
        continue;
      }
      final trimmed = value.toString().trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  String _stableSerialize(dynamic value) {
    return jsonEncode(_sortForSerialization(value));
  }

  dynamic _sortForSerialization(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      return <String, dynamic>{
        for (final key in sortedKeys) key: _sortForSerialization(value[key]),
      };
    }
    if (value is List) {
      return value.map(_sortForSerialization).toList();
    }
    return value;
  }

  void _logEventDiagnostics(String prefix, _DeduplicationContext context) {
    print(
      '$prefix: messageId=${context.messageId ?? '-'} '
      'remoteJid=${context.remoteJid ?? '-'} '
      'timestamp=${context.timestamp ?? '-'} '
      'pushName=${context.pushName ?? '-'} '
      'texto=${context.text ?? '-'}',
    );
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

class _DeduplicationContext {
  const _DeduplicationContext({
    required this.key,
    required this.contentSignature,
    required this.messageId,
    required this.remoteJid,
    required this.timestamp,
    required this.pushName,
    required this.text,
  });

  final String key;
  final String contentSignature;
  final String? messageId;
  final String? remoteJid;
  final String? timestamp;
  final String? pushName;
  final String? text;
}

class _RecentRealtimeEvent {
  const _RecentRealtimeEvent({
    required this.seenAt,
    required this.contentSignature,
  });

  final DateTime seenAt;
  final String contentSignature;
}
