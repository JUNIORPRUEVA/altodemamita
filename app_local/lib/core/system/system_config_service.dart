import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/sync/sync_settings.dart';
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
  SystemConfigService._({SyncConfigRepository? syncConfigRepository})
    : _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository();

  @visibleForTesting
  factory SystemConfigService.test({
    SyncConfigRepository? syncConfigRepository,
  }) {
    return SystemConfigService._(syncConfigRepository: syncConfigRepository);
  }

  factory SystemConfigService.withSyncConfigRepository({
    required SyncConfigRepository syncConfigRepository,
  }) {
    return SystemConfigService._(syncConfigRepository: syncConfigRepository);
  }

  static final SystemConfigService instance = SystemConfigService._();

  final SyncConfigRepository _syncConfigRepository;

  bool _isLoading = false;
  DateTime? _lastFetchedAt;
  DateTime? _lastDeviceValidatedAt;
  String _currentDeviceId = '';
  bool _isReadOnly = false;
  bool _isPrimaryDevice = true;
  bool _canWrite = true;
  String _deviceWriteReason = '';
  String _lastRefreshError = '';

  bool get isReadOnly => _isReadOnly;
  bool get isLoading => _isLoading;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get isPrimaryDevice => _isPrimaryDevice;
  bool get canWrite => _canWrite;
  DateTime? get lastDeviceValidatedAt => _lastDeviceValidatedAt;
  String get deviceWriteReason => _deviceWriteReason;
  String get currentDeviceId => _currentDeviceId;
  String get lastRefreshError => _lastRefreshError;

  Future<void> initialize() => refresh();

  Future<void> refresh({bool throwOnFailure = false}) async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final settings = await _syncConfigRepository.loadSettings();
      _currentDeviceId = settings.deviceId;
      await _applyPersistedDeviceState();

      try {
        await _refreshSystemConfig(settings);
      } catch (error) {
        _lastRefreshError = error.toString();
        debugPrint('[system-config] remote config refresh skipped: $error');
      }

      await _refreshCurrentDevice(settings);
      _lastFetchedAt = DateTime.now();
    } catch (error) {
      if (throwOnFailure) {
        rethrow;
      }
      debugPrint('[system-config] local refresh skipped: $error');
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
            ? 'Este equipo no esta autorizado para escribir.'
            : _deviceWriteReason,
      );
    }
    return;
  }

  Future<void> registerCurrentDevice({bool claimPrimary = false}) async {
    await refresh();
  }

  Future<void> _applyPersistedDeviceState() async {
    final state = await _syncConfigRepository.loadDeviceWriteState();
    _isPrimaryDevice = state.isPrimary;
    _canWrite = state.canWrite;
    _lastDeviceValidatedAt = state.lastValidatedAt;
    _deviceWriteReason = state.reason;
  }

  Future<void> _refreshSystemConfig(SyncSettings settings) async {
    final payload = await _getJson(
      settings,
      Uri.parse('${settings.normalizedBaseUrl}/system/config'),
    );
    final data = _dataPayload(payload);
    if (data == null) {
      return;
    }
    final readOnly = data['readOnly'] ?? data['read_only'] ?? data['systemReadOnly'];
    if (readOnly is bool) {
      _isReadOnly = readOnly;
    }
  }

  Future<void> _refreshCurrentDevice(SyncSettings settings) async {
    if (settings.deviceId.trim().isEmpty || settings.jwtToken.trim().isEmpty) {
      return;
    }

    final payload = await _getJson(
      settings,
      Uri.parse('${settings.normalizedBaseUrl}/devices/current'),
    );
    final data = _dataPayload(payload);
    if (data == null) {
      return;
    }

    final now = DateTime.now();
    final state = DeviceWriteState(
      isPrimary: data['isPrimary'] == true || data['is_primary'] == true,
      canWrite: data['canWrite'] == true || data['can_write'] == true,
      lastValidatedAt: now,
      reason: (data['reason'] ?? '').toString(),
    );
    await _syncConfigRepository.saveDeviceWriteState(state);
    _isPrimaryDevice = state.isPrimary;
    _canWrite = state.canWrite;
    _lastDeviceValidatedAt = state.lastValidatedAt;
    _deviceWriteReason = state.canWrite ? '' : state.reason;
    _lastRefreshError = '';
  }

  Future<Map<String, dynamic>> _getJson(SyncSettings settings, Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (settings.jwtToken.trim().isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${settings.jwtToken.trim()}',
        );
      }
      if (settings.deviceId.trim().isNotEmpty) {
        request.headers.set('x-device-id', settings.deviceId.trim());
      }

      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: $body',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return const {};
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic>? _dataPayload(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return payload;
  }
}
