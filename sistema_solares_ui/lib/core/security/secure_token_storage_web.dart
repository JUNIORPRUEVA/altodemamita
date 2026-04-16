import 'package:web/web.dart' as web;

import 'secure_token_storage.dart';

class _SessionSecureTokenStorage implements SecureTokenStorage {
  @override
  Future<void> clearToken(String key) async {
    web.window.sessionStorage.removeItem(key);
  }

  @override
  Future<String?> readToken(String key) async {
    return web.window.sessionStorage.getItem(key);
  }

  @override
  Future<void> writeToken(String key, String token) async {
    web.window.sessionStorage.setItem(key, token);
  }
}

SecureTokenStorage createSecureTokenStorage() => _SessionSecureTokenStorage();