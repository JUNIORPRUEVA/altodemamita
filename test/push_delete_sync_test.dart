import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncQueueService syncQueueService;
  late _FakeSyncConfigRepository configRepository;
  late _DeleteAckSyncApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'push_delete_sync_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository();
    apiClient = _DeleteAckSyncApiClient();
    syncQueueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => true,
    );
    syncQueueService.registerRepository(
      SalesSyncRepository(appDatabase: appDatabase),
    );
  });

  tearDown(() async {
    await _waitUntil(() async => !syncQueueService.state.isProcessing);
    syncQueueService.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('purga localmente una venta soft-deleted cuando la nube confirma el delete', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 4, 24, 16, 0).toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-push-delete-1',
      'version': 1,
      'nombre': 'Cliente Delete',
      'cedula': '001-0000123-4',
      'telefono': '8095551234',
      'direccion': 'Calle Delete',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'product-push-delete-1',
      'version': 1,
      'manzana_numero': 'B',
      'solar_numero': '08',
      'metros_cuadrados': 180,
      'precio_por_metro': 3000,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-push-delete-1',
      'version': 2,
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
      'estado': 'cancelada',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPending,
    });

    await syncQueueService.refreshScope('sales');
    await _waitUntil(() async {
      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.salesTable,
        where: 'sync_id = ?',
        whereArgs: ['sale-push-delete-1'],
      );
      return apiClient.deletedSyncIds.contains('sale-push-delete-1') &&
          rows.isEmpty &&
          await syncQueueService.pendingCount() == 0 &&
          !syncQueueService.state.isProcessing;
    });

    expect(apiClient.deletedSyncIds, ['sale-push-delete-1']);

    final remainingRows = await db.query(
      DatabaseSchema.salesTable,
      where: 'sync_id = ?',
      whereArgs: ['sale-push-delete-1'],
    );
    expect(remainingRows, isEmpty);

    final queuedRows = await db.query(
      DatabaseSchema.syncQueueTable,
      where: 'scope = ?',
      whereArgs: ['sales'],
    );
    expect(queuedRows, isEmpty);
  });
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('La condicion de la prueba no se cumplio a tiempo.');
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://sync.example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 10),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'push-delete-test-device',
    );
  }
}

class _DeleteAckSyncApiClient extends SyncApiClient {
  final List<String> deletedSyncIds = [];

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final sales = recordsByScope['sales'] ?? const [];
    for (final record in sales) {
      final syncId = record['sync_id']?.toString().trim() ?? '';
      final deletedAt = record['deleted_at']?.toString().trim() ?? '';
      if (syncId.isNotEmpty && deletedAt.isNotEmpty) {
        deletedSyncIds.add(syncId);
      }
    }

    return SyncUploadResponse(
      returnedRecordsByScope: {
        'sales': sales
            .map(
              (record) => record.map(
                (key, value) => MapEntry(key, value),
              ),
            )
            .toList(growable: false),
      },
    );
  }
}