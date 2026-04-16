import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensitiveStorage {
  SensitiveStorage({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferencesFactory,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  final FlutterSecureStorage _secureStorage;
  final Future<SharedPreferences> Function() _preferencesFactory;

  Future<String?> read(String key) async {
    try {
      final value = await _secureStorage.read(key: key);
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    } on MissingPluginException {
      // Falls back to SharedPreferences in unit tests or unsupported targets.
    } on PlatformException {
      // Falls back to SharedPreferences when secure storage is unavailable.
    }

    final prefs = await _preferencesFactory();
    return prefs.getString(_fallbackKey(key));
  }

  Future<void> write(String key, String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await delete(key);
      return;
    }

    try {
      await _secureStorage.write(key: key, value: normalized);
      final prefs = await _preferencesFactory();
      await prefs.remove(_fallbackKey(key));
      return;
    } on MissingPluginException {
      // Falls back to SharedPreferences in unit tests or unsupported targets.
    } on PlatformException {
      // Falls back to SharedPreferences when secure storage is unavailable.
    }

    final prefs = await _preferencesFactory();
    await prefs.setString(_fallbackKey(key), normalized);
  }

  Future<void> delete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      // Falls back to SharedPreferences in unit tests or unsupported targets.
    } on PlatformException {
      // Falls back to SharedPreferences when secure storage is unavailable.
    }

    final prefs = await _preferencesFactory();
    await prefs.remove(_fallbackKey(key));
  }

  String _fallbackKey(String key) => 'secure.$key';
}