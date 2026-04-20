import 'dart:convert';
import 'dart:developer' as developer;

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
  Future<void> Function()? _unauthorizedHandler;

  void setJwtToken(String? token) {
    _jwtToken = token;
  }

  void setUnauthorizedHandler(Future<void> Function()? handler) {
    _unauthorizedHandler = handler;
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
  }) async {
    _assertPanelOperationAllowed(method, path);

    final cleanedQuery = <String, String>{
      for (final entry in (queryParameters ?? const <String, String>{}).entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path').replace(
      queryParameters: cleanedQuery.isEmpty ? null : cleanedQuery,
    );

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (authorized && _jwtToken?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    late http.Response response;
    final encodedBody = body == null ? null : jsonEncode(body);

    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
      case 'POST':
        response = await _client.post(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        response = await _client.patch(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        response = await _client.delete(uri, headers: headers);
      default:
        throw ApiException('Metodo HTTP no soportado: $method');
    }

    final hasBody = response.body.trim().isNotEmpty;
    final decoded = hasBody ? jsonDecode(response.body) : null;
    _logPaymentsTraffic(
      method: method,
      uri: uri,
      statusCode: response.statusCode,
      decoded: decoded,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _unwrapEnvelope(decoded);
    }

    if (response.statusCode == 401 && authorized) {
      await _unauthorizedHandler?.call();
    }

    final extractedMessage = _extractMessage(decoded);

    if (extractedMessage == 'READ_ONLY_MODE') {
      throw ApiException(
        'Sistema en modo solo lectura',
        statusCode: response.statusCode,
      );
    }

    throw ApiException(
      extractedMessage ?? 'La solicitud fallo con estado ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  void _assertPanelOperationAllowed(String method, String path) {
    final normalizedMethod = method.trim().toUpperCase();
    if (normalizedMethod == 'GET') {
      return;
    }

    final normalizedPath = path.trim().toLowerCase();
    for (final blockedPath in _blockedPanelWritePaths) {
      if (normalizedPath.contains(blockedPath)) {
        throw ApiException('Esta accion no esta disponible en el panel web');
      }
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

  void _logPaymentsTraffic({
    required String method,
    required Uri uri,
    required int statusCode,
    required dynamic decoded,
  }) {
    if (!_isPaymentsDebugPath(uri.path)) {
      return;
    }

    developer.log(
      'Payments request $method ${uri.toString()} -> $statusCode payload=${_summarizePayload(decoded)}',
      name: 'SistemaSolares.PaymentsApi',
    );
  }

  bool _isPaymentsDebugPath(String path) {
    final normalized = path.toLowerCase();
    return normalized.contains('/payments');
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