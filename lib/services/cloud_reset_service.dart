import 'dart:convert';
import 'dart:io';

import '../core/config/backend_config.dart';
import '../core/network/backend_http_client.dart';

class CloudResetException implements Exception {
  const CloudResetException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudResetResult {
  const CloudResetResult({
    required this.message,
    required this.deletedCounts,
    required this.resetAt,
  });

  final String message;
  final Map<String, int> deletedCounts;
  final String resetAt;

  String get summary {
    final ordered = [
      'sales',
      'clients',
      'products',
      'installments',
      'payments',
    ];
    final chunks = ordered
        .map((key) => '$key=${deletedCounts[key] ?? 0}')
        .join(' | ');
    return '$message $chunks';
  }
}

class CloudResetService {
  CloudResetService({HttpClient? httpClient})
    : _httpClient = httpClient ?? createBackendHttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
    _httpClient.idleTimeout = const Duration(seconds: 15);
  }

  static const String _adminKey = '123456';

  final HttpClient _httpClient;

  Future<CloudResetResult> resetCloudDatabase() async {
    final baseUrl = normalizeBackendBaseUrl(BASE_URL);
    final uri = Uri.parse('$baseUrl/reset-database');

    final request = await _httpClient.deleteUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set('x-admin-key', _adminKey);

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final decoded = _decodeJson(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudResetException(_extractErrorMessage(decoded));
    }

    final envelope = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    final data = envelope['data'] is Map
        ? (envelope['data'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    final deleted = data['deleted'] is Map
        ? (data['deleted'] as Map).map(
            (key, value) => MapEntry(key.toString(), _readCount(value)),
          )
        : <String, int>{};

    return CloudResetResult(
      message: data['message']?.toString().trim().isNotEmpty == true
          ? data['message'].toString().trim()
          : 'Nube reseteada correctamente.',
      deletedCounts: deleted,
      resetAt: data['reset_at']?.toString().trim() ?? '',
    );
  }

  void dispose() {
    _httpClient.close(force: true);
  }

  Object? _decodeJson(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  String _extractErrorMessage(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    }
    return serverConnectionErrorMessage;
  }

  int _readCount(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
