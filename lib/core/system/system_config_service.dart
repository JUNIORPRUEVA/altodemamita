import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/sync/sync_config_repository.dart';

class ReadOnlyModeException implements Exception {
  const ReadOnlyModeException();

  String get message => 'Sistema en modo solo lectura';

  @override
  String toString() => message;
}

bool isReadOnlyModeError(Object? error) {
  if (error is ReadOnlyModeException) {
    return true;
  }

  final text = error?.toString().toUpperCase() ?? '';
  return text.contains('READ_ONLY_MODE') ||
      text.contains('SISTEMA EN MODO SOLO LECTURA');
}

class SystemConfigService extends ChangeNotifier {
  SystemConfigService._({
    SyncConfigRepository? syncConfigRepository,
    HttpClient? httpClient,
  }) : _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository(),
       _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 8);
    _httpClient.idleTimeout = const Duration(seconds: 10);
  }

  static final SystemConfigService instance = SystemConfigService._();

  final SyncConfigRepository _syncConfigRepository;
  final HttpClient _httpClient;

  bool _isReadOnly = false;
  bool _isLoading = false;
  DateTime? _lastFetchedAt;

  bool get isReadOnly => _isReadOnly;
  bool get isLoading => _isLoading;
  DateTime? get lastFetchedAt => _lastFetchedAt;

  Future<void> initialize() async {
    await refresh();
  }

  Future<void> refresh() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final settings = await _syncConfigRepository.loadSettings();
      if (!settings.isConfigured) {
        _updateState(readOnly: false);
        return;
      }

      final uri = Uri.parse('${settings.normalizedBaseUrl}/system/config');
      if (uri.host.trim().isEmpty) {
        _updateState(readOnly: false);
        return;
      }

      final request = await _httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final decoded = body.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(body);
      final payload = decoded is Map<String, dynamic>
          ? _unwrapEnvelope(decoded)
          : (decoded is Map
                ? _unwrapEnvelope(
                    decoded.map((key, value) => MapEntry(key.toString(), value)),
                  )
                : const <String, dynamic>{});

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateState(readOnly: payload['readOnly'] == true);
      }
    } catch (_) {
      // Preserve the last known state if the backend is temporarily unreachable.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void ensureWritable() {
    if (_isReadOnly) {
      throw const ReadOnlyModeException();
    }
  }

  Map<String, dynamic> _unwrapEnvelope(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  void _updateState({required bool readOnly}) {
    _isReadOnly = readOnly;
    _lastFetchedAt = DateTime.now();
  }
}