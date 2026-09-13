import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/owner_snapshot.dart';

class OwnerSnapshotCache {
  const OwnerSnapshotCache();

  static const _fileName = 'customer_snapshot_cache.json';

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

  /// Removes the cached snapshot from the device.
  ///
  /// Required on logout and before a different customer signs in: the cache is
  /// not authoritative and must never surface a previous customer's business
  /// data to another session on the same device.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[OwnerCache] clear failed: $error');
      }
    }
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
