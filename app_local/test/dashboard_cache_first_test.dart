import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/cloud_foundation/sales_cache_invalidation.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/features/dashboard/data/dashboard_stats_store.dart';
import 'package:sistema_solares/services/sync/sync_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Hotfix P0 — cache-first del Resumen y cap de log de sync.
///
/// Estas pruebas fijan el contrato del read model que evita el spinner de 1-2
/// minutos: el snapshot vive FUERA de la pantalla, sobrevive a la navegación y
/// se refresca en background sin bloquear el primer pintado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const sample = DashboardStats(
    totalClients: 98,
    totalLots: 143,
    availableLots: 40,
    soldLots: 103,
    pendingPayments: 11871,
    incompleteInitialPayments: 0,
    overduePayments: 164,
    activeFinancing: 110,
    portfolioPendingAmount: 56131963.50,
    collectedAmount: 21174698.90,
    soldAmount: 68304394.00,
  );

  setUp(() => DashboardStatsStore.instance.clear());
  tearDown(() => DashboardStatsStore.instance.clear());

  group('DashboardStatsStore (cache-first del Resumen)', () {
    test('sin snapshot no hay datos: sólo aquí se justifica el spinner', () {
      expect(DashboardStatsStore.instance.hasSnapshot, isFalse);
      expect(DashboardStatsStore.instance.stats, isNull);
      expect(DashboardStatsStore.instance.needsRefresh, isTrue);
    });

    test('con snapshot se puede pintar de inmediato', () {
      DashboardStatsStore.instance.save(sample);

      expect(DashboardStatsStore.instance.hasSnapshot, isTrue);
      expect(DashboardStatsStore.instance.stats?.collectedAmount, 21174698.90);
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);
    });

    test(
      'el snapshot SOBREVIVE a cambiar de módulo (Resumen -> Clientes -> Resumen)',
      () {
        // El shell reconstruye el widget al navegar; el store es singleton, así
        // que el snapshot sigue disponible para pintar sin spinner al volver.
        DashboardStatsStore.instance.save(sample);

        // Simula destruir y recrear la pantalla: nada del store se borra.
        expect(DashboardStatsStore.instance.hasSnapshot, isTrue);
        expect(DashboardStatsStore.instance.stats?.overduePayments, 164);
      },
    );

    test('tres entradas seguidas NO disparan tres cálculos', () async {
      var runs = 0;
      Future<void> task() async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      DashboardStatsStore.instance.save(sample);
      // El intervalo mínimo hace que las visitas inmediatas no refresquen.
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);

      // Y si dos llamadas coinciden, el guard ejecuta UNA sola.
      await Future.wait([
        DashboardRefreshGuard.run(task),
        DashboardRefreshGuard.run(task),
        DashboardRefreshGuard.run(task),
      ]);
      expect(runs, 1);
    });

    test('cambio de día invalida las métricas dependientes de fecha', () {
      DashboardStatsStore.instance.debugSeed(
        sample,
        loadedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(DashboardStatsStore.instance.needsRefresh, isTrue);
    });

    test('invalidate() fuerza refresco tras una operación financiera', () {
      DashboardStatsStore.instance.save(sample);
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);

      // Pago / venta / anulación / descarga de nube relevante.
      DashboardStatsStore.instance.invalidate();

      expect(DashboardStatsStore.instance.needsRefresh, isTrue);
      // El snapshot NO se descarta: se sigue pintando mientras refresca.
      expect(DashboardStatsStore.instance.hasSnapshot, isTrue);
    });

    test('el guard nunca deja un cálculo colgado', () async {
      await DashboardRefreshGuard.run(() async {});
      expect(DashboardRefreshGuard.isRunning, isFalse);
    });
  });

  group('SyncLogger (cap de tamaño)', () {
    test('rota sync.log cuando supera el cap (evita 282 MB)', () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'ss_log_cap_test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });

      final logger = SyncLogger(
        appPaths: AppPaths(supportDirectory: supportDirectory.path),
      );
      final logFile = File(
        path.join(supportDirectory.path, 'logs', 'sync.log'),
      );
      await logFile.parent.create(recursive: true);
      // Archivo por encima del cap.
      await logFile.writeAsBytes(
        List<int>.filled(SyncLogger.maxLogBytes + 1024, 65),
      );

      await logger.log(action: 'syncNow', entity: 'sync', result: 'started');

      final rotated = File(path.join(logFile.parent.path, 'sync.log.1'));
      expect(await rotated.exists(), isTrue, reason: 'debe rotar');
      expect(
        await logFile.length(),
        lessThan(SyncLogger.maxLogBytes),
        reason: 'el log activo debe quedar por debajo del cap',
      );
      // La evidencia reciente se conserva y el evento nuevo queda registrado.
      expect(await logFile.readAsString(), contains('syncNow'));
    });

    test('rota por rename: un log grande NO se copia ni bloquea', () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'ss_log_big_test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });

      final logger = SyncLogger(
        appPaths: AppPaths(supportDirectory: supportDirectory.path),
      );
      final logFile = File(
        path.join(supportDirectory.path, 'logs', 'sync.log'),
      );
      await logFile.parent.create(recursive: true);
      // ~48 MB: si la rotación copiara el contenido, esto tardaría mucho.
      await logFile.writeAsBytes(
        List<int>.filled(48 * 1024 * 1024, 65),
        flush: true,
      );

      final stopwatch = Stopwatch()..start();
      await logger.log(action: 'syncNow', entity: 'sync', result: 'started');
      stopwatch.stop();

      expect(
        await File(path.join(logFile.parent.path, 'sync.log.1')).exists(),
        isTrue,
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(3000),
        reason: 'debe ser un rename, no una copia de 48 MB',
      );
    });

    test('solo rota al superar el cap (no en cada evento)', () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'ss_log_once_test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });

      final logger = SyncLogger(
        appPaths: AppPaths(supportDirectory: supportDirectory.path),
      );
      await logger.log(action: 'syncNow', entity: 'sync', result: 'started');
      await logger.log(action: 'syncNow', entity: 'sync', result: 'ok');

      expect(
        await File(
          path.join(supportDirectory.path, 'logs', 'sync.log.1'),
        ).exists(),
        isFalse,
        reason: 'por debajo del cap no debe rotar',
      );
    });

    test('escribe eventos serializados con accion y resultado', () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'ss_log_write_test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });

      final logger = SyncLogger(
        appPaths: AppPaths(supportDirectory: supportDirectory.path),
      );
      await logger.log(
        action: 'syncNow',
        entity: 'sync',
        result: 'ok',
        extra: const {'downloadedRecords': 3},
      );

      final content = await File(
        path.join(supportDirectory.path, 'logs', 'sync.log'),
      ).readAsString();

      expect(content, contains('"action":"syncNow"'));
      expect(content, contains('"result":"ok"'));
      expect(content, contains('"downloadedRecords":3'));
    });
  });

  /// No basta con que `DashboardStatsStore.invalidate()` exista: tiene que estar
  /// CABLEADO a las operaciones que cambian los KPIs. Ventas, Pagos y la sync
  /// pasan por `SalesCacheInvalidation` (punto único), que publica una revisión;
  /// el store se suscribe a esa revisión.
  group('Invalidación real (venta / pago / anulación / nube)', () {
    late Directory tempDirectory;
    late AppDatabase appDatabase;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('ss_inval_');
      appDatabase = AppDatabase.test(
        path.join(tempDirectory.path, 'test.db'),
      );
      await appDatabase.initialize();
      DashboardStatsStore.instance.clear();
      DashboardStatsStore.instance.save(sample);
    });

    tearDown(() async {
      await appDatabase.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('invalidate() marca el snapshot como vencido SIN borrarlo', () {
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);

      DashboardStatsStore.instance.invalidate();

      expect(DashboardStatsStore.instance.needsRefresh, isTrue);
      expect(
        DashboardStatsStore.instance.stats?.overduePayments,
        164,
        reason: 'el snapshot se conserva para pintar de inmediato',
      );
    });

    test('una venta (invalidateSalesList) invalida el resumen', () async {
      final db = await appDatabase.database;

      await SalesCacheInvalidation.invalidateSalesList(db);

      expect(
        DashboardStatsStore.instance.needsRefresh,
        isTrue,
        reason: 'venta creada / modificada / anulada debe invalidar el resumen',
      );
    });

    test('un pago (invalidateFinancialDerivedCaches) invalida el resumen', () async {
      final db = await appDatabase.database;

      await SalesCacheInvalidation.invalidateFinancialDerivedCaches(db);

      expect(
        DashboardStatsStore.instance.needsRefresh,
        isTrue,
        reason: 'pago, pago parcial, abono y anulación pasan por aquí',
      );
    });

    test('una descarga de nube relevante borra el snapshot cacheado', () async {
      final db = await appDatabase.database;
      await db.insert(DatabaseSchema.listSnapshotsTable, {
        'cache_key': 'payments-work-queue:default',
        'query': '',
        'payload': '{"items":[]}',
        'updated_at': DateTime.now().toIso8601String(),
      });

      await SalesCacheInvalidation.invalidateFinancialDerivedCaches(db);

      final remaining = await db.query(
        DatabaseSchema.listSnapshotsTable,
        where: 'cache_key = ?',
        whereArgs: ['payments-work-queue:default'],
      );
      expect(remaining, isEmpty);
      expect(DashboardStatsStore.instance.needsRefresh, isTrue);
    });

    test('el snapshot viejo NO se sirve como fresco tras varias operaciones', () {
      DashboardStatsStore.instance.save(sample);
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);

      SalesCacheInvalidation.revision.value++;

      expect(DashboardStatsStore.instance.needsRefresh, isTrue);
    });
  });

  /// GAP REAL detectado tras iniciar las corridas: una descarga de nube de
  /// `clients` o `products` (los solares viajan bajo el scope `products`)
  /// cambia KPIs del Resumen pero NO entraba en `financialScopes`, así que el
  /// snapshot no se marcaba como vencido.
  ///
  /// Se usa `onCloudRecordsApplied`, el único punto de decisión que la sync
  /// invoca tras aplicar registros descargados.
  group('Invalidación por descarga de nube (gap clientes/solares)', () {
    late Directory tempDirectory;
    late AppDatabase appDatabase;
    late Database db;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('ss_cloud_inval_');
      appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
      await appDatabase.initialize();
      db = await appDatabase.database;
      DashboardStatsStore.instance.clear();
      DashboardStatsStore.instance.save(sample);
    });

    tearDown(() async {
      await appDatabase.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('cloud clients records>0 => dashboard invalidated', () async {
      await SalesCacheInvalidation.onCloudRecordsApplied(
        db,
        scope: 'clients',
        records: 3,
      );

      expect(
        DashboardStatsStore.instance.needsRefresh,
        isTrue,
        reason: 'el conteo de clientes mostrado en el Resumen cambió',
      );
      expect(
        DashboardStatsStore.instance.stats,
        isNotNull,
        reason: 'se invalida sin borrar: el snapshot sigue para pintar',
      );
    });

    test(
      'cloud solares/lotes (scope products) records>0 => dashboard invalidated',
      () async {
        // El scope REAL de solares/lotes es `products`.
        await SalesCacheInvalidation.onCloudRecordsApplied(
          db,
          scope: 'products',
          records: 2,
        );

        expect(DashboardStatsStore.instance.needsRefresh, isTrue);
      },
    );

    test('cloud clients records=0 => NO invalidation', () async {
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);

      await SalesCacheInvalidation.onCloudRecordsApplied(
        db,
        scope: 'clients',
        records: 0,
      );

      expect(
        DashboardStatsStore.instance.needsRefresh,
        isFalse,
        reason: 'una descarga vacía no cambia ningún KPI',
      );
    });

    test('scope irrelevante => NO invalidation', () async {
      for (final scope in const [
        'permissions',
        'roles',
        'role_permissions',
        'user_roles',
        'users',
        'company_profiles',
      ]) {
        await SalesCacheInvalidation.onCloudRecordsApplied(
          db,
          scope: scope,
          records: 5,
        );
      }

      expect(
        DashboardStatsStore.instance.needsRefresh,
        isFalse,
        reason: 'permisos/roles/usuarios no alimentan los KPIs del Resumen',
      );
    });

    test('financial scopes siguen invalidando como antes', () async {
      for (final scope in const ['sales', 'installments', 'payments']) {
        DashboardStatsStore.instance.clear();
        DashboardStatsStore.instance.save(sample);
        await db.insert(DatabaseSchema.listSnapshotsTable, {
          'cache_key': 'payments-work-queue:default',
          'query': '',
          'payload': '{"items":[]}',
          'updated_at': DateTime.now().toIso8601String(),
        });
        await db.insert(DatabaseSchema.salesListCacheTable, {
          'cache_key': SalesCacheInvalidation.salesListCacheKey,
          'query': '',
          'payload': '{"items":[]}',
          'updated_at': DateTime.now().toIso8601String(),
        });

        await SalesCacheInvalidation.onCloudRecordsApplied(
          db,
          scope: scope,
          records: 4,
        );

        expect(
          DashboardStatsStore.instance.needsRefresh,
          isTrue,
          reason: '$scope debe invalidar el Resumen',
        );
        expect(
          await db.query(DatabaseSchema.salesListCacheTable),
          isEmpty,
          reason: '$scope debe seguir borrando la cache de la lista de ventas',
        );
        expect(
          await db.query(DatabaseSchema.listSnapshotsTable),
          isEmpty,
          reason: '$scope debe seguir borrando la cola de pagos cacheada',
        );
      }
    });
  });
}
