import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncConfigRepository configRepository;
  late _CursorAwareSyncApiClient apiClient;
  late SyncQueueService queueService;
  late SyncService syncService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_full_download_rehydrates_missing_sales_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    configRepository = SyncConfigRepository();
    apiClient = _CursorAwareSyncApiClient();
    queueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    syncService = SyncService(
      repositories: [
        ClientRepository(
          appDatabase: appDatabase,
          syncQueueService: queueService,
        ),
        ProductsSyncRepository(appDatabase: appDatabase),
        SalesSyncRepository(appDatabase: appDatabase),
      ],
      configRepository: configRepository,
      apiClient: apiClient,
      syncQueueService: queueService,
      appDatabase: appDatabase,
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
    'download limpia cursores de negocio cuando la base local quedo sin ventas pero conserva referencias',
    () async {
      final db = await appDatabase.database;
      final createdAt = DateTime(2026, 5, 1, 9, 0).toIso8601String();
      final saleUpdatedAt = DateTime(2026, 5, 1, 10, 0).toIso8601String();
      final staleCursor = DateTime(2026, 5, 5, 12, 0);

      await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-missing-sale-1',
        'version': 1,
        'nombre': 'Cliente Recuperado',
        'cedula': '001-0000999-1',
        'telefono': '8095559991',
        'direccion': 'Calle Recuperacion',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-missing-sale-1',
        'version': 1,
        'manzana_numero': 'Z',
        'solar_numero': '09',
        'metros_cuadrados': 150,
        'precio_por_metro': 3000,
        'estado': 'vendido',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await configRepository.saveCursor('clients', staleCursor);
      await configRepository.saveCursor('products', staleCursor);
      await configRepository.saveCursor('sales', staleCursor);
      await configRepository.saveCursor('installments', staleCursor);
      await configRepository.saveCursor('payments', staleCursor);

      apiClient.recordsByScope = {
        'sales': [
          {
            'id': 'remote-sale-missing-1',
            'sync_id': 'sale-missing-local-1',
            'client_sync_id': 'client-missing-sale-1',
            'product_sync_id': 'product-missing-sale-1',
            'seller_sync_id': null,
            'version': 3,
            'sale_date': createdAt,
            'sale_price': 450000,
            'down_payment_percentage': 10,
            'down_payment_amount': 45000,
            'required_initial_payment': 45000,
            'paid_initial_payment': 45000,
            'pending_initial_payment': 0,
            'minimum_reserve_amount': null,
            'initial_payment_deadline': null,
            'activation_date': createdAt,
            'financed_balance': 405000,
            'pending_balance': 405000,
            'monthly_interest': 1,
            'installment_count': 12,
            'status': 'activa',
            'created_at': createdAt,
            'updated_at': saleUpdatedAt,
            'deleted_at': null,
          },
        ],
      };

      final downloaded = await syncService.downloadUpdates();
      final salesRows = await db.query(DatabaseSchema.salesTable);

      expect(downloaded, 1);
      expect(apiClient.requestedUpdatedSince, isNull);
      expect(salesRows, hasLength(1));
      expect(salesRows.single['sync_id'], 'sale-missing-local-1');
      expect(salesRows.single['sync_status'], DatabaseSchema.syncStatusSynced);
    },
  );
}

class _CursorAwareSyncApiClient extends SyncApiClient {
  DateTime? requestedUpdatedSince;
  Map<String, List<Map<String, dynamic>>> recordsByScope = {};

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
  }) async {
    requestedUpdatedSince = updatedSince;
    final filtered = <String, List<Map<String, dynamic>>>{};
    recordsByScope.forEach((scope, records) {
      filtered[scope] = records.where((record) {
        if (updatedSince == null) {
          return true;
        }
        final updatedAt = DateTime.tryParse(record['updated_at']?.toString() ?? '');
        return updatedAt != null && updatedAt.isAfter(updatedSince);
      }).map((record) => Map<String, dynamic>.from(record)).toList(growable: false);
    });
    return SyncDownloadResponse(recordsByScope: filtered);
  }

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    return const SyncUploadResponse(returnedRecordsByScope: {});
  }
}