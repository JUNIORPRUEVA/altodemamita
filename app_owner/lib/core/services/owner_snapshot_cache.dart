import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/owner_snapshot.dart';

class OwnerSnapshotCache {
  const OwnerSnapshotCache();

  static const _fileName = 'owner_snapshot_cache.json';

  Future<OwnerSnapshot?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OwnerSnapshot.fromJson(decoded.cast<String, dynamic>());
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[OwnerCache] read failed: $error');
      }
      return null;
    }
  }

  Future<void> write(OwnerSnapshot snapshot) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(snapshot.toJson()), flush: false);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[OwnerCache] write failed: $error');
      }
    }
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
