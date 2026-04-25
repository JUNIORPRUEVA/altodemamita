import 'dart:html' as html;

import 'secure_token_storage.dart';

class _PersistentSecureTokenStorage implements SecureTokenStorage {
  static const String rememberMeKey = 'panel.remember_me';

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

  bool get _rememberMeEnabled =>
      _parseRememberMe(html.window.localStorage[rememberMeKey]);

  @override
  Future<void> clearToken(String key) async {
    html.window.localStorage.remove(key);
    html.window.sessionStorage.remove(key);
  }

  @override
  Future<String?> readToken(String key) async {
    if (key == rememberMeKey) {
      final raw = html.window.localStorage[key];
      return raw == null || raw.isEmpty ? null : raw;
    }

    if (!_rememberMeEnabled) {
      final sessionToken = html.window.sessionStorage[key];
      return (sessionToken != null && sessionToken.isNotEmpty)
          ? sessionToken
          : null;
    }

    final persistentToken = html.window.localStorage[key];
    if (persistentToken != null && persistentToken.isNotEmpty) {
      return persistentToken;
    }

    final sessionToken = html.window.sessionStorage[key];
    return (sessionToken != null && sessionToken.isNotEmpty)
        ? sessionToken
        : null;
  }

  @override
  Future<void> writeToken(String key, String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      await clearToken(key);
      return;
    }

    if (key == rememberMeKey) {
      html.window.localStorage[key] = normalized;
      html.window.sessionStorage.remove(key);
      return;
    }

    if (_rememberMeEnabled) {
      html.window.localStorage[key] = normalized;
      html.window.sessionStorage.remove(key);
    } else {
      html.window.sessionStorage[key] = normalized;
      html.window.localStorage.remove(key);
    }
  }
}

SecureTokenStorage createSecureTokenStorage() =>
    _PersistentSecureTokenStorage();
