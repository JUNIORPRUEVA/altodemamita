import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_token_storage.dart';

class _PreferencesSecureTokenStorage implements SecureTokenStorage {
  _PreferencesSecureTokenStorage({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const String rememberMeKey = 'panel.remember_me';

  final Future<SharedPreferences> Function() _prefs;
  final Map<String, String> _sessionStorage = <String, String>{};

  Future<SharedPreferences?> _tryPrefs() async {
    try {
      return await _prefs();
    } on MissingPluginException {
      return null;
    }
  }

  bool _parseRememberMe(String? rawValue) {
    if (rawValue == null) {
      return true;
    }
    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  Future<bool> _isRememberMeEnabled({SharedPreferences? prefs}) async {
    final resolvedPrefs = prefs ?? await _tryPrefs();
    if (resolvedPrefs == null) {
      return true;
    }
    return _parseRememberMe(resolvedPrefs.getString(rememberMeKey));
  }

  @override
  Future<void> clearToken(String key) async {
    _sessionStorage.remove(key);
    final prefs = await _tryPrefs();
    await prefs?.remove(key);
  }

  @override
  Future<String?> readToken(String key) async {
    if (key == rememberMeKey) {
      final prefs = await _tryPrefs();
      return prefs?.getString(key);
    }

    final sessionValue = _sessionStorage[key];
    if (sessionValue != null && sessionValue.trim().isNotEmpty) {
      return sessionValue;
    }

    final prefs = await _tryPrefs();
    return prefs?.getString(key);
  }

  @override
  Future<void> writeToken(String key, String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      await clearToken(key);
      return;
    }

    final prefs = await _tryPrefs();
    if (prefs == null) {
      _sessionStorage[key] = normalized;
      return;
    }

    if (key == rememberMeKey) {
      await prefs.setString(key, normalized);
      return;
    }

    final rememberMe = await _isRememberMeEnabled(prefs: prefs);
    if (rememberMe) {
      await prefs.setString(key, normalized);
      _sessionStorage.remove(key);
    } else {
      _sessionStorage[key] = normalized;
      await prefs.remove(key);
    }
  }
}

SecureTokenStorage createSecureTokenStorage() => _PreferencesSecureTokenStorage();

