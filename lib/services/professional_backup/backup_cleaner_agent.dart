import 'dart:io';

import 'package:path/path.dart' as path;

class BackupCleanerAgent {
  const BackupCleanerAgent();

  Future<void> enforceLocalRetention({
    required Directory directory,
    required int keepLast,
    String filePrefix = 'backup_local_',
  }) async {
    if (!await directory.exists()) {
      return;
    }

    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final base = path.basename(entity.path);
      if (!base.startsWith(filePrefix) || !base.endsWith('.db')) continue;
      files.add(entity);
    }

    if (files.length <= keepLast) {
      return;
    }

    files.sort((a, b) {
      final left = path.basename(a.path);
      final right = path.basename(b.path);
      return left.compareTo(right);
    });

    final toDelete = files.length - keepLast;
    for (var i = 0; i < toDelete; i++) {
      try {
        await files[i].delete();
      } catch (_) {
        // Best effort.
      }
    }
  }
}
