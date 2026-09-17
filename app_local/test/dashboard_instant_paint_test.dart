import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/resilience/app_storage_namespace.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/dashboard/data/dashboard_stats_store.dart';
import 'package:sistema_solares/features/dashboard/presentation/dashboard_page.dart';
import 'package:sistema_solares/features/installments/data/installments_repository.dart';
import 'package:sistema_solares/features/installments/domain/installment_detail.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_summary.dart';

/// FIX P0 — el Resumen debe ABRIR DE UNA VEZ.
///
/// El writer del sync puede tener SQLite tomado 1-2 minutos. Estos tests fijan
/// que el primer pintado NO depende de SQLite: sale del snapshot en memoria o
/// del snapshot persistido, y el refresco sigue en background.
///
/// Los repositorios de estos tests NUNCA responden (gate sin completar), que es
/// exactamente el escenario "SQLite ocupado por el writer / sync lento".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const persisted = DashboardStats(
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

  final statsKey = AppStorageNamespace.scopedKey(
    DashboardStatsStore.persistedKey,
  );
  final savedAtKey = AppStorageNamespace.scopedKey(
    '${DashboardStatsStore.persistedKey}.savedAt',
  );

  setUp(() {
    DashboardStatsStore.instance.clear();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => DashboardStatsStore.instance.clear());

  group('Dashboard: primer pintado sin depender de SQLite', () {
    test('snapshot en memoria => hay datos para pintar de inmediato', () {
      DashboardStatsStore.instance.save(persisted);

      expect(DashboardStatsStore.instance.hasSnapshot, isTrue);
      expect(DashboardStatsStore.instance.stats?.totalClients, 98);
      // Recién guardado: no hace falta bloquear la pantalla esperando nada.
      expect(DashboardStatsStore.instance.needsRefresh, isFalse);
    });

    test('snapshot persistido => se hidrata sin tocar la base', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: jsonEncode(persisted.toJson()),
        savedAtKey: DateTime.now().toIso8601String(),
      });

      expect(DashboardStatsStore.instance.hasSnapshot, isFalse);
      await DashboardStatsStore.instance.hydrateFromDisk();

      expect(
        DashboardStatsStore.instance.hasSnapshot,
        isTrue,
        reason: 'el snapshot en disco es la fuente del primer pintado',
      );
      expect(DashboardStatsStore.instance.stats?.overduePayments, 164);
    });

    test('snapshot persistido viejo => se pinta y además pide refresco', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: jsonEncode(persisted.toJson()),
        savedAtKey: DateTime(
        2020,
        1,
        1,
      ).toIso8601String(),
      });

      await DashboardStatsStore.instance.hydrateFromDisk();

      expect(DashboardStatsStore.instance.hasSnapshot, isTrue);
      expect(
        DashboardStatsStore.instance.needsRefresh,
        isTrue,
        reason: 'dato viejo: se muestra y se refresca en background',
      );
    });

    test('snapshot persistido corrupto => NO rompe ni inventa ceros', () async {
      SharedPreferences.setMockInitialValues({statsKey: '{"totalClients":98}'});

      await DashboardStatsStore.instance.hydrateFromDisk();

      expect(
        DashboardStatsStore.instance.stats,
        isNull,
        reason: 'JSON incompleto no debe convertirse en un snapshot a medias',
      );
    });

    testWidgets(
      'SQLite/sync lento (repos que NUNCA responden) => el Resumen pinta el '
      'snapshot persistido y NO muestra spinner de pantalla completa',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          statsKey: jsonEncode(persisted.toJson()),
          savedAtKey: DateTime.now().toIso8601String(),
        });

        final gate = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardPage(
                clientRepository: _GatedClientRepository(gate),
                lotRepository: _GatedLotRepository(gate),
                salesRepository: _GatedSalesRepository(gate),
                installmentsRepository: _GatedInstallmentsRepository(gate),
              ),
            ),
          ),
        );
        // Sólo el tiempo necesario para leer SharedPreferences (milisegundos).
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));

        expect(
          find.textContaining('56,131,963.50'),
          findsWidgets,
          reason: 'el saldo pendiente persistido debe estar en pantalla',
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'con snapshot NO puede haber spinner full-screen',
        );
        expect(
          gate.isCompleted,
          isFalse,
          reason: 'la base sigue ocupada y aun así la pantalla ya pintó',
        );
      },
    );

    testWidgets(
      'volver al Resumen (recrear la pantalla) => sigue pintando de inmediato',
      (tester) async {
        DashboardStatsStore.instance.save(persisted);
        final gate = Completer<void>();

        Widget build() => MaterialApp(
          home: Scaffold(
            body: DashboardPage(
              clientRepository: _GatedClientRepository(gate),
              lotRepository: _GatedLotRepository(gate),
              salesRepository: _GatedSalesRepository(gate),
              installmentsRepository: _GatedInstallmentsRepository(gate),
            ),
          ),
        );

        await tester.pumpWidget(build());
        await tester.pump();
        expect(find.textContaining('56,131,963.50'), findsWidgets);

        // Simula Resumen -> Clientes -> Resumen: el shell destruye y recrea.
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
        await tester.pump();
        await tester.pumpWidget(build());
        await tester.pump();

        expect(
          find.textContaining('56,131,963.50'),
          findsWidgets,
          reason: 'el snapshot sobrevive a la navegación',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}

/// Gates sin completar: representan SQLite tomado por el writer del sync.
class _GatedClientRepository extends ClientRepository {
  _GatedClientRepository(this._gate);

  final Completer<void> _gate;

  @override
  Future<int> countAll() async {
    await _gate.future;
    return 98;
  }
}

class _GatedLotRepository extends LotRepository {
  _GatedLotRepository(this._gate);

  final Completer<void> _gate;

  @override
  Future<int> countAll() async {
    await _gate.future;
    return 143;
  }

  @override
  Future<int> countByStatus(String status) async {
    await _gate.future;
    return status == 'disponible' ? 40 : 103;
  }
}

class _GatedSalesRepository extends SalesRepository {
  _GatedSalesRepository(this._gate);

  final Completer<void> _gate;

  @override
  Future<List<SaleSummary>> fetchAll({
    String query = '',
    String? settlementFilter,
  }) async {
    await _gate.future;
    return const [];
  }
}

class _GatedInstallmentsRepository extends InstallmentsRepository {
  _GatedInstallmentsRepository(this._gate);

  final Completer<void> _gate;

  @override
  Future<List<InstallmentDetail>> getAll() async {
    await _gate.future;
    return const [];
  }
}
