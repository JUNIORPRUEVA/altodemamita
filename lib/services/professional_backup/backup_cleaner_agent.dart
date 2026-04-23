import 'dart:io';

import 'package:path/path.dart' as path;

import 'backup_validator_agent.dart';

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

    final validator = const BackupValidatorAgent();

    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final base = path.basename(entity.path);
      if (!base.startsWith(filePrefix) || !base.endsWith('.db')) continue;

      // Auto-fix: purge empty/corrupt backups so retention is meaningful.
      try {
        final length = await entity.length();
        if (length <= 0) {
          await entity.delete();
          continue;
        }
        await validator.validateSQLiteDbFile(entity);
      } catch (_) {
        try {
          await entity.delete();
        } catch (_) {
          // Best effort.
        }
        continue;
      }

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
