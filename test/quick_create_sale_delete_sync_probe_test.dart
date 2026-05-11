import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sale sync scopes include quick-created client and seller references', () {
    expect(
      SalesRepository.createSaleSyncScopes,
      containsAllInOrder(['clients', 'products', 'sellers', 'sales']),
    );
    expect(
      SalesRepository.saleMutationSyncScopes,
      containsAllInOrder(['clients', 'products', 'sellers', 'sales']),
    );
  });

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncQueueService syncQueueService;
  late _FakeSyncConfigRepository configRepository;
  late _MemorySyncApiClient apiClient;
  late ClientRepository clientRepository;
  late LotRepository lotRepository;
  late SellerRepository sellerRepository;
  late SalesRepository salesRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'quick_create_sale_delete_sync_probe_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository();
    apiClient = _MemorySyncApiClient();
    syncQueueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => true,
      connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
    );

    clientRepository = ClientRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );
    lotRepository = LotRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );
    sellerRepository = SellerRepository(
      database: appDatabase,
      syncQueueService: syncQueueService,
    );
    salesRepository = SalesRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );

    syncQueueService.registerRepository(
      ProductsSyncRepository(appDatabase: appDatabase),
    );
    syncQueueService.registerRepository(
      SalesSyncRepository(appDatabase: appDatabase),
    );
    syncQueueService.registerRepository(
      InstallmentsSyncRepository(appDatabase: appDatabase),
    );
    syncQueueService.registerRepository(
      PaymentsSyncRepository(appDatabase: appDatabase),
    );
  });

  tearDown(() async {
    syncQueueService.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('scenario A quick-created client delete is uploaded as tombstone', () async {
    final now = DateTime(2026, 5, 11, 10, 0);
    await clientRepository.save(
      Client(
        fullName: 'Cliente Escenario A',
        documentId: '001-1000001-1',
        phone: '8095550001',
        address: 'Direccion A',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final clientSyncId = await _readSyncId(
      appDatabase,
      DatabaseSchema.clientsTable,
      client.id!,
    );

    await syncQueueService.syncPending();
    expect(apiClient.countUploads('clients', clientSyncId), 1);

    await clientRepository.delete(client.id!);

    await syncQueueService.syncPending();

    final deleteUploads = apiClient.uploadedRecordsByScope['clients']!
        .where((record) => record['sync_id'] == clientSyncId)
        .where((record) => (record['deleted_at']?.toString().isNotEmpty ?? false))
        .toList(growable: false);
    expect(deleteUploads, hasLength(1));
  });

  test(
    'scenario B quick-created client lot seller remain deletable after createSale and deleteSale',
    () async {
      final now = DateTime(2026, 5, 11, 11, 0);

      await clientRepository.save(
        Client(
          fullName: 'Cliente Escenario B',
          documentId: '001-1000002-2',
          phone: '8095550002',
          address: 'Direccion B',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await lotRepository.save(
        Lot(
          blockNumber: 'B',
          lotNumber: '02',
          area: 200,
          pricePerSquareMeter: 3500,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final sellerId = await sellerRepository.insert(
        Seller(
          name: 'Vendedor Escenario B',
          phone: '8095550003',
          documentId: '001-1000003-3',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;
      final seller = (await sellerRepository.getAll())
          .firstWhere((item) => item.id == sellerId);

      final clientSyncId = await _readSyncId(
        appDatabase,
        DatabaseSchema.clientsTable,
        client.id!,
      );
      final lotSyncId = await _readSyncId(
        appDatabase,
        DatabaseSchema.lotsTable,
        lot.id!,
      );
      final sellerSyncId = await _readSyncId(
        appDatabase,
        DatabaseSchema.sellersTable,
        seller.id!,
      );

      await syncQueueService.syncPending();

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          sellerId: seller.id,
          saleDate: now,
          salePrice: lot.totalPrice,
          downPaymentPercentage: 10,
          requiredInitialPayment: lot.totalPrice * 0.10,
          initialPaymentPaid: lot.totalPrice * 0.10,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      await syncQueueService.syncPending();
      await salesRepository.deleteSale(saleId);
      await syncQueueService.syncPending();

      await clientRepository.delete(client.id!);
      await lotRepository.delete(lot.id!);
      await sellerRepository.delete(seller.id!);

      final db = await appDatabase.database;
      final clientRowBeforeUpload = await _readRowBySyncId(
        db,
        DatabaseSchema.clientsTable,
        clientSyncId,
      );
      final lotRowBeforeUpload = await _readRowBySyncId(
        db,
        DatabaseSchema.lotsTable,
        lotSyncId,
      );
      final sellerRowBeforeUpload = await _readRowBySyncId(
        db,
        DatabaseSchema.sellersTable,
        sellerSyncId,
      );

      expect(
        clientRowBeforeUpload['sync_status'],
        DatabaseSchema.syncStatusPendingDelete,
      );
      expect(
        lotRowBeforeUpload['sync_status'],
        DatabaseSchema.syncStatusPendingDelete,
      );
      expect(
        sellerRowBeforeUpload['sync_status'],
        DatabaseSchema.syncStatusPendingDelete,
      );

      await syncQueueService.syncPending();

      expect(_countDeleteUploads(apiClient, 'clients', clientSyncId), 1);
      expect(_countDeleteUploads(apiClient, 'products', lotSyncId), 1);
      expect(_countDeleteUploads(apiClient, 'sellers', sellerSyncId), 1);

      final clientRow = await _readRowBySyncId(
        db,
        DatabaseSchema.clientsTable,
        clientSyncId,
      );
      final lotRow = await _readRowBySyncId(
        db,
        DatabaseSchema.lotsTable,
        lotSyncId,
      );
      final sellerRow = await _readRowBySyncId(
        db,
        DatabaseSchema.sellersTable,
        sellerSyncId,
      );

      expect(clientRow['deleted_at'], isNotNull);
      expect(lotRow['deleted_at'], isNotNull);
      expect(sellerRow['deleted_at'], isNotNull);
      expect(clientRow['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(lotRow['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(sellerRow['sync_status'], DatabaseSchema.syncStatusSynced);
    },
  );
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
      deviceId: 'desktop-test-device',
    );
  }
}

class _MemorySyncApiClient extends SyncApiClient {
  _MemorySyncApiClient();

  final Map<String, List<Map<String, dynamic>>> uploadedRecordsByScope = {};

  int countUploads(String scope, String syncId) {
    return (uploadedRecordsByScope[scope] ?? const <Map<String, dynamic>>[])
        .where((record) => record['sync_id'] == syncId)
        .length;
  }

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final returned = <String, List<Map<String, dynamic>>>{};

    recordsByScope.forEach((scope, records) {
      uploadedRecordsByScope.putIfAbsent(scope, () => []);
      for (final record in records) {
        final normalized = record.map((key, value) => MapEntry(key, value));
        uploadedRecordsByScope[scope]!.add(normalized);
      }

      returned[scope] = records
          .map((record) => record.map((key, value) => MapEntry(key, value)))
          .toList(growable: false);
    });

    return SyncUploadResponse(returnedRecordsByScope: returned);
  }
}

Future<String> _readSyncId(
  AppDatabase appDatabase,
  String tableName,
  int id,
) async {
  final db = await appDatabase.database;
  final rows = await db.query(
    tableName,
    columns: ['sync_id'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.single['sync_id']!.toString();
}

int _countDeleteUploads(
  _MemorySyncApiClient apiClient,
  String scope,
  String syncId,
) {
  return (apiClient.uploadedRecordsByScope[scope] ?? const <Map<String, dynamic>>[])
      .where((record) => record['sync_id'] == syncId)
      .where((record) => record['deleted_at']?.toString().trim().isNotEmpty ?? false)
      .length;
}

Future<Map<String, Object?>> _readRowBySyncId(
  Database db,
  String tableName,
  String syncId,
) async {
  final rows = await db.query(
    tableName,
    where: 'sync_id = ?',
    whereArgs: [syncId],
    limit: 1,
  );
  return rows.single;
}