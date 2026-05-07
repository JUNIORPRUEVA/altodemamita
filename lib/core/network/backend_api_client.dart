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
          'Esta PC no esta autorizada (falta x-device-id local).',
        );
      }
      headers['Authorization'] = 'Bearer $token';
      headers['x-device-id'] = deviceId;
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    print('ENVIANDO DATA: ${body == null ? '<empty>' : jsonEncode(body)}');

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

    print('RESPUESTA: ${response.body}');

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
