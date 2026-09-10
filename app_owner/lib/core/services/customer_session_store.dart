import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

class CustomerSessionStore {
  const CustomerSessionStore();

  static const _fileName = 'customer_session.json';

  Future<AuthSession?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final session = AuthSession.fromJson(decoded.cast<String, dynamic>());
      return session.accessToken.trim().isEmpty ? null : session;
    } catch (error) {
      if (kDebugMode) debugPrint('[CustomerSession] read failed: $error');
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()), flush: true);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
