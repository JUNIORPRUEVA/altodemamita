import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/sync/sync_config_repository.dart';
import 'backend_http_client.dart';

class BackendApiException implements Exception {
  const BackendApiException(this.message, {this.statusCode, this.responseBody});

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}

class BackendApiClient {
  BackendApiClient({
    http.Client? client,
    SyncConfigRepository? syncConfigRepository,
  }) : _client = client ?? createBackendPackageHttpClient(),
       _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository();

  final http.Client _client;
  final SyncConfigRepository _syncConfigRepository;

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
  }) {
    return _request(
      'GET',
      path,
      queryParameters: queryParameters,
      authorized: authorized,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
  }) {
    return _request(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      authorized: authorized,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
  }) {
    return _request(
      'PATCH',
      path,
      body: body,
      queryParameters: queryParameters,
      authorized: authorized,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<dynamic> delete(
    String path, {
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
  }) {
    return _request(
      'DELETE',
      path,
      queryParameters: queryParameters,
      authorized: authorized,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
    bool isRetry = false,
  }) async {
    final settings = await _syncConfigRepository.loadSettings();
    final uri = Uri.parse('${settings.normalizedBaseUrl}$path').replace(
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final normalizedIdempotencyKey = idempotencyKey?.trim();
    if (normalizedIdempotencyKey != null &&
        normalizedIdempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = normalizedIdempotencyKey;
    }
    if (authorized) {
      final token = settings.jwtToken.trim();
      if (token.isEmpty) {
        throw const BackendApiException(
          'No hay una sesion online activa para ejecutar la operacion.',
        );
      }
      final deviceId = settings.deviceId.trim();
      if (deviceId.isEmpty) {
        throw const BackendApiException(
          'No hay ID local de dispositivo configurado.',
        );
      }
      headers['Authorization'] = 'Bearer $token';
      headers['x-device-id'] = deviceId;
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    print('ENVIANDO DATA: ${_redactBodyForLog(body)}');

    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: encodedBody,
          );
        case 'PATCH':
          response = await _client.patch(
            uri,
            headers: headers,
            body: encodedBody,
          );
        case 'DELETE':
          response = await _client.delete(uri, headers: headers);
        default:
          throw BackendApiException('Metodo HTTP no soportado: $method');
      }
    } catch (error) {
      print('HTTP ERROR: $error');
      throw BackendApiException(
        'No se pudo completar la solicitud HTTP: $error',
      );
    }

    print('RESPUESTA: ${_redactTextForLog(response.body)}');

    dynamic decoded;
    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && authorized && !isRetry) {
        final refreshed = await _tryRefreshJwtToken(settings);
        if (refreshed) {
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

      String message = 'La solicitud fallo con estado ${response.statusCode}.';
      if (decoded is Map<String, dynamic>) {
        final rawMessage = decoded['message'];
        if (rawMessage is String && rawMessage.trim().isNotEmpty) {
          message = rawMessage.trim();
        } else if (rawMessage is List && rawMessage.isNotEmpty) {
          message = rawMessage.join(', ');
        } else {
          final rawError = decoded['error'];
          if (rawError is Map && rawError['message'] is String) {
            final errorMessage = rawError['message'].toString().trim();
            if (errorMessage.isNotEmpty) {
              message = errorMessage;
            }
          }
        }
      }
      throw BackendApiException(
        message,
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    if (decoded is Map<String, dynamic> && decoded['success'] == true) {
      return decoded['data'];
    }
    return decoded;
  }

  String _redactBodyForLog(Map<String, dynamic>? body) {
    if (body == null || body.isEmpty) {
      return '<empty>';
    }
    return jsonEncode(_redactValue(body));
  }

  Object? _redactValue(Object? value) {
    if (value is Map) {
      return value.map((key, entryValue) {
        final normalizedKey = key.toString().trim().toLowerCase();
        if (normalizedKey.contains('password') ||
            normalizedKey.contains('token') ||
            normalizedKey.contains('secret')) {
          return MapEntry(key, '[REDACTED]');
        }
        return MapEntry(key, _redactValue(entryValue));
      });
    }
    if (value is List) {
      return value.map(_redactValue).toList(growable: false);
    }
    return value;
  }

  String _redactTextForLog(String value) {
    return value.replaceAll(
      RegExp(
        r'("(?:accessToken|refreshToken|token|password)"\s*:\s*")[^"]*(")',
        caseSensitive: false,
      ),
      r'$1[REDACTED]$2',
    );
  }

  Future<bool> _tryRefreshJwtToken(dynamic settings) async {
    try {
      final token = settings.jwtToken.toString().trim();
      if (token.isEmpty) {
        return false;
      }

      final refreshUri = Uri.parse(
        '${settings.normalizedBaseUrl}/auth/refresh',
      );
      final response = await _client.post(
        refreshUri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': token, 'clientType': 'desktop'}),
      );

      dynamic decoded;
      if (response.body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          decoded = response.body;
        }
      }

      final unwrapped =
          decoded is Map<String, dynamic> && decoded.containsKey('success')
          ? decoded['data']
          : decoded;

      if (unwrapped is! Map<String, dynamic>) {
        return false;
      }

      final newToken = (unwrapped['accessToken'] ?? '').toString().trim();
      if (newToken.isEmpty) {
        return false;
      }

      await _syncConfigRepository.saveJwtToken(newToken);
      return true;
    } catch (_) {
      return false;
    }
  }
}
