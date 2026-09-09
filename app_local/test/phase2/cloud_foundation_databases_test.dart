import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/cloud_foundation/cache_repository.dart';
import 'package:sistema_solares/core/cloud_foundation/cloud_foundation_databases.dart';
import 'package:sistema_solares/core/cloud_foundation/device_state_repository.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  test('opens separate cache, outbox, and device state databases', () async {
    final root = await Directory.systemTemp.createTemp('phase2_dbs_');
    addTearDown(() => root.delete(recursive: true));

    final databases = CloudFoundationDatabases(
      appPaths: AppPaths(supportDirectory: root.path),
    );
    addTearDown(databases.close);

    await databases.initialize();

    final cache = await databases.cache;
    final outbox = await databases.outbox;
    final deviceState = await databases.deviceState;

    expect(await _hasTable(cache, 'cache_records'), isTrue);
    expect(await _hasTable(cache, 'cache_metadata'), isTrue);
    expect(await _hasTable(outbox, 'outbox_operations'), isTrue);
    expect(await _hasTable(deviceState, 'device_state'), isTrue);
    expect(await _hasTable(deviceState, 'sync_cursors'), isTrue);

    await CacheRepository(cache).upsertRecord(
      entity: 'sales',
      id: 'sale-1',
      payload: {'status': 'pending'},
      status: 'PENDING',
    );
    await DeviceStateRepository(deviceState).put('device_id', 'device-1');
    await databases.deleteCacheOnlyForRebuild();

    expect(await File(databases.appPaths.cacheDatabasePath).exists(), isFalse);
    expect(await File(databases.appPaths.outboxDatabasePath).exists(), isTrue);
    expect(
      await File(databases.appPaths.deviceStateDatabasePath).exists(),
      isTrue,
    );
  });
}

Future<bool> _hasTable(dynamic db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}
