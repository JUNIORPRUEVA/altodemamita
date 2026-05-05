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

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncQueueService service;
  late _FakeSyncConfigRepository configRepository;
  late _AckingSyncApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'products_delete_queue_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository();
    apiClient = _AckingSyncApiClient();
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
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('products_delete_queue_completes_without_fk_error_test', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 11, 0).toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-products-queue-1',
      'version': 1,
      'nombre': 'Cliente Cola',
      'cedula': '00113745624',
      'telefono': '8095553333',
      'direccion': 'Calle Cola',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-products-queue-1',
      'version': 3,
      'manzana_numero': 'B',
      'solar_numero': '05',
      'metros_cuadrados': 220,
      'precio_por_metro': 3200,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'last_modified_local': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusFailed,
    });

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-products-queue-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': 1,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 704000,
      'inicial_porcentaje': 10,
      'inicial_monto': 70400,
      'monto_inicial_requerido': 70400,
      'monto_inicial_pagado': 70400,
      'monto_inicial_pendiente': 0,
      'monto_apartado_minimo': null,
      'fecha_limite_inicial': null,
      'fecha_activacion': now,
      'saldo_financiado': 633600,
      'saldo_pendiente': 633600,
      'interes_mensual': 1,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await db.insert(DatabaseSchema.syncQueueTable, {
      'scope': 'products',
      'record_sync_id': 'lot-products-queue-1',
      'operation': 'delete',
      'payload_json':
          '{"sync_id":"lot-products-queue-1","deleted_at":"$now","version":3}',
      'created_at': now,
      'updated_at': now,
      'next_attempt_at': now,
      'last_error': 'FOREIGN KEY constraint failed',
      'attempt_count': 2,
    });

    final processed = await service.processQueue(includeDeferred: true);

    final queueRows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope = ? AND record_sync_id = ?',
      whereArgs: ['products', 'lot-products-queue-1'],
    );
    final lotRows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-products-queue-1'],
      limit: 1,
    );

    expect(processed, 1);
    expect(queueRows, isEmpty);
    expect(lotRows, hasLength(1));
    expect(lotRows.single['deleted_at'], isNotNull);
    expect(lotRows.single['sync_status'], DatabaseSchema.syncStatusSynced);
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
      deviceId: 'products-delete-test-device',
    );
  }
}

class _AckingSyncApiClient extends SyncApiClient {
  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    final records = recordsByScope[scope] ?? const [];
    return SyncUploadResponse(
      returnedRecordsByScope: {
        scope: records
            .map((record) => record.map((key, value) => MapEntry(key, value)))
            .toList(growable: false),
      },
    );
  }
}
