import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:sistema_solares_ui/core/config/app_config.dart';

class RealtimeController extends ChangeNotifier {
  final Set<String> _processedEvents = <String>{};
  io.Socket? _socket;
  bool _connected = false;
  int _refreshTick = 0;
  String? _lastEventName;
  DateTime? _lastEventTime;
  
  // Throttle: maximo 1 refresh cada 5 segundos para evitar temblor
  static const int _throttleMs = 5000;
  DateTime? _lastRefreshTime;
  Timer? _pendingRefreshTimer;

  bool get isConnected => _connected;
  int get refreshTick => _refreshTick;
  String? get lastEventName => _lastEventName;
  DateTime? get lastEventTime => _lastEventTime;

  Future<void> connect(String jwtToken) async {
    disconnect();

    _socket = io.io(
      AppConfig.realtimeUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': jwtToken})
          .enableForceNew()
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _connected = true;
        notifyListeners();
      })
      ..onDisconnect((_) {
        _connected = false;
        notifyListeners();
      })
      ..onConnectError((_) {
        _connected = false;
        notifyListeners();
      })
      ..onAny((event, data) {
        final eventId = _extractEventId(data);
        if (eventId != null && _processedEvents.contains(eventId)) {
          return;
        }
        if (eventId != null) {
          _processedEvents.add(eventId);
          if (_processedEvents.length > 300) {
            _processedEvents.remove(_processedEvents.first);
          }
        }

        _lastEventName = event;
        _lastEventTime = DateTime.now();
        
        // Throttle refreshes: maximo 1 cada 5 segundos
        // Esto evita que el dashboard tiemble por eventos frecuentes del socket
        if (event != 'realtime.connected' && event != 'pong') {
          _scheduleThrottledRefresh();
        }
        notifyListeners();
      })
      ..connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _processedEvents.clear();
    _pendingRefreshTimer?.cancel();
    _pendingRefreshTimer = null;
    notifyListeners();
  }

  void _scheduleThrottledRefresh() {
    final now = DateTime.now();
    final lastRefresh = _lastRefreshTime;
    
    // Si no hay ultimo refresh o ya paso el throttle interval
    if (lastRefresh == null || now.difference(lastRefresh).inMilliseconds >= _throttleMs) {
      _lastRefreshTime = now;
      _refreshTick += 1;
      _pendingRefreshTimer?.cancel();
      _pendingRefreshTimer = null;
      return;
    }
    
    // Si hay un timer pendiente, no crear otro
    if (_pendingRefreshTimer != null) {
      return;
    }
    
    // Programar refresh al final del throttle interval
    final remainingMs = _throttleMs - now.difference(lastRefresh).inMilliseconds;
    _pendingRefreshTimer = Timer(Duration(milliseconds: remainingMs), () {
      _lastRefreshTime = DateTime.now();
      _refreshTick += 1;
      _pendingRefreshTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    disconnect();
    _pendingRefreshTimer?.cancel();
    _pendingRefreshTimer = null;
    super.dispose();
  }

  String? _extractEventId(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['event_id']?.toString();
    }
    if (data is Map) {
      return data['event_id']?.toString();
    }
    return null;
  }
}

