import 'dart:async';
import 'dart:convert';
import '../network/platform_http.dart';

import '../config/backend_config.dart';

class CloudApiResponse {
  const CloudApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isRetryable => statusCode == 0 || statusCode >= 500;
  bool get isPermanentFailure =>
      statusCode >= 400 && statusCode < 500 && statusCode != 409;
  bool get isBusinessConflict => statusCode == 409;
}

class CloudApiClient {
  CloudApiClient({
    HttpClient? httpClient,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? HttpClient(),
       _baseUrl = baseUrl ?? effectiveBackendBaseUrl,
       _timeout = timeout;

  final HttpClient _httpClient;
  final String _baseUrl;
  final Duration _timeout;

  Future<CloudApiResponse> sendOperation({
    required String operationType,
    required String operationId,
    required Map<String, Object?> payload,
    required String accessToken,
  }) {
    switch (operationType) {
      case 'sale.create':
        return post(
          '/authoritative/sales',
          payload: payload,
          accessToken: accessToken,
          idempotencyKey: operationId,
        );
      case 'payment.register':
        return post(
          '/authoritative/payments',
          payload: payload,
          accessToken: accessToken,
          idempotencyKey: operationId,
        );
      case 'payment.annul':
        final paymentId = payload['paymentId']?.toString() ?? '';
        return post(
          '/authoritative/payments/$paymentId/annul',
          payload: payload,
          accessToken: accessToken,
          idempotencyKey: operationId,
        );
      case 'sale.cancel':
        final saleId = payload['saleId']?.toString() ?? '';
        return post(
          '/authoritative/sales/$saleId/cancel',
          payload: payload,
          accessToken: accessToken,
          idempotencyKey: operationId,
        );
      default:
        return Future.value(
          CloudApiResponse(
            statusCode: 400,
            body: {'message': 'Unsupported operation type: $operationType'},
          ),
        );
    }
  }

  Future<CloudApiResponse> login({
    required String email,
    required String password,
    String clientType = 'desktop',
  }) {
    return post(
      '/auth/login',
      payload: {'email': email, 'password': password, 'clientType': clientType},
      accessToken: '',
    );
  }

  Future<CloudApiResponse> refresh({
    required String refreshToken,
    String clientType = 'desktop',
  }) {
    return post(
      '/auth/refresh',
      payload: {'token': refreshToken, 'clientType': clientType},
      accessToken: '',
    );
  }

  Future<CloudApiResponse> me({required String accessToken}) {
    return get('/auth/me', accessToken: accessToken);
  }

  Future<CloudApiResponse> getCompanyProfile({required String accessToken}) {
    return get('/business/company-profile', accessToken: accessToken);
  }

  Future<CloudApiResponse> saveCompanyProfile({
    required String accessToken,
    required Map<String, Object?> payload,
  }) {
    return put(
      '/business/company-profile',
      payload: payload,
      accessToken: accessToken,
    );
  }

  Future<CloudApiResponse> getFinancialParameters({
    required String accessToken,
  }) {
    return get('/business/financial-parameters', accessToken: accessToken);
  }

  Future<CloudApiResponse> saveFinancialParameters({
    required String accessToken,
    required Map<String, Object?> payload,
  }) {
    return put(
      '/business/financial-parameters',
      payload: payload,
      accessToken: accessToken,
    );
  }

  Future<CloudApiResponse> getBusinessConfiguration({
    required String accessToken,
  }) {
    return get('/business/business-config', accessToken: accessToken);
  }

  Future<CloudApiResponse> saveBusinessConfiguration({
    required String accessToken,
    required String key,
    required Map<String, Object?> payload,
  }) {
    return put(
      '/business/business-config/$key',
      payload: payload,
      accessToken: accessToken,
    );
  }

  Future<CloudApiResponse> post(
    String path, {
    required Map<String, Object?> payload,
    required String accessToken,
    String? idempotencyKey,
  }) async {
    return _send(
      method: 'POST',
      path: path,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      payload: payload,
    );
  }

  Future<CloudApiResponse> put(
    String path, {
    required Map<String, Object?> payload,
    required String accessToken,
    String? idempotencyKey,
  }) async {
    return _send(
      method: 'PUT',
      path: path,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      payload: payload,
    );
  }

  Future<CloudApiResponse> get(
    String path, {
    required String accessToken,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path).replace(queryParameters: query);
    return _request('GET', uri, accessToken: accessToken);
  }

  Future<CloudApiResponse> _send({
    required String method,
    required String path,
    required String accessToken,
    String? idempotencyKey,
    Map<String, Object?>? payload,
  }) async {
    return _request(
      method,
      _uri(path),
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      payload: payload,
    );
  }

  Future<CloudApiResponse> _request(
    String method,
    Uri uri, {
    required String accessToken,
    String? idempotencyKey,
    Map<String, Object?>? payload,
  }) async {
    try {
      final request = switch (method) {
        'GET' => await _httpClient.getUrl(uri).timeout(_timeout),
        'PUT' => await _httpClient.putUrl(uri).timeout(_timeout),
        _ => await _httpClient.postUrl(uri).timeout(_timeout),
      };
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      request.headers.set('x-company-tenant-key', companyTenantKey);
      if (accessToken.trim().isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${accessToken.trim()}',
        );
      }
      if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
        request.headers.set('Idempotency-Key', idempotencyKey.trim());
      }
      if (payload != null) {
        request.write(jsonEncode(payload));
      }
      final response = await request.close().timeout(_timeout);
      final responseBody = await utf8.decoder.bind(response).join();
      return CloudApiResponse(
        statusCode: response.statusCode,
        body: _decodeBody(responseBody),
      );
    } on SocketException catch (error) {
      return CloudApiResponse(statusCode: 0, body: {'message': '$error'});
    } on TimeoutException catch (error) {
      return CloudApiResponse(statusCode: 0, body: {'message': '$error'});
    } on IOException catch (error) {
      return CloudApiResponse(statusCode: 0, body: {'message': '$error'});
    } on FormatException catch (error) {
      return CloudApiResponse(
        statusCode: 0,
        body: {'message': 'Invalid cloud response: ${error.message}'},
      );
    }
  }

  Uri _uri(String path) {
    final normalizedBase = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$normalizedBase/$normalizedPath');
  }
}

Map<String, Object?> _decodeBody(String body) {
  if (body.trim().isEmpty) {
    return {};
  }
  final decoded = jsonDecode(body);
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  return {'data': decoded};
}
