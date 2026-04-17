import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AppConfig {
  static const String _defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
      'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
  );

  static String _apiBaseUrl = _defaultApiBaseUrl;
  static bool _initialized = false;

  static String get apiBaseUrl => _normalizeBaseUrl(_apiBaseUrl);
  static const String appTitle = 'Sistema Solares | Panel Web';

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    if (!kIsWeb) {
      _apiBaseUrl = _defaultApiBaseUrl;
      return;
    }

    final configUri = Uri.base.resolve(
      'app-config.json?v=${DateTime.now().millisecondsSinceEpoch}',
    );

    try {
      final response = await http.get(
        configUri,
        headers: const <String, String>{
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _apiBaseUrl = _defaultApiBaseUrl;
        _logConfig('runtime_config_http_${response.statusCode}', _apiBaseUrl);
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        _apiBaseUrl = _defaultApiBaseUrl;
        _logConfig('runtime_config_invalid_payload', _apiBaseUrl);
        return;
      }

      final runtimeApiBaseUrl = decoded['API_BASE_URL']?.toString();
      _apiBaseUrl = _normalizeBaseUrl(runtimeApiBaseUrl ?? _defaultApiBaseUrl);
      _logConfig(runtimeApiBaseUrl == null ? 'dart_define_fallback' : 'runtime_config', _apiBaseUrl);
    } catch (error, stackTrace) {
      _apiBaseUrl = _defaultApiBaseUrl;
      developer.log(
        'AppConfig.initialize fallback to default API base URL',
        name: 'SistemaSolares.AppConfig',
        error: error,
        stackTrace: stackTrace,
      );
      _logConfig('runtime_config_exception', _apiBaseUrl);
    }
  }

  static String get realtimeUrl {
    final uri = Uri.parse(apiBaseUrl);
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isNotEmpty && segments.last == 'api') {
      segments.removeLast();
    }
    final trimmed = uri.replace(pathSegments: segments);
    final normalized = trimmed.toString().replaceAll(RegExp(r'/$'), '');
    return '$normalized/realtime';
  }

  static void _logConfig(String source, String value) {
    developer.log(
      'Resolved API base URL from $source: $value',
      name: 'SistemaSolares.AppConfig',
    );
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _defaultApiBaseUrl;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.trim().isEmpty) {
      return trimmed.replaceAll(RegExp(r'/$'), '');
    }

    final pathSegments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (pathSegments.isEmpty || pathSegments.last.toLowerCase() != 'api') {
      pathSegments.add('api');
    }

    return uri.replace(pathSegments: pathSegments).toString().replaceAll(RegExp(r'/$'), '');
  }
}