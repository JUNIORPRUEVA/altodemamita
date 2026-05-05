import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncConfigRepository configRepository;
  late _SalesConflictApiClient apiClient;
  late SyncQueueService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_queue_sales_conflict_blocks_installments_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    configRepository = SyncConfigRepository();
    apiClient = _SalesConflictApiClient();
    service = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );

    service.registerRepository(
      ClientRepository(appDatabase: appDatabase, syncQueueService: service),
    );
    service.registerRepository(ProductsSyncRepository(appDatabase: appDatabase));
    service.registerRepository(SalesSyncRepository(appDatabase: appDatabase));
    service.registerRepository(
      InstallmentsSyncRepository(appDatabase: appDatabase),
    );

    await configRepository.saveJwtToken('jwt-test-token');
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'cuando sales entra en conflicto manual no sube installments dependientes y los rehidrata desde servidor',
    () async {
      final db = await appDatabase.database;
      final createdAt = DateTime(2026, 5, 5, 12, 0).toIso8601String();
      final serverUpdatedAt = DateTime(2026, 5, 5, 12, 5).toIso8601String();
      final saleSyncId = 'sale-conflict-parent-1';
      final installmentSyncId = 'installment-conflict-child-1';

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-conflict-parent-1',
        'version': 1,
        'nombre': 'Cliente Padre',
        'cedula': '001-0000666-1',
        'telefono': '8095556661',
        'direccion': 'Calle Padre',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-conflict-parent-1',
        'version': 1,
        'manzana_numero': 'C',
        'solar_numero': '15',
        'metros_cuadrados': 120,
        'precio_por_metro': 3200,
        'estado': 'vendido',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': saleSyncId,
        'id_remote': 'remote-sale-conflict-parent-1',
        'version': 10,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': createdAt,
        'precio_venta': 384000,
        'inicial_porcentaje': 10,
        'inicial_monto': 38400,
        'monto_inicial_requerido': 38400,
        'monto_inicial_pagado': 38400,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': createdAt,
        'saldo_financiado': 345600,
        'saldo_pendiente': 345600,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'last_modified_local': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPendingUpdate,
      });
      await db.insert(DatabaseSchema.installmentsTable, {
        'sync_id': installmentSyncId,
        'id_remote': 'remote-installment-conflict-child-1',
        'version': 15,
        'venta_id': saleId,
        'numero_cuota': 1,
        'fecha_vencimiento': createdAt,
        'saldo_inicial': 28800,
        'capital_cuota': 25600,
        'interes_cuota': 3200,
        'monto_cuota': 28800,
        'monto_pagado': 0,
        'capital_pagado': 0,
        'interes_pagado': 0,
        'saldo_final': 316800,
        'estado': 'pendiente',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'last_modified_local': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPendingUpdate,
      });

      await _insertQueuedRecord(
        appDatabase,
        scope: 'sales',
        syncId: saleSyncId,
        payload: {
          'sync_id': saleSyncId,
          'client_sync_id': 'client-conflict-parent-1',
          'product_sync_id': 'product-conflict-parent-1',
          'version': 10,
          'updated_at': createdAt,
        },
      );
      await _insertQueuedRecord(
        appDatabase,
        scope: 'installments',
        syncId: installmentSyncId,
        payload: {
          'sync_id': installmentSyncId,
          'sale_sync_id': saleSyncId,
          'version': 15,
          'installment_number': 1,
          'updated_at': createdAt,
        },
      );

      apiClient.installmentDownloadRecords = [
        {
          'id': 'remote-installment-conflict-child-1',
          'sync_id': installmentSyncId,
          'sale_sync_id': saleSyncId,
          'version': 16,
          'installment_number': 1,
          'due_date': createdAt,
          'opening_balance': 28800,
          'principal_amount': 25600,
          'interest_amount': 3200,
          'total_amount': 28800,
          'paid_amount': 0,
          'paid_principal_amount': 0,
          'paid_interest_amount': 0,
          'ending_balance': 316800,
          'status': 'pendiente',
          'created_at': createdAt,
          'updated_at': serverUpdatedAt,
          'deleted_at': null,
        },
      ];

      final processed = await service.processQueue();

      final queueRows = await db.query(DatabaseSchema.syncQueueTable);
      final installmentRow = (await db.query(
        DatabaseSchema.installmentsTable,
        where: 'sync_id = ?',
        whereArgs: [installmentSyncId],
        limit: 1,
      )).single;

      expect(processed, 0);
      expect(apiClient.uploadedScopes, ['sales']);
      expect(queueRows, isEmpty);
      expect(installmentRow['sync_status'], DatabaseSchema.syncStatusSynced);
      expect((installmentRow['version'] as num).toInt(), greaterThan(15));
      expect(apiClient.downloadCalls, 1);
    },
  );
}

Future<void> _insertQueuedRecord(
  AppDatabase appDatabase, {
  required String scope,
  required String syncId,
  required Map<String, Object?> payload,
}) async {
  final db = await appDatabase.database;
  final now = DateTime.now().toIso8601String();
  await db.insert(DatabaseSchema.syncQueueTable, {
    'scope': scope,
    'record_sync_id': syncId,
    'operation': 'upsert',
    'payload_json': jsonEncode(payload),
    'created_at': now,
    'updated_at': now,
    'next_attempt_at': now,
    'last_error': null,
    'attempt_count': 0,
  });
}

class _SalesConflictApiClient extends SyncApiClient {
  final List<String> uploadedScopes = [];
  int downloadCalls = 0;
  List<Map<String, dynamic>> installmentDownloadRecords = const [];

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final scope = recordsByScope.keys.single;
    uploadedScopes.add(scope);
    if (scope == 'sales') {
      final payload = recordsByScope[scope]!.single;
      final saleSyncId = payload['sync_id']?.toString() ?? '';
      throw SyncConflictException(
        message: 'Version conflict',
        scope: 'sales',
        strategy: SyncConflictStrategy.manual,
        conflicts: [
          SyncConflictItem(
            scope: 'sales',
            recordSyncId: saleSyncId,
            localVersion: 10,
            serverVersion: 11,
            localRecord: payload.map((key, value) => MapEntry(key, value)),
            serverRecord: {
              'sync_id': saleSyncId,
              'client_sync_id': 'client-conflict-parent-1',
              'product_sync_id': 'product-conflict-parent-1',
              'version': 11,
            },
            message: 'conflict',
          ),
        ],
        returnedRecords: [
          {
            'id': 'remote-sale-conflict-parent-1',
            'sync_id': saleSyncId,
            'client_sync_id': 'client-conflict-parent-1',
            'product_sync_id': 'product-conflict-parent-1',
            'seller_sync_id': null,
            'version': 11,
            'sale_date': DateTime(2026, 5, 5, 12, 0).toIso8601String(),
            'sale_price': 384000,
            'down_payment_percentage': 10,
            'down_payment_amount': 38400,
            'required_initial_payment': 38400,
            'paid_initial_payment': 38400,
            'pending_initial_payment': 0,
            'minimum_reserve_amount': null,
            'initial_payment_deadline': null,
            'activation_date': DateTime(2026, 5, 5, 12, 0).toIso8601String(),
            'financed_balance': 345600,
            'pending_balance': 345600,
            'monthly_interest': 1,
            'installment_count': 12,
            'status': 'activa',
            'created_at': DateTime(2026, 5, 5, 12, 0).toIso8601String(),
            'updated_at': DateTime(2026, 5, 5, 12, 5).toIso8601String(),
            'deleted_at': null,
          },
        ],
        serverUri: Uri.parse('${settings.normalizedBaseUrl}/sync/upload'),
      );
    }

    return SyncUploadResponse(returnedRecordsByScope: {
      scope: recordsByScope[scope]!
          .map((record) => record.map((key, value) => MapEntry(key, value)))
          .toList(growable: false),
    });
  }

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    downloadCalls += 1;
    return SyncDownloadResponse(
      recordsByScope: {'installments': installmentDownloadRecords},
    );
  }
}