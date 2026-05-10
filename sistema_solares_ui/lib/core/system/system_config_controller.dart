import 'package:flutter/foundation.dart';

import 'package:sistema_solares_ui/core/network/api_client.dart';

class SystemConfigController extends ChangeNotifier {
  SystemConfigController({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  bool _initialized = false;
  bool _isReadOnly = false;

  bool get initialized => _initialized;
  bool get isReadOnly => _isReadOnly;

  Future<void> initialize() async {
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final response = await _apiClient.get('/system/config', authorized: false);
      final payload = response as Map<String, dynamic>? ?? const <String, dynamic>{};
      _isReadOnly = payload['readOnly'] == true;
    } catch (_) {
      // Keep the last known state if the config endpoint is temporarily unavailable.
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }
}
