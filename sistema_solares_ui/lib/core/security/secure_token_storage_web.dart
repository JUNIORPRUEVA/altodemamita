import 'package:web/web.dart' as web;

import 'secure_token_storage.dart';

class _PersistentSecureTokenStorage implements SecureTokenStorage {
  @override
  Future<void> clearToken(String key) async {
    web.window.localStorage.removeItem(key);
    web.window.sessionStorage.removeItem(key);
  }

  @override
  Future<String?> readToken(String key) async {
    final persistentToken = web.window.localStorage.getItem(key);
    if (persistentToken != null && persistentToken.isNotEmpty) {
      return persistentToken;
    }

    final sessionToken = web.window.sessionStorage.getItem(key);
    if (sessionToken != null && sessionToken.isNotEmpty) {
      web.window.localStorage.setItem(key, sessionToken);
      web.window.sessionStorage.removeItem(key);
      return sessionToken;
    }

    return null;
  }

  @override
  Future<void> writeToken(String key, String token) async {
    web.window.localStorage.setItem(key, token);
    web.window.sessionStorage.removeItem(key);
  }
}

SecureTokenStorage createSecureTokenStorage() => _PersistentSecureTokenStorage();