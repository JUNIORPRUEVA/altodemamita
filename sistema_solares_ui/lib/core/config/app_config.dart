import 'dart:convert';

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

    final configUri = Uri.base.resolve('app-config.json');

    try {
      final response = await http.get(configUri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _apiBaseUrl = _defaultApiBaseUrl;
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        _apiBaseUrl = _defaultApiBaseUrl;
        return;
      }

      final runtimeApiBaseUrl = decoded['API_BASE_URL']?.toString();
      _apiBaseUrl = _normalizeBaseUrl(runtimeApiBaseUrl ?? _defaultApiBaseUrl);
    } catch (_) {
      _apiBaseUrl = _defaultApiBaseUrl;
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

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _defaultApiBaseUrl;
    }

    return trimmed.replaceAll(RegExp(r'/$'), '');
  }
}