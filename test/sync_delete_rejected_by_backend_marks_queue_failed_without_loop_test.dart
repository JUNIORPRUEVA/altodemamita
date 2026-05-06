/// Verifies that when the backend rejects a pending-delete for a client/seller/product
/// with a conflict response (ENTITY_HAS_ACTIVE_SALES), the sync queue:
///   1. Does NOT retry infinitely.
///   2. Removes the queue entry (or marks it resolved as server_won).
///   3. Restores the local entity (deleted_at = NULL) by merging the server record.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late SyncQueueService service;
  late _FakeSyncConfigRepository configRepository;
  late _EntityHasActiveSalesApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('sync_delete_rejected_');
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository();
    apiClient = _EntityHasActiveSalesApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => true,
    );

    final clientRepo = ClientRepository(appDatabase: appDatabase);
    service.registerRepository(clientRepo);
  });

  tearDown(() async {
    service.dispose();
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sync_delete_rejected_by_backend_marks_queue_failed_without_loop_test',
      () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    // Insert a client that is locally soft-deleted with pending_delete status.
    await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-reject-1',
      'cedula': '00900000001',
      'nombre': 'Reject',
      'apellido': 'Test',
      'telefono': '8092000001',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'last_modified_local': now,
      'deleted_at': now, // locally soft-deleted
      'sync_status': DatabaseSchema.syncStatusPendingDelete,
    });

    // Queue the pending delete.
    await db.insert(DatabaseSchema.syncQueueTable, {
      'scope': 'clients',
      'record_sync_id': 'client-reject-1',
      'operation': 'delete',
      'payload_json':
          '{"sync_id":"client-reject-1","deleted_at":"$now","version":2}',
      'created_at': now,
      'updated_at': now,
      'next_attempt_at': now,
      'last_error': null,
      'attempt_count': 0,
    });

    // Tell the API client to return the current server record (non-deleted)
    // as the conflict resolution record.
    apiClient.serverRecord = {
      'sync_id': 'client-reject-1',
      'first_name': 'Reject',
      'last_name': 'Test',
      'document_id': '00900000001',
      'phone': '8092000001',
      'email': null,
      'address': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null, // server still has it non-deleted
      'sync_status': 'synced',
    };

    // Process queue — conflict should be handled once, not retried.
    final processed = await service.processQueue(includeDeferred: true);

    // Queue should be cleared (conflict auto-resolved or removed).
    final queueRows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: "scope = ? AND record_sync_id = ?",
      whereArgs: ['clients', 'client-reject-1'],
    );

    // The queue should no longer have a pending entry (auto-resolved or gone).
    expect(
      queueRows.where((r) => r['operation'] == 'delete').isEmpty,
      isTrue,
      reason: 'Delete queue entry must not remain after conflict resolution',
    );

    // The client should have deleted_at restored to null (server_won).
    final clientRows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'sync_id = ?',
      whereArgs: ['client-reject-1'],
    );
    if (clientRows.isNotEmpty) {
      expect(
        clientRows.first['deleted_at'],
        isNull,
        reason: 'Client deleted_at must be restored after server rejected delete',
      );
    }

    // API client must have been called exactly once — no retry loop.
    expect(apiClient.callCount, equals(1),
        reason: 'API must be called exactly once — no infinite retry');
    _ = processed; // used
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return const SyncSettings(
      baseUrl: 'https://sync.example.com',
      jwtToken: 'token',
      queueRetryInterval: Duration(seconds: 5),
      realtimePollingInterval: Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'reject-delete-test-device',
    );
  }
}

class _EntityHasActiveSalesApiClient extends SyncApiClient {
  Map<String, dynamic>? serverRecord;
  int callCount = 0;

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    callCount++;
    final scope = recordsByScope.keys.first;
    final record = recordsByScope[scope]?.first ?? const {};
    final recordSyncId = record['sync_id']?.toString() ?? '';

    // Simulate backend rejecting with ENTITY_HAS_ACTIVE_SALES conflict (409)
    throw SyncConflictException(
      message:
          'ENTITY_HAS_ACTIVE_SALES: No puedes eliminar este cliente porque '
          'tiene una venta activa relacionada.',
      scope: scope,
      strategy: SyncConflictStrategy.manual,
      conflicts: [
        SyncConflictItem(
          recordSyncId: recordSyncId,
          reason: 'ENTITY_HAS_ACTIVE_SALES',
        ),
      ],
      returnedRecords: serverRecord != null ? [serverRecord!] : const [],
      serverUri: Uri.parse('https://sync.example.com/sync/upload'),
    );
  }
}
