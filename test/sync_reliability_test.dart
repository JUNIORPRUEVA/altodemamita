import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_logger.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_reliability_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('mantiene cambio local mas reciente cuando remoto viene atrasado', () async {
    final db = await appDatabase.database;
    final localUpdatedAt = DateTime.now().toIso8601String();
    final remoteUpdatedAt = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .toIso8601String();

    await db.insert(DatabaseSchema.sellersTable, {
      'sync_id': 'seller-1',
      'version': 3,
      'nombre': 'Vendedor local',
      'cedula': '00100000001',
      'telefono': '8090000001',
      'fecha_creacion': remoteUpdatedAt,
      'fecha_actualizacion': localUpdatedAt,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPending,
    });

    final queue = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: _FakeSyncConfigRepository(),
      apiClient: SyncApiClient(),
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    final repository = SellerRepository(
      database: appDatabase,
      syncQueueService: queue,
    );

    await repository.mergeRemoteRecords([
      {
        'sync_id': 'seller-1',
        'version': 2,
        'name': 'Vendedor remoto viejo',
        'document_id': '00100000001',
        'phone': '8091111111',
        'created_at': remoteUpdatedAt,
        'updated_at': remoteUpdatedAt,
        'deleted_at': null,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'sync_id = ?',
      whereArgs: ['seller-1'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['nombre'], 'Vendedor local');
    expect(rows.first['version'], 3);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusPending);
  });

  test('reconcilia usuario remoto por email cuando cambia sync_id', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(DatabaseSchema.usersTable, {
      'sync_id': 'local-user-sync',
      'version': 1,
      'nombre': 'Administrador principal',
      'email': 'admin@gmail.com',
      'password_hash': 'hash-local',
      'password_reset_required': 0,
      'rol': 'admin',
      'activo': 1,
      'telefono': null,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
      'auth_source': 'local',
      'last_online_login_at': null,
    });

    final repository = UsersSyncRepository(appDatabase: appDatabase);
    await repository.mergeRemoteRecords([
      {
        'sync_id': 'remote-user-sync',
        'version': 1,
        'full_name': 'Administrador principal',
        'email': 'admin@gmail.com',
        'password_hash': 'hash-remoto',
        'password_reset_required': false,
        'role': 'admin',
        'is_active': true,
        'created_at': now,
        'updated_at': now,
        'password_updated_at': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'LOWER(email) = ?',
      whereArgs: ['admin@gmail.com'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['sync_id'], 'remote-user-sync');
    expect(rows.first['email'], 'admin@gmail.com');
    expect(rows.first['password_hash'], 'hash-remoto');
  });

  test('delete remoto de producto se replica como soft delete local', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1500,
      'estado': 'disponible',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final repository = ProductsSyncRepository(appDatabase: appDatabase);
    await repository.mergeRemoteRecords([
      {
        'sync_id': 'lot-1',
        'version': 2,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-1'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusSynced);
  });

  test(
    'reconcilia cuota remota por venta y numero cuando cambia sync_id',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();

      await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-sync-1',
        'version': 1,
        'cliente_id': 1,
        'solar_id': 1,
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
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await db.insert(DatabaseSchema.installmentsTable, {
        'sync_id': 'local-slot-sync',
        'version': 1,
        'venta_id': 1,
        'numero_cuota': 1,
        'fecha_vencimiento': now,
        'saldo_inicial': 450000,
        'capital_cuota': 30000,
        'interes_cuota': 4500,
        'monto_cuota': 34500,
        'monto_pagado': 0,
        'capital_pagado': 0,
        'interes_pagado': 0,
        'saldo_final': 420000,
        'estado': 'pendiente',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final repository = InstallmentsSyncRepository(appDatabase: appDatabase);
      await repository.mergeRemoteRecords([
        {
          'id': 'remote-installment-id',
          'sync_id': 'remote-slot-sync',
          'version': 4,
          'sale_sync_id': 'sale-sync-1',
          'installment_number': 1,
          'due_date': now,
          'opening_balance': 450000,
          'principal_amount': 35481.95,
          'interest_amount': 4500,
          'total_amount': 39981.95,
          'paid_amount': 0,
          'paid_principal_amount': 0,
          'paid_interest_amount': 0,
          'ending_balance': 414518.05,
          'status': 'pendiente',
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusSynced,
        },
      ]);

      final rows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ? AND numero_cuota = ?',
        whereArgs: [1, 1],
      );

      expect(rows, hasLength(1));
      expect(rows.first['sync_id'], 'remote-slot-sync');
      expect(rows.first['id_remote'], 'remote-installment-id');
      expect(rows.first['version'], 4);
      expect(rows.first['monto_cuota'], 39981.95);
      expect(rows.first['saldo_final'], 414518.05);
    },
  );

  test('sync logger escribe en logs/sync.log', () async {
    final appPaths = AppPaths(supportDirectory: tempDirectory.path);
    final logger = SyncLogger(appPaths: appPaths);

    await logger.log(
      action: 'upload',
      entity: 'sales',
      result: 'ok',
      extra: {'count': 1},
    );

    final file = File(appPaths.syncLogPath);
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines, isNotEmpty);

    final payload = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(payload['action'], 'upload');
    expect(payload['entity'], 'sales');
    expect(payload['result'], 'ok');
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 10),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'device',
    );
  }
}