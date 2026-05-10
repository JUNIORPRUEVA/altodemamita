import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../../core/config/backend_config.dart';
import '../../core/network/backend_http_client.dart';
import '../../core/system/system_config_service.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_settings.dart';
import 'sync_config_repository.dart';

class SyncConflictItem {
  const SyncConflictItem({
    required this.scope,
    required this.recordSyncId,
    required this.localVersion,
    required this.serverVersion,
    this.localRecord,
    this.serverRecord,
    this.message,
  });

  final String scope;
  final String recordSyncId;
  final int? localVersion;
  final int? serverVersion;
  final Map<String, dynamic>? localRecord;
  final Map<String, dynamic>? serverRecord;
  final String? message;

  factory SyncConflictItem.fromMap(Map<String, dynamic> map) {
    return SyncConflictItem(
      scope: map['scope']?.toString() ?? '',
      recordSyncId:
          map['record_sync_id']?.toString() ?? map['sync_id']?.toString() ?? '',
      localVersion: SyncApiClient._readInt(
        map['local_version'] ?? map['client_version'],
      ),
      serverVersion: SyncApiClient._readInt(
        map['server_version'] ?? map['version'],
      ),
      localRecord: SyncApiClient._readRecord(map['local_record']),
      serverRecord: SyncApiClient._readRecord(
        map['server_record'] ?? map['record'],
      ),
      message: map['message']?.toString(),
    );
  }
}

class SyncConflictException implements Exception {
  const SyncConflictException({
    required this.message,
    required this.scope,
    required this.strategy,
    required this.conflicts,
    required this.serverUri,
    this.returnedRecords = const [],
    this.serverTime,
  });

  final String message;
  final String scope;
  final SyncConflictStrategy strategy;
  final List<SyncConflictItem> conflicts;
  final List<Map<String, dynamic>> returnedRecords;
  final DateTime? serverTime;
  final Uri serverUri;

  @override
  String toString() => message;
}

class SyncUploadResponse {
  const SyncUploadResponse({
    required this.returnedRecordsByScope,
    this.serverTime,
  });

  final Map<String, List<Map<String, dynamic>>> returnedRecordsByScope;
  final DateTime? serverTime;

  List<Map<String, dynamic>> recordsForScope(String scope) {
    return returnedRecordsByScope[scope] ?? const [];
  }
}

class SyncDownloadResponse {
  const SyncDownloadResponse({
    required this.recordsByScope,
    this.serverTime,
    this.scopeCursors = const <String, DateTime?>{},
  });

  final Map<String, List<Map<String, dynamic>>> recordsByScope;
  final DateTime? serverTime;
  final Map<String, DateTime?> scopeCursors;

  List<Map<String, dynamic>> recordsForScope(String scope) {
    return recordsByScope[scope] ?? const [];
  }

  bool supportsScope(String scope) => recordsByScope.containsKey(scope);

  DateTime? cursorForScope(String scope) => scopeCursors[scope];
}

class SyncApiClient {
  static const List<String> _scopes = [
    'users',
    'roles',
    'user_roles',
    'role_permissions',
    'permissions',
    'clients',
    'products',
    'sellers',
    'sales',
    'installments',
    'payments',
    'company_profiles',
  ];

  SyncApiClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? createBackendHttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
    _httpClient.idleTimeout = const Duration(seconds: 15);
  }

  final HttpClient _httpClient;

  void _log(String message) {
    developer.log(message, name: 'SistemaSolares.SyncApi');
    // ignore: avoid_print
    print(message);
  }

  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final normalizedRecords = _normalizeRecordsPayload(recordsByScope);
    if (normalizedRecords.isEmpty) {
      return SyncUploadResponse(
        returnedRecordsByScope: _readRecordsByScope(const <String, Object?>{}),
      );
    }

    final uri = Uri.parse('${settings.normalizedBaseUrl}/sync/upload');
    _log(
      '[sync-upload] START '
      'url=$uri '
      'deviceId=${settings.deviceId.trim()} '
      'jwtPresent=${settings.jwtToken.trim().isNotEmpty} '
      'scopeCounts=${_scopeCountsSummary(normalizedRecords)}',
    );
    final payload = <String, Object?>{
      'device_id': settings.deviceId,
      'records': normalizedRecords,
    };
    final body = await _sendJsonRequest(
      method: 'POST',
      uri: uri,
      jwtToken: settings.jwtToken,
      deviceId: settings.deviceId,
      payload: payload,
    );

    return SyncUploadResponse(
      returnedRecordsByScope: _readRecordsByScope(body['records']),
      serverTime: _readDate(body['server_time']),
    );
  }

  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    final queryParameters = <String, String>{
      'device_id': settings.deviceId,
      if (updatedSince != null)
        'updatedSince': updatedSince.toUtc().toIso8601String(),
      if (updatedSinceByScope != null && updatedSinceByScope.isNotEmpty)
        'scope_cursors': jsonEncode({
          for (final entry in updatedSinceByScope.entries)
            if (entry.value != null)
              entry.key: entry.value!.toUtc().toIso8601String(),
        }),
    };
    final uri = Uri.parse(
      '${settings.normalizedBaseUrl}/sync/download',
    ).replace(queryParameters: queryParameters);
    final body = await _sendJsonRequest(
      method: 'GET',
      uri: uri,
      jwtToken: settings.jwtToken,
      deviceId: settings.deviceId,
    );

    return SyncDownloadResponse(
      recordsByScope: _readRecordsByScope(body['records']),
      serverTime: _readDate(body['server_time']),
      scopeCursors: _readScopeCursors(body['scope_cursors']),
    );
  }

  Future<Map<String, int>> previewManualRestore({
    required SyncSettings settings,
  }) async {
    final uri = Uri.parse('${settings.normalizedBaseUrl}/sync/restore/preview');
    final body = await _sendJsonRequest(
      method: 'POST',
      uri: uri,
      jwtToken: settings.jwtToken,
      deviceId: settings.deviceId,
      payload: <String, Object?>{'device_id': settings.deviceId},
    );
    final rawCounts = body['counts'];
    if (rawCounts is! Map) {
      return const <String, int>{};
    }

    return {
      for (final entry in rawCounts.entries)
        entry.key.toString(): _readInt(entry.value) ?? 0,
    };
  }

  Future<SyncDownloadResponse> downloadManualRestore({
    required SyncSettings settings,
    required String adminPassword,
    required String confirmationText,
  }) async {
    final uri = Uri.parse(
      '${settings.normalizedBaseUrl}/sync/restore/download',
    );
    final body = await _sendJsonRequest(
      method: 'POST',
      uri: uri,
      jwtToken: settings.jwtToken,
      deviceId: settings.deviceId,
      payload: <String, Object?>{
        'device_id': settings.deviceId,
        'admin_password': adminPassword,
        'confirmation_text': confirmationText,
      },
    );

    return SyncDownloadResponse(
      recordsByScope: _readRecordsByScope(body['records']),
      serverTime: _readDate(body['server_time']),
      scopeCursors: const <String, DateTime?>{},
    );
  }

  Future<Map<String, dynamic>> _sendJsonRequest({
    required String method,
    required Uri uri,
    required String jwtToken,
    required String deviceId,
    Map<String, Object?>? payload,
    bool isRetry = false,
  }) async {
    final normalizedToken = jwtToken.trim();
    if (normalizedToken.isEmpty) {
      throw HttpException(
        'No hay una sesion online activa para sincronizar. '
        'Inicia sesion en linea para generar el token y vuelve a intentar.',
        uri: uri,
      );
    }

    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      throw HttpException(
        'Esta PC no esta autorizada (falta x-device-id local).',
        uri: uri,
      );
    }
    _log(
      'REQUEST -> ${method.toUpperCase()} $uri '
      '[device_id=$normalizedDeviceId, has_jwt=true]',
    );

    final HttpClientRequest request;
    try {
      request = await _openRequest(method, uri);
    } catch (error) {
      _log('ERROR -> opening request ${method.toUpperCase()} $uri : $error');
      rethrow;
    }
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $normalizedToken',
    );
    request.headers.set('x-device-id', normalizedDeviceId);

    if (payload != null) {
      request.write(jsonEncode(payload));
    }

    final HttpClientResponse response;
    String responseBody = '';
    try {
      response = await request.close();
      _log('RESPONSE -> ${response.statusCode} $uri');
      if (uri.path.toLowerCase().contains('/sync/download')) {
        _log('[sync-download] STATUS ${response.statusCode}');
      }
      responseBody = await utf8.decoder.bind(response).join();
      if (uri.path.toLowerCase().contains('/sync/upload')) {
        _log(
          '[sync-upload] STATUS ${response.statusCode} '
          'body=${_responsePreview(responseBody)}',
        );
      }
    } catch (error) {
      _log('ERROR -> request failed ${method.toUpperCase()} $uri : $error');
      if (uri.path.toLowerCase().contains('/sync/upload')) {
        _log('[sync-upload] ERROR request_failed message=$error');
      }
      rethrow;
    }

    final trimmed = responseBody.trimLeft();
    final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    if (!looksLikeJson) {
      throw HttpException(serverConnectionErrorMessage, uri: uri);
    }

    Map<String, dynamic> decodedBody;
    try {
      decodedBody = _unwrapErrorEnvelope(
        _unwrapResponseEnvelope(_decodeJsonObject(responseBody)),
      );
    } on FormatException {
      throw HttpException(serverConnectionErrorMessage, uri: uri);
    }
    if (response.statusCode == 409) {
      throw SyncConflictException(
        message:
            decodedBody['message']?.toString() ??
            'La API reporto un conflicto de version.',
        scope: decodedBody['scope']?.toString() ?? '',
        strategy: SyncConflictStrategy.fromStorage(
          decodedBody['strategy'] ?? decodedBody['conflict_strategy'],
        ),
        conflicts: _readConflictList(decodedBody['conflicts']),
        returnedRecords: _readRecordList(decodedBody['records']),
        serverTime: _readDate(decodedBody['server_time']),
        serverUri: uri,
      );
    }
    if (response.statusCode == HttpStatus.forbidden &&
        decodedBody['message']?.toString() == 'READ_ONLY_MODE') {
      throw const ReadOnlyModeException();
    }

    if (response.statusCode == HttpStatus.unauthorized) {
      if (!isRetry) {
        final refreshedToken = await _tryRefreshJwtToken(
          baseUrl: uri.origin,
          jwtToken: normalizedToken,
        );
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          return _sendJsonRequest(
            method: method,
            uri: uri,
            jwtToken: refreshedToken,
            deviceId: normalizedDeviceId,
            payload: payload,
            isRetry: true,
          );
        }
      }

      final message = decodedBody['message']?.toString().trim();
      throw HttpException(
        'El backend rechazo la sesion (401). '
        '${message == null || message.isEmpty ? 'Inicia sesion en linea nuevamente.' : message}',
        uri: uri,
      );
    }

    if (response.statusCode == HttpStatus.forbidden) {
      final message = decodedBody['message']?.toString().trim() ?? '';
      if (message == 'DEVICE_NOT_AUTHORIZED' ||
          message == 'DEVICE_NOT_AUTHORIZED_FOR_WRITE') {
        throw HttpException('DEVICE_NOT_AUTHORIZED', uri: uri);
      }
      if (message.contains('No tiene permisos suficientes')) {
        throw HttpException(
          'Tu usuario no tiene permisos para sincronizar (falta "sync.manage"). '
          'Asigna un rol con ese permiso (por ejemplo SUPER_ADMIN) y vuelve a intentar.',
          uri: uri,
        );
      }
      if (message.contains('no esta disponible para clientes panel')) {
        throw HttpException(
          'Estas autenticado como cliente PANEL y la sincronizacion operativa esta bloqueada. '
          'Inicia sesion como Desktop (en la app de escritorio) y vuelve a intentar.',
          uri: uri,
        );
      }
      if (message.isNotEmpty) {
        throw HttpException(message, uri: uri);
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(serverConnectionErrorMessage, uri: uri);
    }

    return decodedBody;
  }

  Future<String?> _tryRefreshJwtToken({
    required String baseUrl,
    required String jwtToken,
  }) async {
    final token = jwtToken.trim();
    if (token.isEmpty) {
      return null;
    }

    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final refreshUri = Uri.parse('$normalizedBaseUrl/auth/refresh');
    try {
      final request = await _httpClient.postUrl(refreshUri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      request.write(jsonEncode({'token': token, 'clientType': 'desktop'}));

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = _decodeJsonObject(responseBody);
      final unwrapped = _unwrapResponseEnvelope(decoded);
      final newToken = unwrapped['accessToken']?.toString().trim() ?? '';
      if (newToken.isEmpty) {
        return null;
      }

      await SyncConfigRepository().saveJwtToken(newToken);
      _log(
        '[sync-auth] JWT refresh exitoso tras 401, se reintentara la solicitud.',
      );
      return newToken;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _unwrapErrorEnvelope(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      return error;
    }
    if (error is Map) {
      return error.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Map<String, dynamic> _unwrapResponseEnvelope(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Future<HttpClientRequest> _openRequest(String method, Uri uri) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _httpClient.getUrl(uri);
      case 'POST':
        return _httpClient.postUrl(uri);
      default:
        throw UnsupportedError('Metodo HTTP no soportado: $method');
    }
  }

  List<Map<String, dynamic>> _readRecordList(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) {
          return item.map((key, data) => MapEntry(key.toString(), data));
        })
        .toList(growable: false);
  }

  Map<String, List<Map<String, dynamic>>> _readRecordsByScope(Object? value) {
    if (value is! Map) {
      return const <String, List<Map<String, dynamic>>>{};
    }

    final normalized = <String, List<Map<String, dynamic>>>{};

    for (final scope in _scopes) {
      if (!value.containsKey(scope)) {
        continue;
      }
      normalized[scope] = _readRecordList(value[scope]);
    }
    return normalized;
  }

  Map<String, DateTime?> _readScopeCursors(Object? value) {
    if (value is! Map) {
      return const <String, DateTime?>{};
    }

    final normalized = <String, DateTime?>{};
    for (final scope in _scopes) {
      if (!value.containsKey(scope)) {
        continue;
      }
      normalized[scope] = _readDate(value[scope]);
    }
    return normalized;
  }

  Map<String, Object?> _normalizeRecordsPayload(
    Map<String, List<Map<String, Object?>>> recordsByScope,
  ) {
    return {
      for (final scope in _scopes)
        if ((recordsByScope[scope] ?? const <Map<String, Object?>>[])
            .isNotEmpty)
          scope: recordsByScope[scope] ?? const <Map<String, Object?>>[],
    };
  }

  String _scopeCountsSummary(Map<String, Object?> recordsPayload) {
    if (recordsPayload.isEmpty) {
      return '{}';
    }

    final parts = <String>[];
    for (final entry in recordsPayload.entries) {
      final value = entry.value;
      final count = value is List ? value.length : 0;
      parts.add('${entry.key}:$count');
    }
    return '{${parts.join(',')}}';
  }

  String _responsePreview(String body) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '<empty>';
    }
    if (normalized.length <= 300) {
      return normalized;
    }
    return '${normalized.substring(0, 300)}...';
  }

  List<SyncConflictItem> _readConflictList(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) {
          return SyncConflictItem.fromMap(
            item.map((key, data) => MapEntry(key.toString(), data)),
          );
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _decodeJsonObject(String responseBody) {
    if (responseBody.trim().isEmpty) {
      return const {};
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'La API de sincronizacion no devolvio un objeto JSON valido.',
      );
    }
    return decoded;
  }

  DateTime? _readDate(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic>? _readRecord(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, data) => MapEntry(key.toString(), data));
  }
}
