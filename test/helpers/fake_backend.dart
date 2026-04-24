import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

class FakeBackendState {
  bool initialized = false;
  String companyName = '';
  String adminEmail = '';
  String adminPassword = '';
  String adminFullName = '';
  Map<String, dynamic> lastSyncUploadPayload = const {};
}

class FakeBackendHttpClient implements HttpClient {
  FakeBackendHttpClient({required FakeBackendState state}) : _state = state;

  final FakeBackendState _state;
  Duration? _connectionTimeout;
  Duration? _idleTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;

  @override
  Duration get idleTimeout => _idleTimeout ?? const Duration(seconds: 15);

  @override
  set idleTimeout(Duration value) => _idleTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(method: 'GET', uri: url, state: _state);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _FakeHttpClientRequest(method: 'POST', uri: url, state: _state);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({
    required String method,
    required Uri uri,
    required FakeBackendState state,
  }) : _method = method,
       _uri = uri,
       _state = state;

  final String _method;
  final Uri _uri;
  final FakeBackendState _state;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();
  final StringBuffer _buffer = StringBuffer();

  @override
  HttpHeaders get headers => _headers;

  @override
  void write(Object? obj) {
    _buffer.write(obj);
  }

  Map<String, dynamic> _decodeBody() {
    final raw = _buffer.toString().trim();
    if (raw.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  _FakeHttpClientResponse _jsonResponse({required int status, required Object body}) {
    return _FakeHttpClientResponse(
      statusCode: status,
      body: jsonEncode(body),
      contentType: ContentType.json,
    );
  }

  @override
  Future<HttpClientResponse> close() async {
    final path = _uri.path;
    final payload = _decodeBody();

    if (_method == 'GET' && path.endsWith('/system/status')) {
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {'initialized': _state.initialized},
        },
      );
    }

    if (_method == 'GET' && path.endsWith('/system/config')) {
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {
            'initialized': _state.initialized,
            'readOnly': false,
            'version': 'test',
          },
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/system/setup')) {
      final company = payload['company'] as Map<String, dynamic>? ?? const {};
      final admin = payload['admin'] as Map<String, dynamic>? ?? const {};
      _state.initialized = true;
      _state.companyName = company['name']?.toString() ?? '';
      _state.adminEmail = admin['email']?.toString() ?? '';
      _state.adminPassword = admin['password']?.toString() ?? '';
      _state.adminFullName = admin['fullName']?.toString() ?? '';

      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {
            'initialized': true,
            'company': {'name': _state.companyName},
          },
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/auth/login')) {
      final identifier =
          payload['identifier']?.toString().trim().toLowerCase() ?? '';
      final password = payload['password']?.toString() ?? '';

      if (!_state.initialized ||
          identifier != _state.adminEmail.toLowerCase() ||
          password != _state.adminPassword) {
        return _jsonResponse(
          status: HttpStatus.unauthorized,
          body: {'success': false, 'message': 'Credenciales inválidas.'},
        );
      }

      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {
            'accessToken': 'jwt-test-token',
            'user': {
              'sub': 'remote-admin-1',
              'email': _state.adminEmail,
              'username': 'admin.general',
              'fullName': _state.adminFullName,
              'isActive': true,
              'roles': ['SUPER_ADMIN'],
              'permissions': ['sync.manage', 'users.write', 'users.read'],
            },
          },
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/sync/upload')) {
      _state.lastSyncUploadPayload = payload;
      final records = payload['records'] is Map<String, dynamic>
          ? payload['records'] as Map<String, dynamic>
          : payload['records'] is Map
          ? (payload['records'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, dynamic>{};
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {
            'server_time': DateTime.now().toIso8601String(),
            'records': records,
          },
        },
      );
    }

    if (_method == 'GET' && path.endsWith('/sync/download')) {
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {
            'server_time': DateTime.now().toIso8601String(),
            'records': const <String, dynamic>{
              'users': <Map<String, dynamic>>[],
              'clients': <Map<String, dynamic>>[],
              'products': <Map<String, dynamic>>[],
              'sellers': <Map<String, dynamic>>[],
              'sales': <Map<String, dynamic>>[],
              'installments': <Map<String, dynamic>>[],
              'payments': <Map<String, dynamic>>[],
            },
          },
        },
      );
    }

    return _jsonResponse(
      status: HttpStatus.notFound,
      body: {'success': false, 'message': 'Not found'},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({
    required int statusCode,
    required String body,
    required ContentType contentType,
  }) : _statusCode = statusCode,
       _bodyBytes = utf8.encode(body),
       _headers = _FakeHttpResponseHeaders(contentType);

  final int _statusCode;
  final List<int> _bodyBytes;
  final HttpHeaders _headers;

  @override
  int get statusCode => _statusCode;

  @override
  HttpHeaders get headers => _headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bodyBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) => _contentType = value;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    // No-op for tests.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponseHeaders implements HttpHeaders {
  _FakeHttpResponseHeaders(this._contentType);

  final ContentType _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSyncConfigRepository extends SyncConfigRepository {
  FakeSyncConfigRepository({required SyncSettings settings}) : _settings = settings;

  SyncSettings _settings;
  String savedJwtToken = '';

  @override
  Future<SyncSettings> loadSettings() async => _settings;

  @override
  Future<void> saveJwtToken(String jwtToken) async {
    savedJwtToken = jwtToken;
    _settings = SyncSettings(
      baseUrl: _settings.baseUrl,
      jwtToken: jwtToken,
      queueRetryInterval: _settings.queueRetryInterval,
      realtimePollingInterval: _settings.realtimePollingInterval,
      conflictStrategy: _settings.conflictStrategy,
      deviceId: _settings.deviceId,
    );
  }

  @override
  Future<void> clearJwtToken() async {
    savedJwtToken = '';
    _settings = SyncSettings(
      baseUrl: _settings.baseUrl,
      jwtToken: '',
      queueRetryInterval: _settings.queueRetryInterval,
      realtimePollingInterval: _settings.realtimePollingInterval,
      conflictStrategy: _settings.conflictStrategy,
      deviceId: _settings.deviceId,
    );
  }
  
  @override
  Future<void> saveBaseUrl(String baseUrl) async {
    _settings = SyncSettings(
      baseUrl: baseUrl.trim(),
      jwtToken: _settings.jwtToken,
      queueRetryInterval: _settings.queueRetryInterval,
      realtimePollingInterval: _settings.realtimePollingInterval,
      conflictStrategy: _settings.conflictStrategy,
      deviceId: _settings.deviceId,
    );
  }
}
SyncSettings buildFakeSettings() {
  return SyncSettings(
    baseUrl: 'http://127.0.0.1:9999/api',
    jwtToken: '',
    queueRetryInterval: const Duration(seconds: 10),
    realtimePollingInterval: const Duration(seconds: 5),
    conflictStrategy: SyncConflictStrategy.manual,
    deviceId: 'test-device',
  );
}
