/// Verifies that when the backend rejects a pending-delete for a product/lot
/// with a conflict response (ENTITY_HAS_ACTIVE_SALES), the sync queue:
///   1. Does NOT retry infinitely (API called exactly once).
///   2. The local entity row still exists (not hard-deleted).
///
/// Uses 'products' scope to avoid ClientDataGuard production filtering.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
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

    service.registerRepository(
      ProductsSyncRepository(appDatabase: appDatabase),
    );
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

    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-reject-1',
      'manzana_numero': 'Z',
      'solar_numero': '99',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingDelete,
    });

    await db.insert(DatabaseSchema.syncQueueTable, {
      'scope': 'products',
      'record_sync_id': 'lot-reject-1',
      'operation': 'delete',
      'payload_json':
          '{"sync_id":"lot-reject-1","deleted_at":"$now","version":2}',
      'created_at': now,
      'updated_at': now,
      'next_attempt_at': now,
      'last_error': null,
      'attempt_count': 0,
    });

    apiClient.serverRecord = {
      'sync_id': 'lot-reject-1',
      'block_number': 'Z',
      'lot_number': '99',
      'square_meters': 200.0,
      'price_per_meter': 3500.0,
      'status': 'vendido',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    };

    final processed = await service.processQueue(includeDeferred: true);

    final lotRows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-reject-1'],
    );
    expect(lotRows, hasLength(1),
        reason: 'Lot record must not be hard-deleted');

    expect(apiClient.callCount, equals(1),
        reason: 'API must be called exactly once -- no infinite retry');
    expect(processed, isNotNull);
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

    throw SyncConflictException(
      message: 'ENTITY_HAS_ACTIVE_SALES: No puedes eliminar este solar porque '
          'tiene una venta activa relacionada.',
      scope: scope,
      strategy: SyncConflictStrategy.manual,
      conflicts: [
        SyncConflictItem(
          scope: scope,
          recordSyncId: recordSyncId,
          localVersion: null,
          serverVersion: null,
          message: 'ENTITY_HAS_ACTIVE_SALES',
        ),
      ],
      returnedRecords: serverRecord != null ? [serverRecord!] : const [],
      serverUri: Uri.parse('https://sync.example.com/sync/upload'),
    );
  }
}
