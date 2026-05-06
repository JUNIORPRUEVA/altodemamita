import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../network/backend_http_client.dart';
import '../../services/sync/sync_config_repository.dart';

class ReadOnlyModeException implements Exception {
  const ReadOnlyModeException();

  String get message => 'Sistema en modo solo lectura';

  @override
  String toString() => message;
}

class DeviceWriteBlockedException implements Exception {
  const DeviceWriteBlockedException(this.message);

  final String message;

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
       _httpClient = httpClient ?? createBackendHttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 8);
    _httpClient.idleTimeout = const Duration(seconds: 10);
  }

  static final SystemConfigService instance = SystemConfigService._();

  final SyncConfigRepository _syncConfigRepository;
  final HttpClient _httpClient;

  bool _isReadOnly = false;
  bool _isLoading = false;
  DateTime? _lastFetchedAt;
  bool _isPrimaryDevice = false;
  bool _canWrite = true;
  DateTime? _lastDeviceValidatedAt;
  String _deviceWriteReason = '';

  bool get isReadOnly => _isReadOnly;
  bool get isLoading => _isLoading;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get isPrimaryDevice => _isPrimaryDevice;
  bool get canWrite => _canWrite;
  DateTime? get lastDeviceValidatedAt => _lastDeviceValidatedAt;
  String get deviceWriteReason => _deviceWriteReason;

  Future<void> initialize() async {
    _applyDeviceState(await _syncConfigRepository.loadDeviceWriteState());
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
        if (_lastDeviceValidatedAt == null) {
          _applyDeviceState(
            DeviceWriteState(
              isPrimary: false,
              canWrite: true,
              lastValidatedAt: null,
              reason: '',
            ),
          );
        }
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
                    decoded.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  )
                : const <String, dynamic>{});

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateState(readOnly: payload['readOnly'] == true);
      }

      final deviceState = await _fetchDeviceState(
        baseUrl: settings.normalizedBaseUrl,
        jwtToken: settings.jwtToken,
        deviceId: settings.deviceId,
      );
      _applyDeviceState(deviceState);
      await _syncConfigRepository.saveDeviceWriteState(deviceState);
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
    if (!_canWrite) {
      throw DeviceWriteBlockedException(
        _deviceWriteReason.isEmpty
            ? 'Este dispositivo no esta autorizado para escribir.'
            : _deviceWriteReason,
      );
    }
  }

  Future<void> registerCurrentDevice({bool claimPrimary = false}) async {
    final settings = await _syncConfigRepository.loadSettings();
    if (!settings.isConfigured || settings.jwtToken.trim().isEmpty) {
      return;
    }

    final uri = Uri.parse(
      '${settings.normalizedBaseUrl}/devices/${claimPrimary ? 'claim-primary' : 'register'}',
    );
    final request = await _httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${settings.jwtToken.trim()}',
    );
    request.headers.set('x-device-id', settings.deviceId);
    request.write(
      jsonEncode({
        'device_id': settings.deviceId,
        'device_name': _deviceName(),
        'platform': Platform.operatingSystem,
      }),
    );

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final decoded = body.trim().isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body);
    final payload = decoded is Map<String, dynamic>
        ? _unwrapEnvelope(decoded)
        : const <String, dynamic>{};
    final state = _deviceStateFromPayload(payload);
    _applyDeviceState(state);
    await _syncConfigRepository.saveDeviceWriteState(state);
    notifyListeners();
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

  Future<DeviceWriteState> _fetchDeviceState({
    required String baseUrl,
    required String jwtToken,
    required String deviceId,
  }) async {
    final request = await _httpClient.getUrl(
      Uri.parse('$baseUrl/devices/current'),
    );
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${jwtToken.trim()}',
    );
    request.headers.set('x-device-id', deviceId);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('device current failed: ${response.statusCode}');
    }

    final decoded = body.trim().isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body);
    final payload = decoded is Map<String, dynamic>
        ? _unwrapEnvelope(decoded)
        : const <String, dynamic>{};
    return _deviceStateFromPayload(payload);
  }

  DeviceWriteState _deviceStateFromPayload(Map<String, dynamic> payload) {
    final canWrite = payload['canWrite'] == true;
    final isPrimary = payload['isPrimary'] == true;
    final reason = payload['reason']?.toString().trim() ?? '';
    return DeviceWriteState(
      isPrimary: isPrimary,
      canWrite: canWrite,
      lastValidatedAt: DateTime.now(),
      reason: _humanizeDeviceReason(reason, canWrite: canWrite),
    );
  }

  void _applyDeviceState(DeviceWriteState state) {
    _isPrimaryDevice = state.isPrimary;
    _canWrite = state.canWrite;
    _lastDeviceValidatedAt = state.lastValidatedAt;
    _deviceWriteReason = state.reason;
  }

  String _humanizeDeviceReason(String reason, {required bool canWrite}) {
    if (canWrite) {
      return '';
    }

    switch (reason) {
      case 'panel_read_only':
        return 'El panel/PWA esta limitado a solo lectura.';
      case 'device_revoked':
        return 'Este equipo fue revocado y ya no puede escribir.';
      case 'device_not_primary':
      case 'registered_secondary':
        return 'Este equipo no es la PC principal autorizada para escribir.';
      case 'device_not_registered':
      case 'missing_device_id':
        return 'Este equipo aun no esta registrado para escribir.';
      default:
        return 'Este dispositivo no esta autorizado para escribir.';
    }
  }

  String _deviceName() {
    final computerName = Platform.environment['COMPUTERNAME']?.trim();
    if (computerName != null && computerName.isNotEmpty) {
      return computerName;
    }
    return Platform.localHostname;
  }
}
