import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
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
  late _MemorySyncApiClient apiClient;
  late StreamController<List<ConnectivityResult>> connectivityController;
  late SyncQueueService syncQueueService;
  late SalesRepository salesRepository;
  late bool online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sales_offline_sync_flow_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();

    configRepository = _FakeSyncConfigRepository();
    apiClient = _MemorySyncApiClient();
    connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
    online = false;

    syncQueueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => online,
      connectivityChanges: connectivityController.stream,
    );
    syncQueueService.registerRepository(_ProductsDbSyncRepository(appDatabase));
    syncQueueService.registerRepository(_SalesDbSyncRepository(appDatabase));
    syncQueueService.registerRepository(
      _InstallmentsDbSyncRepository(appDatabase),
    );
    syncQueueService.registerRepository(_PaymentsDbSyncRepository(appDatabase));

    salesRepository = SalesRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );
  });

  tearDown(() async {
    syncQueueService.dispose();
    await connectivityController.close();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'crea venta offline, la mantiene local y la sincroniza al reconectar sin duplicarla',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 4, 24, 14, 30);

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-offline-sync-1',
        'version': 1,
        'nombre': 'Cliente Offline Sync',
        'cedula': '001-0000101-9',
        'telefono': '8095550101',
        'direccion': 'Calle Proyecto 1',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-offline-sync-1',
        'version': 1,
        'manzana_numero': 'A',
        'solar_numero': '12',
        'metros_cuadrados': 180.0,
        'precio_por_metro': 4000.0,
        'estado': 'disponible',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: clientId,
          lotId: lotId,
          userId: 1,
          saleDate: now,
          salePrice: 720000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 72000,
          initialPaymentPaid: 72000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final saleRow = (await db.query(
        DatabaseSchema.salesTable,
        columns: ['sync_id', 'sync_status'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      final saleSyncId = saleRow['sync_id'] as String;

      expect(saleRow['sync_status'], DatabaseSchema.syncStatusPendingCreate);
      expect(
        await _countByStatus(
          db,
          DatabaseSchema.installmentsTable,
          DatabaseSchema.syncStatusPendingCreate,
        ),
        12,
      );
      expect(
        await _countByStatus(
          db,
          DatabaseSchema.paymentsTable,
          DatabaseSchema.syncStatusPendingCreate,
        ),
        1,
      );

      final offlineProcessed = await syncQueueService.syncPending();
      expect(offlineProcessed, 0);
      expect(await syncQueueService.pendingCount(), greaterThan(0));
      expect(apiClient.uploadedScopes, isEmpty);

      await syncQueueService.start();
      online = true;
      connectivityController.add(const [ConnectivityResult.wifi]);

      await _waitUntil(() async => await syncQueueService.pendingCount() == 0);

      final saleRowAfter = (await db.query(
        DatabaseSchema.salesTable,
        columns: ['sync_status'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      expect(saleRowAfter['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(
        await _countByStatus(
          db,
          DatabaseSchema.lotsTable,
          DatabaseSchema.syncStatusSynced,
          where: 'id = ?',
          whereArgs: [lotId],
        ),
        1,
      );
      expect(
        await _countByStatus(
          db,
          DatabaseSchema.installmentsTable,
          DatabaseSchema.syncStatusSynced,
        ),
        12,
      );
      expect(
        await _countByStatus(
          db,
          DatabaseSchema.paymentsTable,
          DatabaseSchema.syncStatusSynced,
        ),
        1,
      );

      expect(apiClient.countServerRecords('sales', saleSyncId), 1);
      expect(apiClient.countUploads('sales', saleSyncId), 1);

      connectivityController.add(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(apiClient.countServerRecords('sales', saleSyncId), 1);
      expect(apiClient.countUploads('sales', saleSyncId), 1);
    },
  );

  test(
    'edita venta offline y sube version nueva con deletes de cuotas usando timestamp actual',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 4, 25, 9, 0);

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-offline-edit-1',
        'version': 1,
        'nombre': 'Cliente Edit Sync',
        'cedula': '001-0000202-8',
        'telefono': '8095550202',
        'direccion': 'Calle Proyecto 2',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-offline-edit-1',
        'version': 1,
        'manzana_numero': 'B',
        'solar_numero': '03',
        'metros_cuadrados': 200.0,
        'precio_por_metro': 2500.0,
        'estado': 'disponible',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: clientId,
          lotId: lotId,
          userId: 1,
          saleDate: now,
          salePrice: 500000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 50000,
          initialPaymentPaid: 50000,
          monthlyInterest: 1,
          installmentCount: 120,
        ),
      );

      await syncQueueService.start();
      online = true;
      connectivityController.add(const [ConnectivityResult.wifi]);
      await _waitUntil(() async => await syncQueueService.pendingCount() == 0);

      final initialInstallmentRows = await db.query(
        DatabaseSchema.installmentsTable,
        columns: ['sync_id'],
        where: 'venta_id = ?',
        whereArgs: [saleId],
      );
      final deletedSyncIds = initialInstallmentRows
          .map((row) => row['sync_id'] as String)
          .toSet();

      online = false;
      await salesRepository.updateSale(
        saleId,
        SaleDraft(
          clientId: clientId,
          lotId: lotId,
          userId: 1,
          saleDate: now.add(const Duration(days: 1)),
          salePrice: 500000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 50000,
          initialPaymentPaid: 50000,
          monthlyInterest: 1,
          installmentCount: 60,
        ),
      );

      final editedSaleRow = (await db.query(
        DatabaseSchema.salesTable,
        columns: ['sync_id', 'version', 'sync_status'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      final saleSyncId = editedSaleRow['sync_id'] as String;
      expect(editedSaleRow['version'], 2);
      expect(
        editedSaleRow['sync_status'],
        DatabaseSchema.syncStatusPendingUpdate,
      );

      online = true;
      connectivityController.add(const [ConnectivityResult.wifi]);
      await _waitUntil(() async => await syncQueueService.pendingCount() == 0);

      final saleUploads =
          apiClient.uploadedRecordsByScope['sales'] ?? const <Map<String, dynamic>>[];
      final updatedSaleUpload = saleUploads.lastWhere(
        (record) =>
            record['sync_id'] == saleSyncId &&
            record['sync_status'] == DatabaseSchema.syncStatusPendingUpdate,
      );
      expect(updatedSaleUpload['version'], 2);
      expect(updatedSaleUpload['installment_count'], 60);

      final installmentUploads =
          apiClient.uploadedRecordsByScope['installments'] ??
          const <Map<String, dynamic>>[];
      final deletedInstallmentUploads = installmentUploads
          .where(
            (record) =>
                deletedSyncIds.contains(record['sync_id']) &&
                record['deleted_at'] != null,
          )
          .toList(growable: false);
      expect(deletedInstallmentUploads, hasLength(120));
      for (final record in deletedInstallmentUploads) {
        expect(record['updated_at'], record['deleted_at']);
      }
    },
  );

  test(
    'borra venta offline sin pagos y al reconectar sincroniza el soft delete sin revivirla',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 4, 26, 10, 15);

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-offline-delete-1',
        'version': 1,
        'nombre': 'Cliente Delete Sync',
        'cedula': '001-0000303-7',
        'telefono': '8095550303',
        'direccion': 'Calle Proyecto 3',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-offline-delete-1',
        'version': 1,
        'manzana_numero': 'C',
        'solar_numero': '07',
        'metros_cuadrados': 210.0,
        'precio_por_metro': 3000.0,
        'estado': 'disponible',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: clientId,
          lotId: lotId,
          userId: 1,
          saleDate: now,
          salePrice: 500000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 50000,
          initialPaymentPaid: 50000,
          monthlyInterest: 1,
          installmentCount: 120,
        ),
      );

      await syncQueueService.start();
      online = true;
      connectivityController.add(const [ConnectivityResult.wifi]);
      await _waitUntil(() async => await syncQueueService.pendingCount() == 0);

      final saleRow = (await db.query(
        DatabaseSchema.salesTable,
        columns: ['sync_id'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      final saleSyncId = saleRow['sync_id'] as String;

      online = false;
      await salesRepository.deleteSale(saleId);

      expect(await salesRepository.fetchDetail(saleId), isNull);

      final deletedRow = (await db.query(
        DatabaseSchema.salesTable,
        columns: ['deleted_at', 'sync_status', 'version'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      expect(deletedRow['deleted_at'], isNotNull);
      expect(deletedRow['sync_status'], DatabaseSchema.syncStatusPendingDelete);
      expect(deletedRow['version'], 2);

      online = true;
      connectivityController.add(const [ConnectivityResult.wifi]);
      await _waitUntil(() async => await syncQueueService.pendingCount() == 0);

      final saleUploads =
          apiClient.uploadedRecordsByScope['sales'] ?? const <Map<String, dynamic>>[];
      final deleteUpload = saleUploads.lastWhere(
        (record) =>
            record['sync_id'] == saleSyncId && record['deleted_at'] != null,
      );
      expect(deleteUpload['version'], 2);
      expect(deleteUpload['updated_at'], deleteUpload['deleted_at']);

      final syncedRow = (await db.query(
        DatabaseSchema.salesTable,
        columns: ['deleted_at', 'sync_status'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;
      expect(syncedRow['deleted_at'], isNotNull);
      expect(syncedRow['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(await salesRepository.fetchDetail(saleId), isNull);
    },
  );
}

Future<int> _countByStatus(
  dynamic db,
  String tableName,
  String syncStatus, {
  String? where,
  List<Object?>? whereArgs,
}) async {
  final rows = await db.query(
    tableName,
    columns: ['id'],
    where: [
      if (where != null && where.trim().isNotEmpty) '($where)',
      'sync_status = ?',
    ].join(' AND '),
    whereArgs: [...?whereArgs, syncStatus],
  );
  return rows.length;
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
      deviceId: 'desktop-test-device',
    );
  }
}

class _MemorySyncApiClient extends SyncApiClient {
  _MemorySyncApiClient();

  final List<String> uploadedScopes = [];
  final Map<String, List<Map<String, dynamic>>> serverRecordsByScope = {};
  final Map<String, List<Map<String, dynamic>>> uploadedRecordsByScope = {};

  int countServerRecords(String scope, String syncId) {
    return (serverRecordsByScope[scope] ?? const <Map<String, dynamic>>[])
        .where((record) => record['sync_id'] == syncId)
        .length;
  }

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
      for (final record in records) {
        uploadedScopes.add(scope);
        final normalized = record.map((key, value) => MapEntry(key, value));
        uploadedRecordsByScope.putIfAbsent(scope, () => []).add(normalized);

        final syncId = normalized['sync_id']?.toString().trim() ?? '';
        if (syncId.isEmpty) {
          continue;
        }

        final serverScope = serverRecordsByScope.putIfAbsent(scope, () => []);
        final existingIndex = serverScope.indexWhere(
          (item) => item['sync_id'] == syncId,
        );
        if (existingIndex == -1) {
          serverScope.add(Map<String, dynamic>.from(normalized));
        } else {
          serverScope[existingIndex] = Map<String, dynamic>.from(normalized);
        }
      }

      returned[scope] = records
          .map((record) => record.map((key, value) => MapEntry(key, value)))
          .toList(growable: false);
    });

    return SyncUploadResponse(returnedRecordsByScope: returned);
  }
}

class _ProductsDbSyncRepository implements SyncRepository {
  _ProductsDbSyncRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  String get scope => 'products';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_status IN (?, ?, ?, ?, ?)',
      whereArgs: [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingSync,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
      ],
      orderBy: 'fecha_actualizacion ASC',
    );
    return rows
        .map(
          (row) => {
            'sync_id': row['sync_id'],
            'version': row['version'],
            'block_number': row['manzana_numero'],
            'lot_number': row['solar_numero'],
            'area': row['metros_cuadrados'],
            'price_per_square_meter': row['precio_por_metro'],
            'status': row['estado'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.lotsTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusSynced,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.lotsTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusConflict,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}

class _SalesDbSyncRepository implements SyncRepository {
  _SalesDbSyncRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  String get scope => 'sales';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        v.*,
        c.sync_id AS client_sync_id,
        s.sync_id AS product_sync_id,
        vd.sync_id AS seller_sync_id
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      LEFT JOIN vendedores vd ON vd.id = v.vendedor_id
      WHERE v.sync_status IN (?, ?, ?, ?, ?, ?)
      ORDER BY v.fecha_actualizacion ASC
      ''',
      [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingSync,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
    );
    return rows
        .map(
          (row) => {
            'sync_id': row['sync_id'],
            'version': row['version'],
            'client_sync_id': row['client_sync_id'],
            'product_sync_id': row['product_sync_id'],
            'seller_sync_id': row['seller_sync_id'],
            'sale_date': row['fecha_venta'],
            'sale_price': row['precio_venta'],
            'down_payment_percentage': row['inicial_porcentaje'],
            'down_payment_amount': row['inicial_monto'],
            'required_initial_payment': row['monto_inicial_requerido'],
            'paid_initial_payment': row['monto_inicial_pagado'],
            'pending_initial_payment': row['monto_inicial_pendiente'],
            'minimum_reserve_amount': row['monto_apartado_minimo'],
            'initial_payment_deadline': row['fecha_limite_inicial'],
            'activation_date': row['fecha_activacion'],
            'financed_balance': row['saldo_financiado'],
            'pending_balance': row['saldo_pendiente'],
            'monthly_interest': row['interes_mensual'],
            'installment_count': row['cantidad_cuotas'],
            'status': row['estado'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.salesTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusSynced,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.salesTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusConflict,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}

class _InstallmentsDbSyncRepository implements SyncRepository {
  _InstallmentsDbSyncRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  String get scope => 'installments';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        q.*,
        v.sync_id AS sale_sync_id
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
      WHERE q.sync_status IN (?, ?, ?, ?, ?)
      ORDER BY q.fecha_actualizacion ASC
      ''',
      [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
    );
    return rows
        .map(
          (row) => {
            'sync_id': row['sync_id'],
            'version': row['version'],
            'sale_sync_id': row['sale_sync_id'],
            'installment_number': row['numero_cuota'],
            'due_date': row['fecha_vencimiento'],
            'opening_balance': row['saldo_inicial'],
            'principal_amount': row['capital_cuota'],
            'interest_amount': row['interes_cuota'],
            'total_amount': row['monto_cuota'],
            'paid_amount': row['monto_pagado'],
            'paid_principal_amount': row['capital_pagado'],
            'paid_interest_amount': row['interes_pagado'],
            'ending_balance': row['saldo_final'],
            'status': row['estado'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.installmentsTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusSynced,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.installmentsTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusConflict,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}

class _PaymentsDbSyncRepository implements SyncRepository {
  _PaymentsDbSyncRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  String get scope => 'payments';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        p.*,
        v.sync_id AS sale_sync_id,
        c.sync_id AS client_sync_id,
        q.sync_id AS installment_sync_id
      FROM ${DatabaseSchema.paymentsTable} p
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = p.venta_id
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = p.cliente_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
      WHERE p.sync_status IN (?, ?, ?, ?, ?)
      ORDER BY COALESCE(p.fecha_actualizacion, p.fecha_creacion) ASC
      ''',
      [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
    );
    return rows
        .map(
          (row) => {
            'sync_id': row['sync_id'],
            'version': row['version'],
            'sale_sync_id': row['sale_sync_id'],
            'client_sync_id': row['client_sync_id'],
            'installment_sync_id': row['installment_sync_id'],
            'payment_date': row['fecha_pago'],
            'amount_paid': row['monto_pagado'],
            'payment_method': row['metodo_pago'],
            'payment_type': row['tipo_pago'],
            'reference': row['referencia'],
            'year_to_pay': row['ano_a_pagar'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'] ?? row['fecha_creacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.paymentsTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusSynced,
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _markRowsBySyncId(
      appDatabase: _appDatabase,
      tableName: DatabaseSchema.paymentsTable,
      syncIds: syncIds,
      syncStatus: DatabaseSchema.syncStatusConflict,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}

Future<void> _markRowsBySyncId({
  required AppDatabase appDatabase,
  required String tableName,
  required Iterable<String> syncIds,
  required String syncStatus,
}) async {
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
    [syncStatus, ...ids],
  );
}
