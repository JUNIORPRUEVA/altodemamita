import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late _FakeSyncConfigRepository configRepository;
  late _RecordingSyncApiClient apiClient;
  late SyncQueueService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_queue_service_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository(
      settings: _buildSettings(isConfigured: true),
    );
    apiClient = _RecordingSyncApiClient(failingScopes: {'clients'});
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    for (final scope in [
      'clients',
      'products',
      'sellers',
      'sales',
      'installments',
      'payments',
    ]) {
      service.registerRepository(
        _FakeSyncRepository(scope, pendingSyncIds: const {}),
      );
    }
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('bloquea scopes dependientes cuando falla un scope padre', () async {
    await _insertQueuedRecord(appDatabase, scope: 'clients', syncId: 'c-1');
    await _insertQueuedRecord(appDatabase, scope: 'products', syncId: 'p-1');
    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 's-1');
    await _insertQueuedRecord(appDatabase, scope: 'payments', syncId: 'py-1');

    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    service.registerRepository(
      _FakeSyncRepository('clients', pendingSyncIds: {'c-1'}),
    );
    service.registerRepository(
      _FakeSyncRepository('products', pendingSyncIds: {'p-1'}),
    );
    service.registerRepository(
      _FakeSyncRepository('sellers', pendingSyncIds: const {}),
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'s-1'}),
    );
    service.registerRepository(
      _FakeSyncRepository('installments', pendingSyncIds: const {}),
    );
    service.registerRepository(
      _FakeSyncRepository('payments', pendingSyncIds: {'py-1'}),
    );

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 0);
    expect(apiClient.uploadedScopes, ['clients']);
    expect(queueRows['clients']?['attempt_count'], 1);
    expect(queueRows['products']?['attempt_count'], 0);
    expect(queueRows['sales']?['attempt_count'], 0);
    expect(queueRows['payments']?['attempt_count'], 0);
  });

  test('procesa vendedores como scope valido de sincronizacion', () async {
    apiClient = _RecordingSyncApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    for (final scope in [
      'clients',
      'products',
      'sales',
      'installments',
      'payments',
    ]) {
      service.registerRepository(
        _FakeSyncRepository(scope, pendingSyncIds: const {}),
      );
    }
    service.registerRepository(
      _FakeSyncRepository('sellers', pendingSyncIds: {'seller-1'}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'sellers', syncId: 'seller-1');

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 1);
    expect(apiClient.uploadedScopes, ['sellers']);
    expect(queueRows.containsKey('sellers'), isFalse);
  });

  test('no marca synced cuando la API responde sin ack del registro', () async {
    apiClient = _RecordingSyncApiClient(missingAckScopes: {'sales'});
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-no-ack'}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 'sale-no-ack');

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 0);
    expect(apiClient.uploadedScopes, ['sales']);
    expect(queueRows.containsKey('sales'), isTrue);
    expect(
      queueRows['sales']?['last_error'],
      contains('La API no confirmo todos los registros de la cola.'),
    );
  });

  test('elimina upserts huerfanos antes de sincronizar la cola', () async {
    apiClient = _RecordingSyncApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    service.registerRepository(
      _FakeSyncRepository('sellers', pendingSyncIds: const {}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'sellers', syncId: 'seller-stale');

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 0);
    expect(apiClient.uploadedScopes, isEmpty);
    expect(queueRows.containsKey('sellers'), isFalse);
  });

  test('elimina scopes no soportados de la cola', () async {
    apiClient = _RecordingSyncApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    service.registerRepository(
      _FakeSyncRepository('clients', pendingSyncIds: {'c-1'}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'usuarios', syncId: 'u-1');
    await _insertQueuedRecord(appDatabase, scope: 'clients', syncId: 'c-1');

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 1);
    expect(apiClient.uploadedScopes, ['clients']);
    expect(queueRows.containsKey('usuarios'), isFalse);
    expect(queueRows.containsKey('clients'), isFalse);
  });

  test('confirma scopes cuando la cola queda vacia tras sincronizar', () async {
    apiClient = _RecordingSyncApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-1'}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 'sale-1');

    await service.syncScopesNowOrThrow(
      const ['sales'],
      operationLabel: 'create-sale:test',
    );

    final queueRows = await _readQueueRows(appDatabase);
    expect(apiClient.uploadedScopes, ['sales']);
    expect(queueRows.containsKey('sales'), isFalse);
  });

  test('lanza pending exception cuando backend deja registros pendientes', () async {
    apiClient = _RecordingSyncApiClient(failingScopes: {'sales'});
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-1'}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 'sale-1');

    await expectLater(
      () => service.syncScopesNowOrThrow(
        const ['sales'],
        operationLabel: 'delete-sale:test',
      ),
      throwsA(isA<SyncOperationPendingException>()),
    );

    final queueRows = await _readQueueRows(appDatabase);
    expect(queueRows.containsKey('sales'), isTrue);
    expect(queueRows['sales']?['last_error'], contains('Fallo simulado'));
  });

  test('si esta offline deja la cola pendiente y no intenta enviar', () async {
    apiClient = _RecordingSyncApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => false,
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-offline'}),
    );

    await _insertQueuedRecord(
      appDatabase,
      scope: 'sales',
      syncId: 'sale-offline',
    );

    final processed = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processed, 0);
    expect(apiClient.uploadedScopes, isEmpty);
    expect(queueRows.containsKey('sales'), isTrue);
  });

  test('procesa la cola uno por uno en orden al reconectar', () async {
    apiClient = _RecordingSyncApiClient();
    var online = false;
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => online,
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-1', 'sale-2'}),
    );

    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 'sale-1');
    await _insertQueuedRecord(appDatabase, scope: 'sales', syncId: 'sale-2');

    final processedOffline = await service.processQueue();
    expect(processedOffline, 0);
    expect(apiClient.uploadedScopes, isEmpty);

    online = true;
    final processedOnline = await service.processQueue();
    final queueRows = await _readQueueRows(appDatabase);

    expect(processedOnline, 2);
    expect(apiClient.uploadedScopes, ['sales', 'sales']);
    expect(queueRows.containsKey('sales'), isFalse);
  });

  test('conserva solo el ultimo estado create-update-delete tras volver internet', () async {
    apiClient = _RecordingSyncApiClient();
    var online = false;
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => online,
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-final'}),
    );

    await _insertQueuedRecord(
      appDatabase,
      scope: 'sales',
      syncId: 'sale-final',
      payloadJson: '{"sync_id":"sale-final","status":"created"}',
    );
    await _insertQueuedRecord(
      appDatabase,
      scope: 'sales',
      syncId: 'sale-final',
      payloadJson: '{"sync_id":"sale-final","status":"updated"}',
    );
    await _insertQueuedRecord(
      appDatabase,
      scope: 'sales',
      syncId: 'sale-final',
      operation: 'delete',
      payloadJson:
          '{"sync_id":"sale-final","status":"deleted","deleted_at":"2026-04-23T12:00:00.000Z"}',
    );

    final processedOffline = await service.processQueue();
    expect(processedOffline, 0);

    online = true;
    final processedOnline = await service.processQueue();

    expect(processedOnline, 1);
    expect(apiClient.uploadedScopes, ['sales']);
    expect(apiClient.uploadedPayloads, hasLength(1));
    expect(apiClient.uploadedPayloads.single['status'], 'deleted');
    expect(apiClient.uploadedPayloads.single['deleted_at'], isNotNull);
  });

  test('reintenta automaticamente al recibir reconexion de connectivity_plus', () async {
    apiClient = _RecordingSyncApiClient();
    var online = false;
    final connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
    addTearDown(connectivityController.close);

    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => online,
      connectivityChanges: connectivityController.stream,
    );
    service.registerRepository(
      _FakeSyncRepository('sales', pendingSyncIds: {'sale-reconnect'}),
    );

    await _insertQueuedRecord(
      appDatabase,
      scope: 'sales',
      syncId: 'sale-reconnect',
    );

    final processedOffline = await service.processQueue();
    expect(processedOffline, 0);
    expect(apiClient.uploadedScopes, isEmpty);

    await service.start();
    online = true;
    connectivityController.add(const [ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final queueRows = await _readQueueRows(appDatabase);
    expect(apiClient.uploadedScopes, contains('sales'));
    expect(queueRows.containsKey('sales'), isFalse);
  });
}

SyncSettings _buildSettings({required bool isConfigured}) {
  return SyncSettings(
    baseUrl: isConfigured ? 'https://sync.example.com' : '',
    jwtToken: isConfigured ? 'token' : '',
    queueRetryInterval: const Duration(seconds: 10),
    realtimePollingInterval: const Duration(seconds: 5),
    conflictStrategy: SyncConflictStrategy.manual,
    deviceId: 'test-device',
  );
}

Future<void> _insertQueuedRecord(
  AppDatabase appDatabase, {
  required String scope,
  required String syncId,
  String operation = 'upsert',
  String? payloadJson,
}) async {
  final db = await appDatabase.database;
  final now = DateTime.now().toIso8601String();

  final resolvedPayloadJson = payloadJson ?? switch (scope) {
    'clients' =>
      // Must include required client fields to avoid production guards.
      // 00113745624 is checksum-valid under DominicanValidators.
      '{"sync_id":"$syncId","full_name":"Juan Perez","document_id":"00113745624"}',
    _ => '{"sync_id":"$syncId"}',
  };

  final existing = await db.query(
    DatabaseSchema.syncQueueTable,
    columns: ['id', 'created_at'],
    where: 'scope = ? AND record_sync_id = ?',
    whereArgs: [scope, syncId],
    limit: 1,
  );

  if (existing.isEmpty) {
    await db.insert(DatabaseSchema.syncQueueTable, {
      'scope': scope,
      'record_sync_id': syncId,
      'operation': operation,
      'payload_json': resolvedPayloadJson,
      'created_at': now,
      'updated_at': now,
      'next_attempt_at': now,
      'last_error': null,
      'attempt_count': 0,
    });
    return;
  }

  await db.update(
    DatabaseSchema.syncQueueTable,
    {
      'operation': operation,
      'payload_json': resolvedPayloadJson,
      'updated_at': now,
      'next_attempt_at': now,
      'last_error': null,
    },
    where: 'scope = ? AND record_sync_id = ?',
    whereArgs: [scope, syncId],
  );
}

Future<Map<String, Map<String, Object?>>> _readQueueRows(
  AppDatabase appDatabase,
) async {
  final db = await appDatabase.database;
  final rows = await db.query(DatabaseSchema.syncQueueTable);
  return {for (final row in rows) row['scope']! as String: row};
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  _FakeSyncConfigRepository({required SyncSettings settings})
    : _settings = settings;

  SyncSettings _settings;

  set settings(SyncSettings value) {
    _settings = value;
  }

  @override
  Future<SyncSettings> loadSettings() async => _settings;
}

class _RecordingSyncApiClient extends SyncApiClient {
  _RecordingSyncApiClient({
    this.failingScopes = const {},
    this.missingAckScopes = const {},
  });

  final Set<String> failingScopes;
  final Set<String> missingAckScopes;
  final List<String> uploadedScopes = [];
  final List<Map<String, Object?>> uploadedPayloads = [];

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    uploadedScopes.add(scope);
    uploadedPayloads.addAll(recordsByScope.values.expand((items) => items));
    if (failingScopes.contains(scope)) {
      throw HttpException('Fallo simulado para $scope');
    }

    return SyncUploadResponse(
      returnedRecordsByScope: {
        scope: missingAckScopes.contains(scope)
            ? const []
            : recordsByScope.values
                  .expand((items) => items)
                  .map(
                    (item) => item.map(
                      (key, value) => MapEntry(key, value),
                    ),
                  )
                  .toList(growable: false),
      },
    );
  }
}

class _FakeSyncRepository implements SyncRepository {
  _FakeSyncRepository(this.scope, {required Set<String> pendingSyncIds})
    : _pendingSyncIds = pendingSyncIds;

  @override
  final String scope;
  final Set<String> _pendingSyncIds;

  @override
  String get downloadPath => '/sync/$scope';

  @override
  String get uploadPath => '/sync/$scope';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    return _pendingSyncIds
        .map((syncId) => {'sync_id': syncId})
        .toList(growable: false);
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {}

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {}

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}
