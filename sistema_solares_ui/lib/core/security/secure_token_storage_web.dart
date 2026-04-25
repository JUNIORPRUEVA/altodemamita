import 'dart:html' as html;

import 'secure_token_storage.dart';

class _PersistentSecureTokenStorage implements SecureTokenStorage {
  @override
  Future<void> clearToken(String key) async {
    html.window.localStorage.remove(key);
    html.window.sessionStorage.remove(key);
  }

  @override
  Future<String?> readToken(String key) async {
    final persistentToken = html.window.localStorage[key];
    if (persistentToken != null && persistentToken.isNotEmpty) {
      return persistentToken;
    }

    final sessionToken = html.window.sessionStorage[key];
    if (sessionToken != null && sessionToken.isNotEmpty) {
      html.window.localStorage[key] = sessionToken;
      html.window.sessionStorage.remove(key);
      return sessionToken;
    }

    return null;
  }

  @override
  Future<void> writeToken(String key, String token) async {
    html.window.localStorage[key] = token;
    html.window.sessionStorage.remove(key);
  }
}

SecureTokenStorage createSecureTokenStorage() =>
    _PersistentSecureTokenStorage();
