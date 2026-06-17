import 'package:flutter/foundation.dart';

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

  static final SystemConfigService instance = SystemConfigService._();

  final SyncConfigRepository _syncConfigRepository;

  bool _isLoading = false;
  DateTime? _lastFetchedAt;
  String _currentDeviceId = '';

  bool get isReadOnly => false;
  bool get isLoading => _isLoading;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get isPrimaryDevice => true;
  bool get canWrite => true;
  DateTime? get lastDeviceValidatedAt => _lastFetchedAt;
  String get deviceWriteReason => '';
  String get currentDeviceId => _currentDeviceId;
  String get lastRefreshError => '';

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
    return;
  }

  Future<void> registerCurrentDevice({bool claimPrimary = false}) async {
    await refresh();
  }
}
