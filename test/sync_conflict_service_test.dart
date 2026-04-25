import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncConflictService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_conflict_service_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    service = SyncConflictService(appDatabase: appDatabase);
  });

  tearDown(() async {
    service.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'logUploadConflicts upsert evita duplicar conflictos abiertos',
    () async {
      final exception = SyncConflictException(
        message: 'conflict',
        scope: 'sales',
        strategy: SyncConflictStrategy.manual,
        conflicts: const [],
        serverUri: Uri.parse('https://sync.example.com/sync/upload'),
        returnedRecords: const [],
      );

      final queuedItems = [
        SyncQueueItem(
          id: 1,
          scope: 'sales',
          recordSyncId: 'sale-1',
          operation: 'upsert',
          payload: const {'sync_id': 'sale-1', 'version': 2},
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ];

      await service.logUploadConflicts(
        scope: 'sales',
        queuedItems: queuedItems,
        exception: exception,
      );
      await service.logUploadConflicts(
        scope: 'sales',
        queuedItems: queuedItems,
        exception: exception,
      );

      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.conflictLogsTable,
        where: 'scope = ? AND record_sync_id = ? AND resolved_at IS NULL',
        whereArgs: ['sales', 'sale-1'],
      );

      expect(rows, hasLength(1));
    },
  );

  test(
    'logUploadConflicts inserta una nueva fila si el conflicto anterior ya fue resuelto',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();

      await db.insert(DatabaseSchema.conflictLogsTable, {
        'scope': 'sales',
        'record_sync_id': 'sale-1',
        'local_version': 1,
        'server_version': 1,
        'strategy': 'manual',
        'local_payload_json': null,
        'server_payload_json': null,
        'message': 'old',
        'resolution': 'synced',
        'detected_at': now,
        'resolved_at': now,
      });

      final exception = SyncConflictException(
        message: 'conflict-new',
        scope: 'sales',
        strategy: SyncConflictStrategy.manual,
        conflicts: const [],
        serverUri: Uri.parse('https://sync.example.com/sync/upload'),
        returnedRecords: const [],
      );

      await service.logUploadConflicts(
        scope: 'sales',
        queuedItems: [
          SyncQueueItem(
            id: 1,
            scope: 'sales',
            recordSyncId: 'sale-1',
            operation: 'upsert',
            payload: const {'sync_id': 'sale-1', 'version': 3},
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
        exception: exception,
      );

      final rows = await db.query(
        DatabaseSchema.conflictLogsTable,
        where: 'scope = ? AND record_sync_id = ?',
        whereArgs: ['sales', 'sale-1'],
        orderBy: 'id ASC',
      );

      expect(rows.length, 2);
      expect(rows.where((row) => row['resolved_at'] == null).length, 1);
    },
  );
}
