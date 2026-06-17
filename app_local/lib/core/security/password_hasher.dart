import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PasswordHasher {
  PasswordHasher._();

  static const String defaultAdminEmail = 'admin@sistema.local';
  static const String legacyDefaultAdminPassword = 'Admin12345';
  static const String legacyMigratedPassword = 'Temporal12345';
  static const int defaultIterations = 60000;

  static final Random _random = Random.secure();

  static String hashPassword(
    String password, {
    String? salt,
    int iterations = defaultIterations,
  }) {
    final resolvedSalt = salt ?? _generateSalt();
    final digest = _deriveDigest(
      password: password,
      salt: resolvedSalt,
      iterations: iterations,
    );
    return 'v2\$$iterations\$$resolvedSalt\$${digest.toString()}';
  }

  static bool verifyPassword(String password, String storedHash) {
    if (storedHash.startsWith('v2\$')) {
      final parts = storedHash.split('\$');
      if (parts.length != 4) {
        return false;
      }

      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations <= 0) {
        return false;
      }

      final expectedHash = hashPassword(
        password,
        salt: parts[2],
        iterations: iterations,
      );
      return _constantTimeEquals(expectedHash, storedHash);
    }

    final separatorIndex = storedHash.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex >= storedHash.length - 1) {
      return false;
    }

    final salt = storedHash.substring(0, separatorIndex);
    final digest = sha256.convert(utf8.encode('$salt::$password')).toString();
    final expectedHash = '$salt:$digest';
    return _constantTimeEquals(expectedHash, storedHash);
  }

  static bool needsRehash(String storedHash) {
    if (!storedHash.startsWith('v2\$')) {
      return true;
    }

    final parts = storedHash.split('\$');
    if (parts.length != 4) {
      return true;
    }

    final iterations = int.tryParse(parts[1]);
    return iterations == null || iterations < defaultIterations;
  }

  static String generateRandomToken([int length = 32]) {
    final values = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static String generateRecoveryCode({int groups = 4, int groupLength = 4}) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final segments = <String>[];

    for (var groupIndex = 0; groupIndex < groups; groupIndex++) {
      final buffer = StringBuffer();
      for (var charIndex = 0; charIndex < groupLength; charIndex++) {
        buffer.write(alphabet[_random.nextInt(alphabet.length)]);
      }
      segments.add(buffer.toString());
    }

    return segments.join('-');
  }

  static String encryptRecoveryPayload({
    required String plaintext,
    required String secret,
  }) {
    final normalizedSecret = secret.trim();
    if (normalizedSecret.isEmpty) {
      throw ArgumentError('El secreto de recuperacion es obligatorio.');
    }

    final nonce = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = sha256.convert(utf8.encode(normalizedSecret)).bytes;
    final cipherBytes = _xorWithRecoveryKeystream(
      utf8.encode(plaintext),
      key,
      nonce,
    );
    final macBytes = Hmac(
      sha256,
      key,
    ).convert([...nonce, ...cipherBytes]).bytes;

    return [
      'v1',
      _base64UrlEncode(nonce),
      _base64UrlEncode(cipherBytes),
      _base64UrlEncode(macBytes),
    ].join('.');
  }

  static String decryptRecoveryPayload({
    required String protectedValue,
    required String secret,
  }) {
    final normalizedSecret = secret.trim();
    final parts = protectedValue.split('.');
    if (normalizedSecret.isEmpty || parts.length != 4 || parts.first != 'v1') {
      throw const FormatException('Formato de recuperacion invalido.');
    }

    final key = sha256.convert(utf8.encode(normalizedSecret)).bytes;
    final nonce = _base64UrlDecode(parts[1]);
    final cipherBytes = _base64UrlDecode(parts[2]);
    final macBytes = _base64UrlDecode(parts[3]);
    final expectedMac = Hmac(
      sha256,
      key,
    ).convert([...nonce, ...cipherBytes]).bytes;

    if (!_constantTimeBytesEquals(expectedMac, macBytes)) {
      throw const FormatException('La clave de recuperacion no coincide.');
    }

    final plainBytes = _xorWithRecoveryKeystream(cipherBytes, key, nonce);
    return utf8.decode(plainBytes);
  }

  static String hashToken(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  static List<int> _xorWithRecoveryKeystream(
    List<int> input,
    List<int> key,
    List<int> nonce,
  ) {
    final output = List<int>.filled(input.length, 0);
    var offset = 0;
    var counter = 0;

    while (offset < input.length) {
      final block = Hmac(sha256, key).convert([
        ...nonce,
        counter & 0xFF,
        (counter >> 8) & 0xFF,
        (counter >> 16) & 0xFF,
        (counter >> 24) & 0xFF,
      ]).bytes;

      for (
        var index = 0;
        index < block.length && offset < input.length;
        index++
      ) {
        output[offset] = input[offset] ^ block[index];
        offset++;
      }

      counter++;
    }

    return output;
  }

  static Digest _deriveDigest({
    required String password,
    required String salt,
    required int iterations,
  }) {
    List<int> bytes = List<int>.from(utf8.encode('$salt::$password'));
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);

    for (var round = 0; round < iterations; round++) {
      bytes = sha256.convert([
        ...bytes,
        ...passwordBytes,
        ...saltBytes,
        round & 0xFF,
        (round >> 8) & 0xFF,
        (round >> 16) & 0xFF,
        (round >> 24) & 0xFF,
      ]).bytes;
    }

    return Digest(bytes);
  }

  static String _generateSalt([int length = 16]) {
    final values = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static String _base64UrlEncode(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static List<int> _base64UrlDecode(String value) {
    final padding = (4 - value.length % 4) % 4;
    return base64Url.decode('$value${'=' * padding}');
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }

    var mismatch = 0;
    for (var index = 0; index < left.length; index++) {
      mismatch |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return mismatch == 0;
  }

  static bool _constantTimeBytesEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var mismatch = 0;
    for (var index = 0; index < left.length; index++) {
      mismatch |= left[index] ^ right[index];
    }
    return mismatch == 0;
  }
}
