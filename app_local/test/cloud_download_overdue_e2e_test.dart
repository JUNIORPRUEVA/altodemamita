import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/business/installment_status.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

import 'helpers/fake_sync_download_api_client.dart';
import 'helpers/payment_application_test_harness.dart';

/// PARTE B — CLOUD DOWNLOAD E2E POR LA RUTA REAL
///
/// Ruta ejercitada de extremo a extremo (nada de invalidar caches a mano):
///   respuesta cloud (FakeSyncDownloadApiClient)
///     -> SyncService.downloadUpdatesForScopes(['installments'])
///     -> InstallmentsSyncRepository.mergeRemoteRecords
///     -> SQLite (cuotas)
///     -> invalidacion financiera de caches
///     -> SalesRepository (lista + detalle)
///
/// Este archivo corre en modo LOCAL (default) para poder observar el conteo de
/// vencidas DERIVADO de SQLite. La invalidacion del snapshot `cache_ventas_lista`
/// (que solo existe en modo CLOUD_AUTHORITATIVE) se verifica con la MISMA ruta de
/// sync en `sales_list_cache_cloud_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime anchor;
  late String saleSyncId;
  late PaymentApplicationTestHarness harness;
  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SalesRepository salesRepository;
  late SyncConfigRepository configRepository;
  late FakeSyncDownloadApiClient apiClient;
  late SyncService syncService;

  setUpAll(() {
    anchor = DateTime.parse(InstallmentStatusResolver.currentBusinessDateKey());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    harness = await PaymentApplicationTestHarness.create();
    appDatabase = harness.appDatabase;
    salesRepository = SalesRepository(appDatabase: appDatabase);

    // El sincronizador usa el MISMO AppDatabase que los repositorios de negocio.
    tempDirectory = await Directory.systemTemp.createTemp(
      'cloud_download_overdue_',
    );
    configRepository = SyncConfigRepository(
      settingsRepository: SettingsRepository(appDatabase: appDatabase),
      preferencesFactory: SharedPreferences.getInstance,
    );
    apiClient = FakeSyncDownloadApiClient();
    final queueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: configRepository,
      apiClient: apiClient,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    syncService = SyncService(
      repositories: [
        SalesSyncRepository(appDatabase: appDatabase),
        InstallmentsSyncRepository(appDatabase: appDatabase),
      ],
      configRepository: configRepository,
      apiClient: apiClient,
      syncQueueService: queueService,
      appDatabase: appDatabase,
      allowCloudPullOverride: true,
    );
    await configRepository.saveBaseUrl('http://127.0.0.1:9999/api');
    await configRepository.saveJwtToken('jwt-test');
  });

  tearDown(() async {
    await harness.dispose();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  /// Venta con EXACTAMENTE 1 cuota vencida (cuota 1) y el resto pendientes.
  Future<int> seedSaleWithOneOverdue() async {
    final saleId = await harness.createFinancedSale(
      saleDate: DateTime(
        anchor.year,
        anchor.month - 1,
        anchor.day,
      ).subtract(const Duration(days: 5)),
      installmentCount: 6,
    );
    final db = await appDatabase.database;
    final saleRows = await db.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    saleSyncId = saleRows.first['sync_id'] as String;
    final cuotas = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
      orderBy: 'numero_cuota ASC',
    );
    // Estado de partida realista: cuotas ya sincronizadas, con sync_id estable.
    for (final cuota in cuotas) {
      await db.update(
        DatabaseSchema.installmentsTable,
        {
          'sync_id': 'inst-sync-${cuota['numero_cuota']}',
          'sync_status': DatabaseSchema.syncStatusSynced,
        },
        where: 'id = ?',
        whereArgs: [cuota['id']],
      );
    }
    return saleId;
  }

  Future<List<Map<String, Object?>>> cuotasOf(int saleId) async {
    final db = await appDatabase.database;
    return db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
      orderBy: 'numero_cuota ASC',
    );
  }

  Future<int> countOf(String table) async {
    final db = await appDatabase.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
    return (rows.first['total'] as num).toInt();
  }

  /// Registro cloud de una cuota, con la misma forma que devuelve el backend.
  Map<String, dynamic> cloudInstallment({
    required String syncId,
    required int number,
    required DateTime dueDate,
    required Map<String, Object?> local,
    required DateTime updatedAt,
    double? paidAmount,
    double? paidPrincipalAmount,
  }) {
    return {
      'id': 'remote-$syncId',
      'sync_id': syncId,
      'sale_sync_id': saleSyncId,
      'version': 2,
      'installment_number': number,
      // Convencion del producto: un valor NAIVE es hora de pared de RD. Se envia
      // sin conversion para que el resultado no dependa de la zona del equipo
      // (convertir a UTC desde la zona local corria el dia de negocio).
      'due_date': dueDate.toIso8601String(),
      'opening_balance': (local['saldo_inicial'] as num).toDouble(),
      'principal_amount': (local['capital_cuota'] as num).toDouble(),
      'interest_amount': (local['interes_cuota'] as num).toDouble(),
      'total_amount': (local['monto_cuota'] as num).toDouble(),
      'paid_amount': paidAmount ?? (local['monto_pagado'] as num).toDouble(),
      'paid_principal_amount':
          paidPrincipalAmount ?? (local['capital_pagado'] as num).toDouble(),
      'paid_interest_amount': (local['interes_pagado'] as num).toDouble(),
      'ending_balance': (local['saldo_final'] as num).toDouble(),
      'status': 'pendiente',
      'created_at': (local['fecha_creacion'] as String),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': null,
    };
  }

  test(
    'B1: descarga real de cuotas cambia el conteo 1 -> 2 en SQLite, lista y detalle',
    () async {
      final saleId = await seedSaleWithOneOverdue();

      // PRE: 1 vencida en lista y detalle, outbox vacia y sin conflictos.
      expect(await _listOverdue(salesRepository, saleId), 1);
      expect(await _detailOverdue(salesRepository, saleId), 1);
      expect(await countOf('sync_queue'), 0);
      expect(await countOf('conflict_logs'), 0);

      final before = await cuotasOf(saleId);
      final cloudUpdatedAt = DateTime.now().toUtc().add(
        const Duration(minutes: 5),
      );
      // La nube adelanta el vencimiento de la cuota 2 (queda en el pasado).
      final newDueDate = anchor.subtract(const Duration(days: 2));

      apiClient.recordsByScope = {
        'installments': [
          cloudInstallment(
            syncId: 'inst-sync-2',
            number: 2,
            dueDate: newDueDate,
            local: before[1],
            updatedAt: cloudUpdatedAt,
          ),
        ],
      };

      // RUTA REAL: cloud -> SyncService -> merge -> SQLite -> caches -> repos.
      await syncService.downloadUpdatesForScopes(['installments']);

      expect(apiClient.downloadCalls, greaterThan(0));

      // SQLITE UPDATED: la cuota 2 quedo con el vencimiento de la nube.
      final after = await cuotasOf(saleId);
      final dueDate2 = DateTime.parse(after[1]['fecha_vencimiento'] as String);
      expect(
        InstallmentStatusResolver.businessDateKey(dueDate2),
        InstallmentStatusResolver.businessDateKey(newDueDate),
      );
      expect(after, hasLength(6), reason: 'la descarga no duplica cuotas');

      // El conteo DERIVADO ya refleja 2 vencidas sin reiniciar ni limpiar cache.
      expect(await _listOverdue(salesRepository, saleId), 2);
      expect(await _detailOverdue(salesRepository, saleId), 2);

      // Sin efectos colaterales en la outbox ni conflictos.
      expect(await countOf('sync_queue'), 0);
      expect(await countOf('conflict_logs'), 0);
    },
  );

  test(
    'B2: descarga sin registros financieros no altera el estado (sin invalidacion innecesaria)',
    () async {
      final saleId = await seedSaleWithOneOverdue();
      final before = await cuotasOf(saleId);

      apiClient.recordsByScope = {'installments': const []};
      await syncService.downloadUpdatesForScopes(['installments']);

      final after = await cuotasOf(saleId);
      for (var i = 0; i < before.length; i++) {
        expect(
          after[i]['fecha_vencimiento'],
          before[i]['fecha_vencimiento'],
          reason: 'una descarga vacia no puede tocar el calendario',
        );
        expect(after[i]['monto_pagado'], before[i]['monto_pagado']);
        expect(after[i]['capital_cuota'], before[i]['capital_cuota']);
      }
      expect(await _listOverdue(salesRepository, saleId), 1);
      expect(await countOf('sync_queue'), 0);
      expect(await countOf('conflict_logs'), 0);
    },
  );

  test(
    'B4: un registro remoto rancio no revierte a un estado mas nuevo',
    () async {
      final saleId = await seedSaleWithOneOverdue();
      final before = await cuotasOf(saleId);
      final staleUpdatedAt = DateTime.now().toUtc().subtract(
        const Duration(days: 3),
      );
      final staleRecord = cloudInstallment(
        syncId: 'inst-sync-2',
        number: 2,
        dueDate: anchor.add(const Duration(days: 250)),
        local: before[1],
        updatedAt: staleUpdatedAt,
      );

      // Primero llega la version NUEVA (vencimiento en el pasado -> 2 vencidas).
      final newDueDate = anchor.subtract(const Duration(days: 2));
      apiClient.recordsByScope = {
        'installments': [
          cloudInstallment(
            syncId: 'inst-sync-2',
            number: 2,
            dueDate: newDueDate,
            local: before[1],
            updatedAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          ),
        ],
      };
      await syncService.downloadUpdatesForScopes(['installments']);
      expect(await _listOverdue(salesRepository, saleId), 2);

      // Despues reingresa el MISMO registro rancio: no puede revertir el estado.
      apiClient.filterByScopeCursor = false;
      apiClient.recordsByScope = {
        'installments': [staleRecord],
      };
      await syncService.downloadUpdatesForScopes(['installments']);

      final after = await cuotasOf(saleId);
      final dueDate2 = DateTime.parse(after[1]['fecha_vencimiento'] as String);
      expect(
        InstallmentStatusResolver.businessDateKey(dueDate2),
        InstallmentStatusResolver.businessDateKey(newDueDate),
        reason: 'un payload rancio no puede revertir el vencimiento vigente',
      );
      expect(await _listOverdue(salesRepository, saleId), 2);
      expect(await _detailOverdue(salesRepository, saleId), 2);
      expect(await countOf('sync_queue'), 0);
      expect(await countOf('conflict_logs'), 0);
    },
  );

  test(
    'B1b (VERIFICADO): la nube no marca pagada una cuota sin pago local; el dinero real si',
    () async {
      final saleId = await seedSaleWithOneOverdue();
      final before = await cuotasOf(saleId);
      final cuota2 = before[1];
      final total = (cuota2['monto_cuota'] as num).toDouble();
      final baselinePagos = await countOf('pagos');
      final cloudUpdatedAt = DateTime.now().toUtc().add(
        const Duration(minutes: 5),
      );

      // La nube afirma "pagada" pero NO trae el pago correspondiente en `pagos`.
      apiClient.recordsByScope = {
        'installments': [
          cloudInstallment(
            syncId: 'inst-sync-2',
            number: 2,
            dueDate: DateTime.parse(cuota2['fecha_vencimiento'] as String),
            local: cuota2,
            updatedAt: cloudUpdatedAt,
            paidAmount: total,
            paidPrincipalAmount: (cuota2['capital_cuota'] as num).toDouble(),
          ),
        ],
      };
      await syncService.downloadUpdatesForScopes(['installments']);

      // COMPORTAMIENTO CANONICO (P0 cloud authority): PostgreSQL es la autoridad
      // del negocio. Una cuota que la nube entrega PAGADA se respeta aunque la
      // fila Payment todavia no se haya hidratado; el local NO la degrada.
      final afterDownload = await cuotasOf(saleId);
      expect(
        (afterDownload[1]['monto_pagado'] as num).toDouble(),
        closeTo(total, 0.01),
      );
      expect(afterDownload[1]['estado'], 'pagada');
      // FASE 23: la UI/historial no inventa una fila Payment sintetica.
      expect(
        await countOf('pagos'),
        baselinePagos,
        reason: 'no puede aparecer un pago fantasma',
      );

      // Con el DINERO real aplicado localmente, la cuota si queda pagada.
      await harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: anchor,
          amountPaid: total,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuota',
          targetInstallmentId: cuota2['id'] as int,
        ),
      );
      final afterPayment = await cuotasOf(saleId);
      expect(
        (afterPayment[1]['monto_pagado'] as num).toDouble(),
        closeTo(total, 0.01),
      );
      expect(afterPayment[1]['estado'], 'pagada');
      expect(await countOf('sync_queue'), 0);
    },
  );

  test(
    'A8: el abono a capital local no se aplica dos veces tras descargar la nube',
    () async {
      final saleId = await harness.createFinancedSale(
        saleDate: anchor,
        installmentCount: 6,
      );
      final db = await appDatabase.database;
      final saleRows = await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      saleSyncId = saleRows.first['sync_id'] as String;
      final cuotas = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
        orderBy: 'numero_cuota ASC',
      );
      for (final cuota in cuotas) {
        await db.update(
          DatabaseSchema.installmentsTable,
          {
            'sync_id': 'inst-sync-${cuota['numero_cuota']}',
            'sync_status': DatabaseSchema.syncStatusSynced,
          },
          where: 'id = ?',
          whereArgs: [cuota['id']],
        );
      }

      // 1) Abono a capital offline: efecto financiero local + intencion en outbox.
      await harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: anchor,
          amountPaid: 5000,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'abono_capital',
        ),
      );
      final afterLocal = await cuotasOf(saleId);
      final capitalLocal = afterLocal.fold<double>(
        0,
        (sum, row) => sum + (row['capital_cuota'] as num).toDouble(),
      );
      final pagosLocal = await countOf('pagos');

      // 2) La nube confirma el calendario resultante (misma foto, ya aplicada).
      final cloudUpdatedAt = DateTime.now().toUtc().add(
        const Duration(minutes: 5),
      );
      apiClient.recordsByScope = {
        'installments': [
          for (final row in afterLocal)
            cloudInstallment(
              syncId: 'inst-sync-${row['numero_cuota']}',
              number: row['numero_cuota'] as int,
              dueDate: DateTime.parse(row['fecha_vencimiento'] as String),
              local: row,
              updatedAt: cloudUpdatedAt,
            ),
        ],
      };
      await syncService.downloadUpdatesForScopes(['installments']);

      // 3) Reconciliacion: NO se duplica el pago ni se vuelve a bajar el capital.
      final afterDownload = await cuotasOf(saleId);
      final capitalFinal = afterDownload.fold<double>(
        0,
        (sum, row) => sum + (row['capital_cuota'] as num).toDouble(),
      );
      expect(
        capitalFinal,
        closeTo(capitalLocal, 0.01),
        reason: 'el capital no puede reducirse dos veces',
      );
      expect(
        await countOf('pagos'),
        pagosLocal,
        reason: 'no puede aparecer un pago duplicado',
      );
      expect(await countOf('sync_queue'), 0);
      expect(await countOf('conflict_logs'), 0);
    },
  );
}

Future<int> _listOverdue(SalesRepository repository, int saleId) async {
  final summaries = await repository.fetchAll();
  final matches = summaries.where((item) => item.id == saleId).toList();
  expect(matches, hasLength(1));
  return matches.first.overdueInstallmentCount;
}

Future<int> _detailOverdue(SalesRepository repository, int saleId) async {
  final detail = await repository.fetchDetail(saleId);
  expect(detail, isNotNull);
  return detail!.overdueInstallmentCount;
}
