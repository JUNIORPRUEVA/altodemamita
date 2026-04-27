import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sistema_solares_ui/core/config/app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const List<String> _blockedPanelWritePaths = <String>[
    '/sales',
    '/payments',
    '/installments',
    '/cash',
  ];

  final http.Client _client;
  String? _jwtToken;
  Future<bool> Function()? _unauthorizedHandler;
  Future<void> Function()? _ensureValidTokenHandler;

  void setJwtToken(String? token) {
    _jwtToken = token;
  }

  void setUnauthorizedHandler(Future<void> Function()? handler) {
    // Deprecated: kept for backward compatibility.
    if (handler == null) {
      _unauthorizedHandler = null;
      return;
    }
    _unauthorizedHandler = () async {
      await handler();
      return false;
    };
  }

  void setUnauthorizedHandlerV2(Future<bool> Function()? handler) {
    _unauthorizedHandler = handler;
  }

  void setEnsureValidTokenHandler(Future<void> Function()? handler) {
    _ensureValidTokenHandler = handler;
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    bool authorized = true,
  }) {
    return _request(
      'GET',
      path,
      queryParameters: queryParameters,
      authorized: authorized,
    );
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authorized = true,
  }) {
    return _request(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      authorized: authorized,
    );
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authorized = true,
  }) {
    return _request(
      'PATCH',
      path,
      body: body,
      queryParameters: queryParameters,
      authorized: authorized,
    );
  }

  Future<dynamic> delete(
    String path, {
    Map<String, String>? queryParameters,
    bool authorized = true,
  }) {
    return _request(
      'DELETE',
      path,
      queryParameters: queryParameters,
      authorized: authorized,
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authorized = true,
    bool isRetry = false,
  }) async {
    if (authorized) {
      await _ensureValidTokenHandler?.call();
    }

    final cleanedQuery = <String, String>{
      for (final entry in (queryParameters ?? const <String, String>{}).entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}$path',
    ).replace(queryParameters: cleanedQuery.isEmpty ? null : cleanedQuery);

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (authorized && _jwtToken?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    _assertPanelOperationAllowed(method, uri, headers: headers, body: body);

    _debugRequest(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      authorized: authorized,
    );

    late http.Response response;
    final encodedBody = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          response = await _client
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        default:
          throw ApiException('Metodo HTTP no soportado: $method');
      }
    } on TimeoutException {
      throw ApiException(
        'El servidor no respondio a tiempo. Verifica tu conexion a internet.',
      );
    } catch (error) {
      _debugTransportError(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        error: error,
      );
      throw ApiException('No se pudo completar la solicitud HTTP: $error');
    }

    final decoded = _decodeResponseBody(response.body);
    _debugResponse(
      method: method,
      uri: uri,
      statusCode: response.statusCode,
      decoded: decoded,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _unwrapEnvelope(decoded);
    }

    if (response.statusCode == 401 && authorized && !isRetry) {
      final refreshed = await _unauthorizedHandler?.call();
      if (refreshed == true && _jwtToken?.isNotEmpty == true) {
        return _request(
          method,
          path,
          body: body,
          queryParameters: queryParameters,
          authorized: authorized,
          isRetry: true,
        );
      }
    }

    final extractedMessage = _extractMessage(decoded);
    _debugApiError(
      method: method,
      uri: uri,
      statusCode: response.statusCode,
      extractedMessage: extractedMessage,
      decoded: decoded,
    );

    if (extractedMessage == 'READ_ONLY_MODE') {
      throw ApiException(
        'Sistema en modo solo lectura',
        statusCode: response.statusCode,
      );
    }

    throw ApiException(
      extractedMessage ??
          'La solicitud fallo con estado ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  void _assertPanelOperationAllowed(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
  }) {
    final normalizedMethod = method.trim().toUpperCase();
    if (normalizedMethod == 'GET') {
      return;
    }

    final normalizedPath = uri.path.trim().toLowerCase();
    for (final blockedPath in _blockedPanelWritePaths) {
      if (normalizedPath.contains(blockedPath)) {
        _debugBlockedWrite(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          blockedPath: blockedPath,
        );
        throw ApiException('Esta accion no esta disponible en el panel web');
      }
    }
  }

  dynamic _decodeResponseBody(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return rawBody;
    }
  }

  dynamic _unwrapEnvelope(dynamic decoded) {
    if (decoded is Map<String, dynamic> && decoded.containsKey('success')) {
      return decoded['data'];
    }
    return decoded;
  }

  String? _extractMessage(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        return message.join(', ');
      }
      if (decoded['error'] is String) {
        return decoded['error'] as String;
      }
    }
    return null;
  }

  void _debugRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
    required bool authorized,
  }) {
    print(
      '[API REQUEST] ${jsonEncode({'method': method, 'url': uri.toString(), 'authorized': authorized, 'token': headers['Authorization'], 'headers': headers, 'body': body})}',
    );
  }

  void _debugResponse({
    required String method,
    required Uri uri,
    required int statusCode,
    required dynamic decoded,
  }) {
    print(
      '[API RESPONSE] ${jsonEncode({'method': method, 'url': uri.toString(), 'statusCode': statusCode, 'body': _summarizePayload(decoded)})}',
    );
  }

  void _debugApiError({
    required String method,
    required Uri uri,
    required int statusCode,
    required String? extractedMessage,
    required dynamic decoded,
  }) {
    print(
      '[API ERROR] ${jsonEncode({'method': method, 'url': uri.toString(), 'statusCode': statusCode, 'message': extractedMessage, 'body': _summarizePayload(decoded)})}',
    );
  }

  void _debugBlockedWrite({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
    required String blockedPath,
  }) {
    print(
      '[API BLOCKED WRITE] ${jsonEncode({'method': method, 'url': uri.toString(), 'blockedPath': blockedPath, 'token': headers['Authorization'], 'body': body, 'reason': 'Esta accion no esta disponible en el panel web'})}',
    );
  }

  void _debugTransportError({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
    required Object error,
  }) {
    print(
      '[API TRANSPORT ERROR] ${jsonEncode({'method': method, 'url': uri.toString(), 'token': headers['Authorization'], 'body': body, 'error': error.toString()})}',
    );
  }

  String _summarizePayload(dynamic decoded) {
    try {
      final encoded = jsonEncode(decoded);
      if (encoded.length <= 1200) {
        return encoded;
      }
      return '${encoded.substring(0, 1200)}...(truncated)';
    } catch (_) {
      return decoded?.toString() ?? 'null';
    }
  }
}
