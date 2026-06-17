import 'dart:io';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'delete_409_conflict_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    configRepository = _FakeSyncConfigRepository();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('delete_409_marks_conflict_and_stops_retry_test', () async {
    final db = await appDatabase.database;
    await _seedSalesGraph(db, now: DateTime(2026, 5, 2, 9, 0).toIso8601String());
    await _insertQueue(
      db,
      scope: 'sales',
      syncId: 'sale-409',
      operation: 'delete',
      payloadJson:
          '{"sync_id":"sale-409","deleted_at":"2026-05-02T09:00:00.000Z","version":2}',
    );

    final apiClient = _ConflictSyncApiClient(
      conflictScopes: {'sales': 'server-sale-id'},
    );
    final service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    addTearDown(service.dispose);
    service.registerRepository(
      _TableSyncRepository(
        appDatabase: appDatabase,
        scope: 'sales',
        tableName: DatabaseSchema.salesTable,
      ),
    );

    await service.processQueue();
    await service.processQueue();

    final queueRows = await db.query(DatabaseSchema.syncQueueTable);
    final salesRow = (await db.query(
      DatabaseSchema.salesTable,
      columns: ['sync_status'],
      where: 'sync_id = ?',
      whereArgs: ['sale-409'],
      limit: 1,
    )).single;

    expect(queueRows, isEmpty);
    expect(salesRow['sync_status'], DatabaseSchema.syncStatusConflict);
    expect(apiClient.callsByScope['sales'], 1);
  });

  test('sales_409_conflict_not_retried_in_loop_test', () async {
    final db = await appDatabase.database;
    await _seedSalesGraph(db, now: DateTime(2026, 5, 2, 10, 0).toIso8601String());
    await _insertQueue(
      db,
      scope: 'sales',
      syncId: 'sale-loop-409',
      operation: 'delete',
      payloadJson:
          '{"sync_id":"sale-loop-409","deleted_at":"2026-05-02T10:00:00.000Z","version":2}',
    );

    final apiClient = _ConflictSyncApiClient(
      conflictScopes: {'sales': 'sale-loop-409'},
    );
    final service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    addTearDown(service.dispose);
    service.registerRepository(
      _TableSyncRepository(
        appDatabase: appDatabase,
        scope: 'sales',
        tableName: DatabaseSchema.salesTable,
      ),
    );

    await service.processQueue();
    await service.processQueue();
    await service.processQueue();

    expect(apiClient.callsByScope['sales'], 1);
  });

  test('installments_409_conflict_not_retried_in_loop_test', () async {
    final db = await appDatabase.database;
    await _seedSalesGraph(db, now: DateTime(2026, 5, 2, 11, 0).toIso8601String());
    await db.insert(DatabaseSchema.installmentsTable, {
      'sync_id': 'installment-409',
      'version': 1,
      'venta_id': 1,
      'numero_cuota': 1,
      'fecha_vencimiento': '2026-06-02T11:00:00.000Z',
      'saldo_inicial': 10000,
      'capital_cuota': 8000,
      'interes_cuota': 2000,
      'monto_cuota': 10000,
      'monto_pagado': 0,
      'capital_pagado': 0,
      'interes_pagado': 0,
      'saldo_final': 10000,
      'estado': 'pendiente',
      'fecha_creacion': '2026-05-02T11:00:00.000Z',
      'fecha_actualizacion': '2026-05-02T11:00:00.000Z',
      'sync_status': DatabaseSchema.syncStatusPendingDelete,
      'deleted_at': '2026-05-02T11:00:00.000Z',
    });
    await _insertQueue(
      db,
      scope: 'installments',
      syncId: 'installment-409',
      operation: 'delete',
      payloadJson:
          '{"sync_id":"installment-409","deleted_at":"2026-05-02T11:00:00.000Z","version":2}',
    );

    final apiClient = _ConflictSyncApiClient(
      conflictScopes: {'installments': 'installment-409'},
    );
    final service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    addTearDown(service.dispose);
    service.registerRepository(
      _TableSyncRepository(
        appDatabase: appDatabase,
        scope: 'installments',
        tableName: DatabaseSchema.installmentsTable,
      ),
    );

    await service.processQueue();
    await service.processQueue();

    final queueRows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope = ?',
      whereArgs: ['installments'],
    );
    final installmentRow = (await db.query(
      DatabaseSchema.installmentsTable,
      columns: ['sync_status'],
      where: 'sync_id = ?',
      whereArgs: ['installment-409'],
      limit: 1,
    )).single;

    expect(queueRows, isEmpty);
    expect(installmentRow['sync_status'], DatabaseSchema.syncStatusConflict);
    expect(apiClient.callsByScope['installments'], 1);
  });

  test('delete_401_pauses_sync_without_spam_test', () async {
    final db = await appDatabase.database;
    await _seedSalesGraph(db, now: DateTime(2026, 5, 2, 12, 0).toIso8601String());
    await _insertQueue(
      db,
      scope: 'sales',
      syncId: 'sale-auth-401',
      operation: 'delete',
      payloadJson:
          '{"sync_id":"sale-auth-401","deleted_at":"2026-05-02T12:00:00.000Z","version":2}',
    );

    final apiClient = _UnauthorizedSyncApiClient();
    final service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    addTearDown(service.dispose);
    service.registerRepository(
      _TableSyncRepository(
        appDatabase: appDatabase,
        scope: 'sales',
        tableName: DatabaseSchema.salesTable,
      ),
    );

    await service.processQueue();
    await service.processQueue();

    final queueRow = (await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope = ? AND record_sync_id = ?',
      whereArgs: ['sales', 'sale-auth-401'],
      limit: 1,
    )).single;

    expect(apiClient.callsByScope['sales'], 1);
    expect(queueRow['last_error'].toString(), contains('AUTH_REQUIRED'));
    final nextAttemptAt = DateTime.parse(queueRow['next_attempt_at'] as String);
    expect(nextAttemptAt.isAfter(DateTime.now().add(const Duration(hours: 5))), isTrue);
  });
}

Future<void> _seedSalesGraph(dynamic db, {required String now}) async {
  final clientId = await db.insert(DatabaseSchema.clientsTable, {
    'sync_id': 'client-409',
    'version': 1,
    'nombre': 'Cliente 409',
    'cedula': '00113745624',
    'telefono': '8095550000',
    'direccion': 'Direccion',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  final lotId = await db.insert(DatabaseSchema.lotsTable, {
    'sync_id': 'product-409',
    'version': 1,
    'manzana_numero': 'A',
    'solar_numero': '9',
    'metros_cuadrados': 140,
    'precio_por_metro': 2200,
    'estado': 'vendido',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });

  await db.insert(DatabaseSchema.salesTable, {
    'id': 1,
    'sync_id': 'sale-409',
    'version': 1,
    'cliente_id': clientId,
    'solar_id': lotId,
    'usuario_id': 1,
    'vendedor_id': null,
    'fecha_venta': now,
    'precio_venta': 500000,
    'inicial_porcentaje': 10,
    'inicial_monto': 50000,
    'monto_inicial_requerido': 50000,
    'monto_inicial_pagado': 50000,
    'monto_inicial_pendiente': 0,
    'monto_apartado_minimo': null,
    'fecha_limite_inicial': null,
    'fecha_activacion': now,
    'saldo_financiado': 450000,
    'saldo_pendiente': 450000,
    'interes_mensual': 1,
    'cantidad_cuotas': 12,
    'estado': 'activa',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusPendingDelete,
    'deleted_at': now,
  });

  await db.insert(DatabaseSchema.salesTable, {
    'sync_id': 'sale-loop-409',
    'version': 1,
    'cliente_id': clientId,
    'solar_id': lotId,
    'usuario_id': 1,
    'vendedor_id': null,
    'fecha_venta': now,
    'precio_venta': 300000,
    'inicial_porcentaje': 10,
    'inicial_monto': 30000,
    'monto_inicial_requerido': 30000,
    'monto_inicial_pagado': 30000,
    'monto_inicial_pendiente': 0,
    'monto_apartado_minimo': null,
    'fecha_limite_inicial': null,
    'fecha_activacion': now,
    'saldo_financiado': 270000,
    'saldo_pendiente': 270000,
    'interes_mensual': 1,
    'cantidad_cuotas': 12,
    'estado': 'activa',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusPendingDelete,
    'deleted_at': now,
  });

  await db.insert(DatabaseSchema.salesTable, {
    'sync_id': 'sale-auth-401',
    'version': 1,
    'cliente_id': clientId,
    'solar_id': lotId,
    'usuario_id': 1,
    'vendedor_id': null,
    'fecha_venta': now,
    'precio_venta': 200000,
    'inicial_porcentaje': 10,
    'inicial_monto': 20000,
    'monto_inicial_requerido': 20000,
    'monto_inicial_pagado': 20000,
    'monto_inicial_pendiente': 0,
    'monto_apartado_minimo': null,
    'fecha_limite_inicial': null,
    'fecha_activacion': now,
    'saldo_financiado': 180000,
    'saldo_pendiente': 180000,
    'interes_mensual': 1,
    'cantidad_cuotas': 12,
    'estado': 'activa',
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'sync_status': DatabaseSchema.syncStatusPendingDelete,
    'deleted_at': now,
  });
}

Future<void> _insertQueue(
  dynamic db, {
  required String scope,
  required String syncId,
  required String operation,
  required String payloadJson,
}) async {
  final now = DateTime.now().toIso8601String();
  await db.insert(DatabaseSchema.syncQueueTable, {
    'scope': scope,
    'record_sync_id': syncId,
    'operation': operation,
    'payload_json': payloadJson,
    'attempt_count': 0,
    'last_error': null,
    'next_attempt_at': now,
    'created_at': now,
    'updated_at': now,
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://sync.example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 5),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'desktop-test',
    );
  }
}

class _ConflictSyncApiClient extends SyncApiClient {
  _ConflictSyncApiClient({required this.conflictScopes});

  final Map<String, String> conflictScopes;
  final Map<String, int> callsByScope = {};

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    callsByScope.update(scope, (value) => value + 1, ifAbsent: () => 1);

    final conflictId = conflictScopes[scope];
    if (conflictId != null) {
      throw SyncConflictException(
        message: 'Conflicto de sincronizacion: el servidor tiene una version mas reciente.',
        scope: scope,
        strategy: SyncConflictStrategy.manual,
        conflicts: [
          SyncConflictItem(
            scope: scope,
            recordSyncId: conflictId,
            localVersion: 1,
            serverVersion: 2,
            localRecord: {'sync_id': conflictId},
            serverRecord: null,
            message: 'manual conflict',
          ),
        ],
        serverUri: Uri.parse('https://sync.example.com/sync/upload'),
      );
    }

    return const SyncUploadResponse(returnedRecordsByScope: {});
  }
}

class _UnauthorizedSyncApiClient extends SyncApiClient {
  final Map<String, int> callsByScope = {};

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    callsByScope.update(scope, (value) => value + 1, ifAbsent: () => 1);
    throw HttpException('El backend rechazo la sesion (401). Unauthorized');
  }
}

class _TableSyncRepository implements SyncRepository {
  _TableSyncRepository({
    required this.appDatabase,
    required this.scope,
    required this.tableName,
  });

  final AppDatabase appDatabase;
  @override
  final String scope;
  final String tableName;

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/download';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async => const [];

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    final ids = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final db = await appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE $tableName SET sync_status = ? WHERE sync_id IN ($placeholders)',
      [DatabaseSchema.syncStatusConflict, ...ids],
    );
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    final ids = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final db = await appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE $tableName SET sync_status = ? WHERE sync_id IN ($placeholders)',
      [DatabaseSchema.syncStatusSynced, ...ids],
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}
