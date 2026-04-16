import 'secure_token_storage_stub.dart'
    if (dart.library.html) 'secure_token_storage_web.dart' as implementation;

abstract class SecureTokenStorage {
  factory SecureTokenStorage() => implementation.createSecureTokenStorage();

  Future<String?> readToken(String key);

  Future<void> writeToken(String key, String token);

  Future<void> clearToken(String key);
}