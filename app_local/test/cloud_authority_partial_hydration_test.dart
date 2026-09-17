import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/business/installment_status.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

import 'helpers/fake_sync_download_api_client.dart';
import 'helpers/payment_application_test_harness.dart';

/// P0 CLOUD AUTHORITY — HIDRATACION PARCIAL
///
/// PRINCIPIO: PostgreSQL es la UNICA autoridad del negocio. SQLite local es
/// cache/outbox/estado offline provisional. Ningun registro autoritativo de la
/// nube puede ser DEGRADADO por el hecho de que otra tabla local todavia no se
/// haya hidratado (p. ej. la cuota llega `pagada` y el pago aun no bajo).
///
/// Este archivo demuestra el downgrade ANTES del fix y luego lo congela como
/// invariante permanente.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime anchor;

  setUpAll(() {
    anchor = DateTime.parse(InstallmentStatusResolver.currentBusinessDateKey());
  });

  /// Escenario base: venta con 6 cuotas, cuota 1 impaga y ya sincronizada.
  Future<_AuthorityHarness> boot() async {
    final harness = await PaymentApplicationTestHarness.create();
    final saleId = await harness.createFinancedSale(
      saleDate: anchor,
      installmentCount: 6,
    );
    final db = await harness.appDatabase.database;
    final saleRow = (await db.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).first;
    final saleSyncId = saleRow['sync_id'] as String;
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
    // El merge de `payments` resuelve la venta/cliente/cuota por sync_id.
    await db.update(
      DatabaseSchema.clientsTable,
      {
        'sync_id': 'client-sync-local',
        'sync_status': DatabaseSchema.syncStatusSynced,
      },
      where: 'id = ?',
      whereArgs: [saleRow['cliente_id']],
    );

    final config = SyncConfigRepository(
      settingsRepository: SettingsRepository(appDatabase: harness.appDatabase),
      preferencesFactory: SharedPreferences.getInstance,
    );
    final api = FakeSyncDownloadApiClient()..filterByScopeCursor = false;
    final queue = SyncQueueService.test(
      appDatabase: harness.appDatabase,
      configRepository: config,
      apiClient: api,
      conflictService: SyncConflictService(appDatabase: harness.appDatabase),
    );
    final sync = SyncService(
      repositories: [
        SalesSyncRepository(appDatabase: harness.appDatabase),
        InstallmentsSyncRepository(appDatabase: harness.appDatabase),
        PaymentsSyncRepository(appDatabase: harness.appDatabase),
      ],
      configRepository: config,
      apiClient: api,
      syncQueueService: queue,
      appDatabase: harness.appDatabase,
      allowCloudPullOverride: true,
    );
    await config.saveBaseUrl('http://127.0.0.1:9999/api');
    await config.saveJwtToken('jwt-test');

    return _AuthorityHarness(
      harness: harness,
      api: api,
      sync: sync,
      saleId: saleId,
      saleSyncId: saleSyncId,
      installmentTotal: (cuotas.first['monto_cuota'] as num).toDouble(),
    );
  }

  test(
    'FASE 3 / ORDEN A: la cuota pagada de la nube NO se degrada porque el pago no haya bajado',
    () async {
      final h = await boot();
      addTearDown(h.dispose);
      final pagosAntes = await h.paymentsCount();

      // ORDEN A: primero la cuota (pagada, version 5), todavia sin el pago.
      h.api.recordsByScope = {
        'installments': [h.paidInstallmentRecord(number: 1, version: 5)],
      };
      await h.sync.downloadUpdatesForScopes(['installments']);

      // El dato autoritativo NO puede volver a pendiente/0.
      final cuota = await h.installment(1);
      expect(
        (cuota['monto_pagado'] as num).toDouble(),
        closeTo(h.installmentTotal, 0.01),
        reason: 'paid_amount de PostgreSQL es autoritativo',
      );
      expect(cuota['estado'], 'pagada');
      // FASE 23: sin fila Payment sintetica (el baseline incluye el pago inicial).
      expect(await h.paymentsCount(), pagosAntes);
    },
  );

  test(
    'FASE 4 / ORDEN B: bajar primero el pago y despues la cuota da el MISMO estado final',
    () async {
      final h = await boot();
      addTearDown(h.dispose);
      final pagosAntes = await h.paymentsCount();

      h.api.recordsByScope = {
        'payments': [h.paymentRecord(version: 5)],
      };
      await h.sync.downloadUpdatesForScopes(['payments']);

      h.api.recordsByScope = {
        'installments': [h.paidInstallmentRecord(number: 1, version: 6)],
      };
      await h.sync.downloadUpdatesForScopes(['installments']);

      final cuota = await h.installment(1);
      expect(
        (cuota['monto_pagado'] as num).toDouble(),
        closeTo(h.installmentTotal, 0.01),
      );
      expect(cuota['estado'], 'pagada');
      expect(await h.paymentsCount(), pagosAntes + 1);
    },
  );

  test(
    'P0 identity bridge: una intencion offline 1->N no queda duplicada en historial',
    () async {
      final h = await boot();
      addTearDown(h.dispose);
      final pagosBase = await h.livePaymentsCount();
      final totalBase = await h.livePaymentTotal();

      await h.harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: h.saleId,
          amountPaid: h.installmentTotal,
          paymentMethod: 'efectivo',
          paymentDate: anchor,
          paymentTypeOverride: 'cuota',
          targetInstallmentId: (await h.installment(1))['id'] as int,
        ),
      );
      expect(await h.livePaymentsCount(), pagosBase + 1);

      final provisionalSyncId = await h.latestPaymentSyncId();
      h.api.recordsByScope = {
        'payments': [
          h.paymentRecord(
            syncId: 'payment-auth-child-1',
            sourceSyncId: provisionalSyncId,
            amountPaid: h.installmentTotal / 2,
            version: 7,
          ),
          h.paymentRecord(
            syncId: 'payment-auth-child-2',
            sourceSyncId: provisionalSyncId,
            amountPaid: h.installmentTotal / 2,
            paymentType: 'abono_capital',
            installmentSyncId: null,
            version: 8,
          ),
        ],
      };
      await h.sync.downloadUpdatesForScopes(['payments']);

      expect(
        await h.paymentDeletedAt(provisionalSyncId),
        isNotNull,
        reason: 'la intencion provisional queda resuelta/oculta',
      );
      expect(
        await h.livePaymentsCount(),
        pagosBase + 2,
        reason: 'solo se cuentan las dos filas autoritativas, no la provisional',
      );
      expect(
        await h.livePaymentTotal(),
        closeTo(totalBase + h.installmentTotal, 0.01),
        reason:
            'baseline inicial + hijos autoritativos; la provisional no se suma',
      );
    },
  );

  test(
    'FASE 5/21: el resultado final NO depende del orden de llegada de los scopes',
    () async {
      final orders = <List<List<String>>>[
        [
          ['installments'],
          ['payments'],
        ],
        [
          ['payments'],
          ['installments'],
        ],
        [
          ['sales'],
          ['installments'],
          ['payments'],
        ],
        [
          ['payments'],
          ['sales'],
          ['installments'],
        ],
      ];

      final snapshots = <String>[];
      final labels = <String>[];
      for (final order in orders) {
        final h = await boot();
        try {
          for (final scopes in order) {
            h.api.recordsByScope = {
              if (scopes.contains('sales'))
                'sales': [h.cloudSaleRecord(version: 5)],
              if (scopes.contains('installments'))
                'installments': [h.paidInstallmentRecord(number: 1, version: 5)],
              if (scopes.contains('payments'))
                'payments': [h.paymentRecord(version: 5)],
            };
            await h.sync.downloadUpdatesForScopes(scopes);
          }
          labels.add(order.map((s) => s.join('+')).join(' -> '));
          snapshots.add(await h.businessState());
        } finally {
          await h.dispose();
        }
      }

      for (var i = 1; i < snapshots.length; i++) {
        expect(
          snapshots[i],
          snapshots[0],
          reason: 'el orden ${labels[i]} no puede dar otro estado que ${labels[0]}',
        );
      }
      // Y el estado convergido es el de la nube: cuota 1 pagada.
      expect(snapshots.first, contains('c1:${h1Total(snapshots.first)}'));
    },
  );

  test(
    'FASE 11: una version cloud mas nueva gana y el reconcile local no la vuelve a degradar',
    () async {
      final h = await boot();
      addTearDown(h.dispose);

      final db = await h.harness.appDatabase.database;
      await db.update(
        DatabaseSchema.installmentsTable,
        {'version': 4},
        where: 'venta_id = ? AND numero_cuota = 1',
        whereArgs: [h.saleId],
      );

      h.api.recordsByScope = {
        'installments': [h.paidInstallmentRecord(number: 1, version: 5)],
      };
      await h.sync.downloadUpdatesForScopes(['installments']);

      final cuota = await h.installment(1);
      expect(cuota['estado'], 'pagada');
      expect((cuota['version'] as num).toInt(), 5);
    },
  );

  test(
    'PARTE D/E/H: la liquidacion converge igual en 5 ordenes de scopes y no duplica',
    () async {
      final orders = <List<String>>[
        ['sales', 'installments', 'payments'],
        ['payments', 'installments', 'sales'],
        ['installments', 'payments', 'sales'],
        ['payments', 'sales', 'installments'],
        ['installments', 'sales', 'payments'],
      ];
      final finales = <String>[];
      for (final order in orders) {
        final h = await boot();
        try {
          for (final scope in order) {
            h.api.recordsByScope = h.settlementCloudState(scope);
            await h.sync.downloadUpdatesForScopes([scope]);
          }
          finales.add(await h.businessState());
        } finally {
          await h.dispose();
        }
      }

      for (var i = 1; i < finales.length; i++) {
        expect(
          finales[i],
          finales[0],
          reason: 'el orden ${orders[i].join('->')} debe dar el mismo estado final',
        );
      }
      // Estado autoritativo esperado: venta saldada, sin duplicados.
      expect(finales.first, contains('saldo:0.00'));
      expect(finales.first, contains('c1:${h1Total(finales.first)}:pagada'));
      // 1 = pago inicial de la venta (fixture), 1 = pago de liquidacion.
      expect(finales.first, contains('pagosVivos:2'));
    },
  );

  test(
    'PARTE D2/H: anular la liquidacion converge en 4 ordenes y no resucita el pago',
    () async {
      final orders = <List<String>>[
        ['payments', 'installments', 'sales'],
        ['installments', 'payments', 'sales'],
        ['sales', 'installments', 'payments'],
        ['installments', 'sales', 'payments'],
      ];
      final finales = <String>[];
      for (final order in orders) {
        final h = await boot();
        try {
          // 1) Estado autoritativo con la liquidacion aplicada.
          for (final scope in ['sales', 'installments', 'payments']) {
            h.api.recordsByScope = h.settlementCloudState(scope);
            await h.sync.downloadUpdatesForScopes([scope]);
          }
          expect((await h.installment(1))['estado'], 'pagada');

          // 2) Anulacion: tombstone del pago + cuotas corregidas + venta activa,
          //    llegando en el orden indicado.
          for (final scope in order) {
            h.api.recordsByScope = h.settlementCloudState(scope, annulled: true);
            await h.sync.downloadUpdatesForScopes([scope]);
          }
          finales.add(await h.businessState());
        } finally {
          await h.dispose();
        }
      }

      for (var i = 1; i < finales.length; i++) {
        expect(
          finales[i],
          finales[0],
          reason: 'el orden ${orders[i].join('->')} debe dar el mismo estado final',
        );
      }
      // Sin resurreccion del pago (solo queda vivo el pago inicial del fixture).
      expect(finales.first, contains('pagosVivos:1'));
      // El registro autoritativo MAS NUEVO gana y la cuota vuelve a impaga.
      // NOTA (correccion de un diagnostico previo mio): el "defecto" reportado
      // antes era un ERROR DE FIXTURE — la anulacion llegaba con `version` MENOR
      // que la local, y `_shouldKeepLocal` protege correctamente un local de
      // version mayor. La anulacion real de PostgreSQL siempre llega con la
      // version incrementada, por lo que el remoto gana.
      expect(finales.first, contains('c1:0.00:pendiente'));
    },
  );

  test(
    'PARTE E: sin intencion local pendiente, el estado local converge al de PostgreSQL',
    () async {
      final h = await boot();
      addTearDown(h.dispose);

      // Nube autoritativa: cuota 1 pagada; llega SOLO el scope de cuotas.
      h.api.recordsByScope = {
        'installments': [h.paidInstallmentRecord(number: 1, version: 5)],
      };
      await h.sync.downloadUpdatesForScopes(['installments']);
      final parcial = await h.businessState();

      // Completar el resto de scopes no puede cambiar el resultado financiero
      // (no habia intencion local pendiente).
      h.api.recordsByScope = h.settlementCloudState('payments');
      await h.sync.downloadUpdatesForScopes(['payments']);
      expect((await h.installment(1))['estado'], 'pagada');
      expect(parcial, contains('c1:${h1Total(parcial)}:pagada'));
      // 1 = pago inicial del fixture, 1 = pago de liquidacion descargado.
      expect(await h.livePaymentsCount(), 2);
    },
  );

  test(
    'FASE 15/16: anulacion y tombstone del pago convergen sin depender del orden',
    () async {
      // Orden 1: pago -> anulacion -> cuota corregida.
      // Orden 2: cuota corregida -> tombstone del pago.
      final finales = <String>[];
      for (final ordenTombstonePrimero in [false, true]) {
        final h = await boot();
        try {
          // Estado de partida: el pago existe y la cuota esta pagada (cloud).
          h.api.recordsByScope = {
            'payments': [h.paymentRecord(version: 5)],
          };
          await h.sync.downloadUpdatesForScopes(['payments']);
          h.api.recordsByScope = {
            'installments': [h.paidInstallmentRecord(number: 1, version: 5)],
          };
          await h.sync.downloadUpdatesForScopes(['installments']);
          expect((await h.installment(1))['estado'], 'pagada');

          final cuotaCorregida = h.unpaidInstallmentRecord(number: 1);
          final pagoAnulado = h.paymentRecord(version: 9, deleted: true);

          if (ordenTombstonePrimero) {
            h.api.recordsByScope = {
              'payments': [pagoAnulado],
            };
            await h.sync.downloadUpdatesForScopes(['payments']);
            h.api.recordsByScope = {
              'installments': [cuotaCorregida],
            };
            await h.sync.downloadUpdatesForScopes(['installments']);
          } else {
            h.api.recordsByScope = {
              'installments': [cuotaCorregida],
            };
            await h.sync.downloadUpdatesForScopes(['installments']);
            h.api.recordsByScope = {
              'payments': [pagoAnulado],
            };
            await h.sync.downloadUpdatesForScopes(['payments']);
          }

          finales.add(await h.businessState());
        } finally {
          await h.dispose();
        }
      }

      expect(
        finales[1],
        finales[0],
        reason: 'el orden de anulacion/tombstone no puede cambiar el estado final',
      );
      // La anulacion restablece la deuda (la cuota vuelve a estar impaga).
      expect(finales[0], contains('c1:0.00:'));
    },
  );

  test(
    'INTENCION LOCAL REAL: un pago offline pendiente NO se pierde ante un snapshot remoto',
    () async {
      final h = await boot();
      addTearDown(h.dispose);

      // El usuario registra un pago OFFLINE (intencion real, aun sin ACK).
      await h.harness.paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: h.saleId,
          paymentDate: anchor,
          amountPaid: h.installmentTotal,
          paymentMethod: 'efectivo',
          paymentTypeOverride: 'cuota',
          targetInstallmentId: (await h.installment(1))['id'] as int,
        ),
      );
      expect((await h.installment(1))['estado'], 'pagada');
      final pagosVivos = await h.livePaymentsCount();

      // La nube todavia NO conoce ese pago y envia un snapshot con paidAmount 0
      // y version MAYOR (el caso mas adverso): la intencion local no puede
      // perderse antes de ACK/REJECTION.
      h.api.recordsByScope = {
        'installments': [h.unpaidInstallmentRecord(number: 1)],
      };
      await h.sync.downloadUpdatesForScopes(['installments']);

      expect(
        (await h.installment(1))['estado'],
        'pagada',
        reason: 'la intencion local no resuelta debe conservarse',
      );
      expect(await h.livePaymentsCount(), pagosVivos);
    },
  );
}

/// Extrae el total pagado esperado de la cuota 1 a partir del snapshot.
double h1Total(String snapshot) {
  final match = RegExp(r'c1:([0-9.]+):pagada').firstMatch(snapshot);
  expect(match, isNotNull, reason: 'la cuota 1 debe quedar pagada: $snapshot');
  return double.parse(match!.group(1)!);
}

class _AuthorityHarness {
  _AuthorityHarness({
    required this.harness,
    required this.api,
    required this.sync,
    required this.saleId,
    required this.saleSyncId,
    required this.installmentTotal,
  });

  final PaymentApplicationTestHarness harness;
  final FakeSyncDownloadApiClient api;
  final SyncService sync;
  final int saleId;
  final String saleSyncId;
  final double installmentTotal;

  Future<void> dispose() => harness.dispose();

  Future<Map<String, Object?>> installment(int number) async {
    final db = await harness.appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ? AND numero_cuota = ?',
      whereArgs: [saleId, number],
      limit: 1,
    );
    return rows.first;
  }

  Future<int> paymentsCount() async {
    final db = await harness.appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DatabaseSchema.paymentsTable}',
    );
    return (rows.first['total'] as num).toInt();
  }

  /// Estado de negocio canonico: cuotas + saldo/estado de la venta + pagos.
  Future<String> businessState() async {
    final db = await harness.appDatabase.database;
    final cuotas = await db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
      orderBy: 'numero_cuota ASC',
    );
    final venta = (await db.query(
      DatabaseSchema.salesTable,
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).first;
    final parts = <String>[
      'saldo:${(venta['saldo_pendiente'] as num).toStringAsFixed(2)}',
      'estadoVenta:${venta['estado']}',
      for (final cuota in cuotas)
        'c${cuota['numero_cuota']}:${(cuota['monto_pagado'] as num).toStringAsFixed(2)}:${cuota['estado']}',
      'pagos:${await paymentsCount()}',
      'pagosVivos:${await livePaymentsCount()}',
    ];
    return parts.join('|');
  }

  Map<String, dynamic> paidInstallmentRecord({
    required int number,
    required int version,
  }) {
    final ahora = DateTime.now().toUtc().add(Duration(minutes: version));
    return {
      'id': 'remote-inst-$number',
      'sync_id': 'inst-sync-$number',
      'sale_sync_id': saleSyncId,
      'version': version,
      'installment_number': number,
      'due_date': '2026-09-20T00:00:00.000',
      'opening_balance': 1000.0,
      'principal_amount': 900.0,
      'interest_amount': 100.0,
      'total_amount': installmentTotal,
      'paid_amount': installmentTotal,
      'paid_principal_amount': 900.0,
      'paid_interest_amount': 100.0,
      'ending_balance': 0.0,
      'status': 'pagada',
      'created_at': '2026-08-20T00:00:00.000',
      'updated_at': ahora.toIso8601String(),
      'deleted_at': null,
    };
  }

  /// Estado autoritativo de la nube tras una LIQUIDACION (o su anulacion),
  /// por scope. Permite probar la convergencia independiente del orden.
  Map<String, List<Map<String, dynamic>>> settlementCloudState(
    String scope, {
    bool annulled = false,
  }) {
    final version = annulled ? 20 : 10;
    if (scope == 'sales') {
      final record = cloudSaleRecord(version: version);
      record['pending_balance'] = annulled ? 90000.0 : 0.0;
      record['status'] = annulled ? 'activa' : 'pagada';
      return {'sales': [record]};
    }
    if (scope == 'payments') {
      final record = paymentRecord(version: version, deleted: annulled);
      record['sync_id'] = 'payment-sync-settle';
      record['payment_type'] = 'liquidacion';
      return {'payments': [record]};
    }
    return {
      'installments': [
        for (var number = 1; number <= 6; number++)
          annulled
              ? unpaidInstallmentRecord(number: number)
              : paidInstallmentRecord(number: number, version: version),
      ],
    };
  }

  Future<int> livePaymentsCount() async {
    final db = await harness.appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DatabaseSchema.paymentsTable} '
      'WHERE deleted_at IS NULL',
    );
    return (rows.first['total'] as num).toInt();
  }

  Future<double> livePaymentTotal() async {
    final db = await harness.appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(monto_pagado), 0) AS total '
      'FROM ${DatabaseSchema.paymentsTable} WHERE deleted_at IS NULL',
    );
    return (rows.first['total'] as num).toDouble();
  }

  Future<String> latestPaymentSyncId() async {
    final db = await harness.appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.paymentsTable,
      columns: ['sync_id'],
      where: 'deleted_at IS NULL',
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.first['sync_id'] as String;
  }

  Future<String?> paymentDeletedAt(String syncId) async {
    final db = await harness.appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.paymentsTable,
      columns: ['deleted_at'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    return rows.first['deleted_at'] as String?;
  }

  Map<String, dynamic> paymentRecord({
    required int version,
    bool deleted = false,
    String syncId = 'payment-sync-1',
    String? sourceSyncId,
    double? amountPaid,
    String paymentType = 'cuota',
    String? installmentSyncId = 'inst-sync-1',
  }) {
    final ahora = DateTime.now().toUtc().add(Duration(minutes: version));
    return {
      'id': 'remote-pay-1',
      'sync_id': syncId,
      'sale_sync_id': saleSyncId,
      'client_sync_id': 'client-sync-local',
      'installment_sync_id': installmentSyncId,
      'source_payment_sync_id': sourceSyncId,
      'payment_date': '2026-09-16T00:00:00.000',
      'amount_paid': amountPaid ?? installmentTotal,
      'payment_method': 'efectivo',
      'payment_type': paymentType,
      'reference': 'REF-1',
      'year_to_pay': null,
      'created_at': '2026-09-16T00:00:00.000',
      'updated_at': ahora.toIso8601String(),
      'deleted_at': deleted ? ahora.toIso8601String() : null,
    };
  }

  /// La nube corrige la cuota a impaga (efecto autoritativo de la anulacion).
  Map<String, dynamic> unpaidInstallmentRecord({required int number}) {
    return {
      'id': 'remote-inst-$number',
      'sync_id': 'inst-sync-$number',
      'sale_sync_id': saleSyncId,
      'version': 30,
      'installment_number': number,
      'due_date': '2026-09-20T00:00:00.000',
      'opening_balance': 1000.0,
      'principal_amount': 900.0,
      'interest_amount': 100.0,
      'total_amount': installmentTotal,
      'paid_amount': 0.0,
      'paid_principal_amount': 0.0,
      'paid_interest_amount': 0.0,
      'ending_balance': 1000.0,
      'status': 'pendiente',
      'created_at': '2026-08-20T00:00:00.000',
      'updated_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String(),
      'deleted_at': null,
    };
  }

  Map<String, dynamic> cloudSaleRecord({required int version}) {
    final ahora = DateTime.now().toUtc().add(Duration(minutes: version));
    return {
      'id': 'remote-sale-1',
      'sync_id': saleSyncId,
      'sale_date': '2026-09-16T00:00:00.000',
      'sale_price': 100000.0,
      'down_payment_percentage': 10.0,
      'down_payment_amount': 10000.0,
      'required_initial_payment': 10000.0,
      'paid_initial_payment': 10000.0,
      'pending_initial_payment': 0.0,
      'minimum_reserve_amount': null,
      'initial_payment_deadline': null,
      'activation_date': '2026-09-16T00:00:00.000',
      'financed_balance': 90000.0,
      'pending_balance': 77529.35300397929,
      'monthly_interest': 1.0,
      'installment_count': 6,
      'status': 'activa',
      'created_at': '2026-09-16T00:00:00.000',
      'updated_at': ahora.toIso8601String(),
      'deleted_at': null,
      'client_sync_id': null,
      'product_sync_id': null,
      'seller_sync_id': null,
    };
  }
}
