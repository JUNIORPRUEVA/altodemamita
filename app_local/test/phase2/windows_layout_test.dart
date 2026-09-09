import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  test('creates Phase 2 Windows storage layout under app support', () async {
    final root = await Directory.systemTemp.createTemp('phase2_paths_');
    addTearDown(() => root.delete(recursive: true));

    final appPaths = AppPaths(supportDirectory: root.path);
    await appPaths.ensureCriticalDirectories();

    expect(
      appPaths.cacheDatabasePath,
      path.join(root.path, 'data', 'cache', 'cache.db'),
    );
    expect(
      appPaths.outboxDatabasePath,
      path.join(root.path, 'data', 'outbox', 'outbox.db'),
    );
    expect(
      appPaths.deviceStateDatabasePath,
      path.join(root.path, 'data', 'state', 'device_state.db'),
    );

    for (final directory in [
      appPaths.dataCacheDirectory,
      appPaths.dataOutboxDirectory,
      appPaths.dataStateDirectory,
      appPaths.localBackupsDirectory,
      appPaths.migrationDirectory,
    ]) {
      expect(await Directory(directory).exists(), isTrue, reason: directory);
    }
  });
}
