import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

class FakeBackendState {
  bool initialized = false;
  bool offline = false;
  final Set<String> unreachableHosts = <String>{};
  bool rejectSyncDownloadUnauthorized = false;
  bool rejectSyncDownloadForDeviceUnauthorized = false;
  bool systemReadOnly = false;
  String companyName = '';
  String adminEmail = '';
  String adminPassword = '';
  String adminFullName = '';
  String authClientType = 'desktop';
  List<String> authRoles = const ['SUPER_ADMIN'];
  List<String> authPermissions = const [
    'sync.manage',
    'users.write',
    'users.read',
  ];
  Map<String, dynamic> lastSyncUploadPayload = const {};

  bool forceSyncUploadConflict = false;
  bool wrapUploadConflictInErrorEnvelope = true;
  Map<String, dynamic> syncUploadConflictPayload = const {
    'message': 'Conflicto de version detectado.',
    'scope': 'installments',
    'strategy': 'manual',
    'conflicts': [
      {
        'scope': 'installments',
        'record_sync_id': 'installment-1',
        'local_version': 1,
        'server_version': 2,
        'server_record': {'sync_id': 'installment-1', 'version': 2},
      },
    ],
    'records': [
      {'sync_id': 'installment-1', 'version': 2},
    ],
  };

  final Map<String, FakeAuthorizedDevice> authorizedDevices =
      <String, FakeAuthorizedDevice>{};

  void seedAuthorizedDevice({
    required String deviceId,
    String? deviceName,
    String? platform,
    String userId = 'remote-admin-1',
    bool isPrimary = false,
    bool canWrite = false,
    DateTime? revokedAt,
  }) {
    authorizedDevices[deviceId] = FakeAuthorizedDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? deviceId,
      platform: platform ?? 'windows',
      userId: userId,
      isPrimary: isPrimary,
      canWrite: canWrite,
      revokedAt: revokedAt,
      lastSeenAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  FakeAuthorizedDevice? device(String? deviceId) {
    if (deviceId == null || deviceId.trim().isEmpty) {
      return null;
    }
    return authorizedDevices[deviceId.trim()];
  }

  FakeAuthorizedDevice? activePrimaryDevice() {
    for (final device in authorizedDevices.values) {
      if (device.revokedAt == null && device.isPrimary && device.canWrite) {
        return device;
      }
    }
    return null;
  }

  bool canDeviceWrite(String? deviceId) {
    final device = this.device(deviceId);
    return device != null &&
        device.revokedAt == null &&
        device.isPrimary &&
        device.canWrite;
  }

  Map<String, dynamic> currentDevicePayload(String? deviceId) {
    final normalizedDeviceId = deviceId?.trim() ?? '';
    if (normalizedDeviceId.isEmpty) {
      return _buildDevicePayload(
        deviceId: '',
        canWrite: false,
        isPrimary: false,
        reason: 'missing_device_id',
      );
    }

    final device = authorizedDevices[normalizedDeviceId];
    if (device == null) {
      return _buildDevicePayload(
        deviceId: normalizedDeviceId,
        canWrite: false,
        isPrimary: false,
        reason: 'device_not_registered',
      );
    }

    if (device.revokedAt != null) {
      return _buildDevicePayload(
        deviceId: normalizedDeviceId,
        deviceName: device.deviceName,
        platform: device.platform,
        canWrite: false,
        isPrimary: false,
        revokedAt: device.revokedAt,
        reason: 'device_revoked',
      );
    }

    final canWrite = device.isPrimary && device.canWrite;
    return _buildDevicePayload(
      deviceId: normalizedDeviceId,
      deviceName: device.deviceName,
      platform: device.platform,
      canWrite: canWrite,
      isPrimary: device.isPrimary,
      reason: canWrite ? 'authorized' : 'device_not_primary',
    );
  }

  Map<String, dynamic> registerDevice({
    required String deviceId,
    String? deviceName,
    String? platform,
  }) {
    final now = DateTime.now();
    final existing = authorizedDevices[deviceId];
    if (existing != null) {
      final updated = existing.copyWith(
        deviceName: deviceName ?? existing.deviceName,
        platform: platform ?? existing.platform,
        lastSeenAt: now,
        updatedAt: now,
      );
      authorizedDevices[deviceId] = updated;
      return currentDevicePayload(deviceId);
    }

    final hasPrimary = activePrimaryDevice() != null;
    final created = FakeAuthorizedDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? deviceId,
      platform: platform ?? 'windows',
      userId: 'remote-admin-1',
      isPrimary: !hasPrimary,
      canWrite: !hasPrimary,
      lastSeenAt: now,
      createdAt: now,
      updatedAt: now,
    );
    authorizedDevices[deviceId] = created;
    return _buildDevicePayload(
      deviceId: deviceId,
      deviceName: created.deviceName,
      platform: created.platform,
      canWrite: created.canWrite,
      isPrimary: created.isPrimary,
      reason: hasPrimary ? 'registered_secondary' : 'auto_registered_primary',
    );
  }

  Map<String, dynamic> claimPrimary({
    required String deviceId,
    String? deviceName,
    String? platform,
  }) {
    final now = DateTime.now();
    for (final entry in authorizedDevices.entries.toList()) {
      final device = entry.value;
      if (device.revokedAt != null) {
        continue;
      }
      authorizedDevices[entry.key] = device.copyWith(
        isPrimary: false,
        canWrite: false,
        updatedAt: now,
      );
    }

    final existing = authorizedDevices[deviceId];
    final claimed =
        (existing ??
                FakeAuthorizedDevice(
                  deviceId: deviceId,
                  deviceName: deviceName ?? deviceId,
                  platform: platform ?? 'windows',
                  userId: 'remote-admin-1',
                  isPrimary: true,
                  canWrite: true,
                  lastSeenAt: now,
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              deviceName: deviceName ?? existing?.deviceName ?? deviceId,
              platform: platform ?? existing?.platform ?? 'windows',
              isPrimary: true,
              canWrite: true,
              revokedAt: null,
              lastSeenAt: now,
              updatedAt: now,
            );
    authorizedDevices[deviceId] = claimed;
    return _buildDevicePayload(
      deviceId: deviceId,
      deviceName: claimed.deviceName,
      platform: claimed.platform,
      canWrite: true,
      isPrimary: true,
      reason: 'authorized',
    );
  }

  Map<String, dynamic> revokeDevice(String deviceId) {
    final normalizedDeviceId = deviceId.trim();
    final existing = authorizedDevices[normalizedDeviceId];
    final now = DateTime.now();
    if (existing != null) {
      authorizedDevices[normalizedDeviceId] = existing.copyWith(
        isPrimary: false,
        canWrite: false,
        revokedAt: now,
        updatedAt: now,
      );
    }
    return currentDevicePayload(normalizedDeviceId);
  }

  Map<String, dynamic> _buildDevicePayload({
    required String deviceId,
    String? deviceName,
    String? platform,
    required bool isPrimary,
    required bool canWrite,
    required String reason,
    DateTime? revokedAt,
  }) {
    return {
      'userId': 'remote-admin-1',
      'clientType': authClientType,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'isPrimary': isPrimary,
      'canWrite': canWrite,
      'revokedAt': revokedAt?.toIso8601String(),
      'lastValidatedAt': DateTime.now().toIso8601String(),
      'reason': reason,
    };
  }
}

class FakeAuthorizedDevice {
  const FakeAuthorizedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.userId,
    required this.isPrimary,
    required this.canWrite,
    this.revokedAt,
    required this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String userId;
  final bool isPrimary;
  final bool canWrite;
  final DateTime? revokedAt;
  final DateTime lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  FakeAuthorizedDevice copyWith({
    String? deviceName,
    String? platform,
    bool? isPrimary,
    bool? canWrite,
    Object? revokedAt = _sentinel,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FakeAuthorizedDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      userId: userId,
      isPrimary: isPrimary ?? this.isPrimary,
      canWrite: canWrite ?? this.canWrite,
      revokedAt: revokedAt == _sentinel
          ? this.revokedAt
          : revokedAt as DateTime?,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _sentinel = Object();

class FakeBackendHttpClient implements HttpClient {
  FakeBackendHttpClient({required FakeBackendState state}) : _state = state;

  final FakeBackendState _state;
  Duration? _connectionTimeout;
  Duration? _idleTimeout;
  bool Function(X509Certificate, String, int)? _badCertificateCallback;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;

  @override
  Duration get idleTimeout => _idleTimeout ?? const Duration(seconds: 15);

  @override
  set idleTimeout(Duration value) => _idleTimeout = value;

  bool Function(X509Certificate, String, int)? get badCertificateCallback =>
      _badCertificateCallback;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? callback,
  ) => _badCertificateCallback = callback;

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

  _FakeHttpClientResponse _jsonResponse({
    required int status,
    required Object body,
  }) {
    return _FakeHttpClientResponse(
      statusCode: status,
      body: jsonEncode(body),
      contentType: ContentType.json,
    );
  }

  @override
  Future<HttpClientResponse> close() async {
    if (_state.offline || _state.unreachableHosts.contains(_uri.host)) {
      throw const SocketException('offline');
    }

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
            'readOnly': _state.systemReadOnly,
            'version': 'test',
          },
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/system/setup')) {
      if (_state.initialized) {
        return _jsonResponse(
          status: HttpStatus.badRequest,
          body: {
            'success': false,
            'message': 'El sistema central ya fue inicializado.',
          },
        );
      }

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

    if (_method == 'GET' && path.endsWith('/auth/me')) {
      final authHeader = _headers.value(HttpHeaders.authorizationHeader) ?? '';
      final hasValidToken = authHeader.trim() == 'Bearer jwt-test-token';
      if (!_state.initialized || !hasValidToken) {
        return _jsonResponse(
          status: HttpStatus.unauthorized,
          body: {'success': false, 'message': 'Unauthorized'},
        );
      }

      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': {
            'sub': 'remote-admin-1',
            'email': _state.adminEmail,
            'username': 'admin.general',
            'fullName': _state.adminFullName,
            'isActive': true,
            'type': _state.authClientType,
            'roles': _state.authRoles,
            'permissions': _state.authPermissions,
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
              'type':
                  payload['clientType']?.toString() ?? _state.authClientType,
              'roles': _state.authRoles,
              'permissions': _state.authPermissions,
            },
          },
        },
      );
    }

    if (_method == 'GET' && path.endsWith('/devices/current')) {
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': _state.currentDevicePayload(_headers.value('x-device-id')),
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/devices/register')) {
      final String deviceId =
          payload['device_id']?.toString().trim().isNotEmpty == true
          ? payload['device_id'].toString().trim()
          : _headers.value('x-device-id')?.trim() ?? '';
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': _state.registerDevice(
            deviceId: deviceId,
            deviceName: payload['device_name']?.toString(),
            platform: payload['platform']?.toString(),
          ),
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/devices/claim-primary')) {
      final String deviceId =
          payload['device_id']?.toString().trim().isNotEmpty == true
          ? payload['device_id'].toString().trim()
          : _headers.value('x-device-id')?.trim() ?? '';
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {
          'success': true,
          'data': _state.claimPrimary(
            deviceId: deviceId,
            deviceName: payload['device_name']?.toString(),
            platform: payload['platform']?.toString(),
          ),
        },
      );
    }

    if (_method == 'POST' && path.endsWith('/devices/revoke')) {
      final deviceId = payload['device_id']?.toString().trim() ?? '';
      return _jsonResponse(
        status: HttpStatus.ok,
        body: {'success': true, 'data': _state.revokeDevice(deviceId)},
      );
    }

    if (_method == 'POST' && path.endsWith('/sync/upload')) {
      _state.lastSyncUploadPayload = payload;

      final requestDeviceId =
          payload['device_id']?.toString().trim().isNotEmpty == true
          ? payload['device_id']?.toString().trim()
          : _headers.value('x-device-id')?.trim();
      if (!_state.canDeviceWrite(requestDeviceId)) {
        return _jsonResponse(
          status: HttpStatus.forbidden,
          body: {
            'success': false,
            'message': 'DEVICE_NOT_AUTHORIZED_FOR_WRITE',
          },
        );
      }

      if (_state.forceSyncUploadConflict) {
        final conflictPayload = _state.syncUploadConflictPayload;
        if (_state.wrapUploadConflictInErrorEnvelope) {
          return _jsonResponse(
            status: HttpStatus.conflict,
            body: {
              'success': false,
              'statusCode': HttpStatus.conflict,
              'message': 'Conflict',
              'error': conflictPayload,
            },
          );
        }
        return _jsonResponse(
          status: HttpStatus.conflict,
          body: conflictPayload,
        );
      }

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
      if (_state.rejectSyncDownloadUnauthorized) {
        return _jsonResponse(
          status: HttpStatus.unauthorized,
          body: {'success': false, 'message': 'Unauthorized'},
        );
      }

      if (_state.rejectSyncDownloadForDeviceUnauthorized) {
        return _jsonResponse(
          status: HttpStatus.forbidden,
          body: {
            'success': false,
            'message': 'DEVICE_NOT_AUTHORIZED_FOR_WRITE',
          },
        );
      }

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
  final Map<String, String> _values = <String, String>{};

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) => _contentType = value;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _values[name.toLowerCase()];

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
  FakeSyncConfigRepository({required SyncSettings settings})
    : _settings = settings;

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
