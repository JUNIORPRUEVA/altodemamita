import 'secure_token_storage.dart';

class _InMemorySecureTokenStorage implements SecureTokenStorage {
  final Map<String, String> _storage = <String, String>{};

  @override
  Future<void> clearToken(String key) async {
    _storage.remove(key);
  }

  @override
  Future<String?> readToken(String key) async {
    return _storage[key];
  }

  @override
  Future<void> writeToken(String key, String token) async {
    _storage[key] = token;
  }
}

SecureTokenStorage createSecureTokenStorage() => _InMemorySecureTokenStorage();
