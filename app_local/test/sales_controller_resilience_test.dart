import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_detail.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/features/sales/domain/sale_summary.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/features/sales/presentation/sales_controller.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/features/settings/domain/app_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // El cache en memoria vive FUERA de la pantalla (sobrevive a que el shell
  // destruya y recree la pagina). Se aisla entre tests.
  setUp(SalesListMemoryCache.debugReset);
  tearDown(SalesListMemoryCache.debugReset);

  test(
    'cache-first: muestra la ultima lista guardada de inmediato y refresca en segundo plano sin vaciar',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..cached = [_summary(1, 'Cliente A')]
        ..onFetchAll = (_) => [
          _summary(1, 'Cliente A'),
          _summary(2, 'Cliente B'),
        ];
      final gate = Completer<void>();
      fakeSales.fetchGate = gate;

      final controller = _buildController(sales: fakeSales);
      final loadFuture = controller.load();
      await pumpEventQueue();

      // Cache visible de inmediato mientras cloud aun no responde.
      expect(controller.hasVisibleData, isTrue);
      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.isLoading, isFalse);
      expect(controller.isRefreshing, isFalse);
      expect(controller.loadError, isNull);

      gate.complete();
      await loadFuture;
      expect(controller.sales.map((s) => s.id), [1, 2]);
      expect(controller.isRefreshing, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.loadError, isNull);
      controller.dispose();
    },
  );

  test(
    'refresh fallido conserva los datos visibles y NO muestra pantalla fatal',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..onFetchAll = (_) => [_summary(1, 'Cliente A')];
      final controller = _buildController(sales: fakeSales);
      await controller.load();
      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.loadError, isNull);

      fakeSales.failFetch = true;
      await controller.load();
      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.hasVisibleData, isTrue);
      expect(controller.refreshFailed, isTrue);
      expect(controller.loadError, isNull);
      expect(controller.isRefreshing, isFalse);
      controller.dispose();
    },
  );

  test(
    'sin cache + backend caido: unico caso con estado bloqueante, sin implicar corrupcion',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..cached = const []
        ..failFetch = true
        ..fetchError = SocketException('network unreachable');
      final controller = _buildController(sales: fakeSales);
      await controller.load();
      expect(controller.sales, isEmpty);
      expect(controller.loadError, isNotNull);
      expect(controller.loadError!.message, contains('no hay conexión'));
      expect(controller.refreshFailed, isFalse);
      controller.dispose();
    },
  );

  test(
    '"No hay ventas" (vacio) solo se muestra tras exito autoritativo; cargar NO es vacio',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..cached = const []
        ..onFetchAll = (_) => const [];
      final gate = Completer<void>();
      fakeSales.fetchGate = gate;

      final controller = _buildController(sales: fakeSales);
      final loadFuture = controller.load();
      await pumpEventQueue();

      // Durante la carga: loading con lista vacia, JAMAS vacio confirmado.
      expect(controller.isLoading, isTrue);
      expect(controller.sales, isEmpty);
      expect(controller.loadError, isNull);

      gate.complete();
      await loadFuture;
      expect(controller.isLoading, isFalse);
      expect(controller.hasVisibleData, isFalse);
      expect(controller.loadError, isNull);
      expect(controller.searchFailed, isFalse);
      controller.dispose();
    },
  );

  test('una respuesta tardia (carrera) no pisa una carga mas nueva', () async {
    final fakeSales = _FakeSalesRepository()
      ..cached = const []
      ..onFetchAll = (_) => [_summary(99, 'Respuesta vieja')];
    final gate = Completer<void>();
    fakeSales.fetchGate = gate;

    final controller = _buildController(sales: fakeSales);
    final firstLoad = controller.load();
    await pumpEventQueue();

    fakeSales.fetchGate = null;
    fakeSales.onFetchAll = (_) => [
      _summary(1, 'Nuevo'),
      _summary(2, 'Nuevo 2'),
    ];
    final secondLoad = controller.load();
    await secondLoad;
    expect(controller.sales.map((s) => s.id), [1, 2]);

    gate.complete();
    await firstLoad;
    // La respuesta vieja NO debe sobrescribir la nueva.
    expect(controller.sales.map((s) => s.id), [1, 2]);
    controller.dispose();
  });

  test(
    'busqueda fallida: error recuperable (searchFailed), nunca fatal de modulo',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..onFetchAll = (_) => [_summary(1, 'Cliente A')];
      final controller = _buildController(sales: fakeSales);
      await controller.load();

      fakeSales.failFetch = true;
      await controller.load(query: 'maria');
      expect(controller.searchFailed, isTrue);
      expect(controller.loadError, isNull);
      controller.dispose();
    },
  );

  test(
    'busqueda cache-first: filtra cache inmediatamente y refresca backend sin pantalla completa',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..onFetchAll = (query) => query.isEmpty
            ? [
                _summary(1, 'Lucas Gomez', phone: '8095551000'),
                _summary(2, 'Maria Perez'),
              ]
            : [_summary(1, 'Lucas Gomez', phone: '8095551000')];
      final controller = _buildController(sales: fakeSales);
      await controller.load();

      final gate = Completer<void>();
      fakeSales.fetchGate = gate;
      final searchFuture = controller.load(query: '809555');
      await pumpEventQueue();

      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.isLoading, isFalse);
      expect(controller.isRefreshing, isFalse);
      expect(controller.searchFailed, isFalse);

      gate.complete();
      await searchFuture;
      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.isRefreshing, isFalse);
      controller.dispose();
    },
  );

  test(
    'busqueda rapida: respuesta vieja luc no pisa resultado nuevo lucas',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..onFetchAll = (query) => query == 'luc'
            ? [_summary(1, 'Luc Viejo')]
            : [_summary(2, 'Lucas Nuevo')];
      final controller = _buildController(sales: fakeSales);
      await controller.load();

      final lucGate = Completer<void>();
      fakeSales.fetchGatesByQuery['luc'] = lucGate;
      final oldSearch = controller.load(query: 'luc');
      await pumpEventQueue();

      final newSearch = controller.load(query: 'lucas');
      await newSearch;
      expect(controller.sales.map((s) => s.id), [2]);

      lucGate.complete();
      await oldSearch;
      expect(controller.sales.map((s) => s.id), [2]);
      controller.dispose();
    },
  );

  test(
    'crear venta exitosa actualiza la lista de inmediato (PostgreSQL -> cache/lista)',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..onFetchAll = (_) => [_summary(1, 'Cliente A')];
      final controller = _buildController(sales: fakeSales);
      await controller.load();

      fakeSales.onFetchAll = (_) => [
        _summary(1, 'Cliente A'),
        _summary(2, 'Cliente B'),
      ];
      final id = await controller.createSale(
        SaleDraft(
          clientId: 10,
          lotId: 20,
          userId: 1,
          saleDate: DateTime(2026, 9, 9),
          salePrice: 1000,
          downPaymentPercentage: 20,
          requiredInitialPayment: 200,
          initialPaymentPaid: 200,
          monthlyInterest: 1,
          installmentCount: 12,
          status: 'activa',
        ),
      );
      expect(id, 501);
      expect(controller.sales.map((s) => s.id), [1, 2]);
      controller.dispose();
    },
  );

  test(
    'eliminar venta quita el item y reconcilia la lista sin recargar todo',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..onFetchAll = (_) => [
          _summary(1, 'Cliente A'),
          _summary(2, 'Cliente B'),
        ];
      final controller = _buildController(sales: fakeSales);
      await controller.load();

      fakeSales.onFetchAll = (_) => [_summary(2, 'Cliente B')];
      final error = await controller.deleteSale(1);
      expect(error, isNull);
      await pumpEventQueue();
      expect(controller.sales.map((s) => s.id), [2]);
      expect(controller.loadError, isNull);
      controller.dispose();
    },
  );

  group('Ventas abre de inmediato (lista visible, sin "Actualizando" eterno)', () {
    test('lista existente => visible inmediatamente, sin isLoading', () async {
      // Primera entrada: se carga y queda memorizado.
      final first = _FakeSalesRepository()
        ..onFetchAll = (_) => [_summary(1, 'Cliente A')];
      final firstController = _buildController(sales: first);
      await firstController.load();
      expect(firstController.sales.map((s) => s.id), [1]);
      firstController.dispose();

      // Segunda entrada con SQLite tomado: cache y fetch bloqueados.
      final blocked = _FakeSalesRepository();
      final cacheGate = Completer<void>();
      final fetchGate = Completer<void>();
      blocked.cacheGate = cacheGate;
      blocked.fetchGate = fetchGate;

      final controller = _buildController(sales: blocked);
      controller.load();
      await pumpEventQueue();

      expect(
        controller.sales.map((s) => s.id),
        [1],
        reason: 'la lista anterior debe estar ANTES de que responda SQLite',
      );
      expect(
        controller.isLoading,
        isFalse,
        reason: 'NO puede quedar en skeleton si hay lista previa',
      );
      expect(controller.loadError, isNull);

      cacheGate.complete();
      fetchGate.complete();
      await pumpEventQueue();
      controller.dispose();
    });

    test('Ventas -> Dashboard -> Ventas => lista inmediata', () async {
      final first = _FakeSalesRepository()
        ..onFetchAll = (_) => [_summary(1, 'Cliente A'), _summary(2, 'B')];
      final firstController = _buildController(sales: first);
      await firstController.load();
      firstController.dispose(); // el shell destruye la página al navegar

      // Segundo controlador (pantalla recreada) con SQLite TOMADO: ni la cache
      // ni el fetch autoritativo responden todavía.
      final blocked = _FakeSalesRepository();
      final cacheGate = Completer<void>();
      final fetchGate = Completer<void>();
      blocked.cacheGate = cacheGate;
      blocked.fetchGate = fetchGate;
      final controller = _buildController(sales: blocked);
      controller.load();
      await pumpEventQueue();

      expect(controller.sales.map((s) => s.id), [1, 2]);
      expect(controller.isLoading, isFalse);

      cacheGate.complete();
      fetchGate.complete();
      await pumpEventQueue();
      controller.dispose();
    });

    test(
      'sync lento (fetch que nunca responde) => la lista permanece visible',
      () async {
        final sales = _FakeSalesRepository()
          ..onFetchAll = (_) => [_summary(1, 'Cliente A')];
        final controller = _buildController(sales: sales);
        await controller.load();
        expect(controller.sales.map((s) => s.id), [1]);

        // El sync general deja el fetch colgado: la lista NO se puede vaciar.
        final gate = Completer<void>();
        sales.fetchGate = gate;
        controller.load();
        await pumpEventQueue();

        expect(controller.sales.map((s) => s.id), [1]);
        expect(controller.isLoading, isFalse);
        expect(controller.isRefreshing, isFalse);

        gate.complete();
        await pumpEventQueue();
        controller.dispose();
      },
    );

    test('error de refresh => conserva la última lista (no la borra)', () async {
      final sales = _FakeSalesRepository()
        ..onFetchAll = (_) => [_summary(1, 'Cliente A')];
      final controller = _buildController(sales: sales);
      await controller.load();

      sales.failFetch = true;
      await controller.load();

      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.refreshFailed, isTrue);
      expect(controller.loadError, isNull);

      // Y al reentrar sigue habiendo lista válida (aunque la base esté tomada).
      final blocked = _FakeSalesRepository();
      final cacheGate = Completer<void>();
      final fetchGate = Completer<void>();
      blocked.cacheGate = cacheGate;
      blocked.fetchGate = fetchGate;
      final again = _buildController(sales: blocked);
      again.load();
      await pumpEventQueue();
      expect(again.sales.map((s) => s.id), [1]);

      cacheGate.complete();
      fetchGate.complete();
      await pumpEventQueue();
      controller.dispose();
      again.dispose();
    });
  });
}

SalesController _buildController({required _FakeSalesRepository sales}) {
  return SalesController(
    salesRepository: sales,
    clientRepository: _FakeClientRepository(),
    lotRepository: _FakeLotRepository(),
    sellerRepository: _FakeSellerRepository(),
    settingsRepository: _FakeSettingsRepository(),
  );
}

SaleSummary _summary(int id, String clientName, {String phone = ''}) {
  return SaleSummary(
    id: id,
    syncStatus: 'synced',
    clientName: clientName,
    clientDocumentId: '001-0000000-$id',
    clientPhone: phone,
    lotDisplayCode: 'M1-S$id',
    saleDate: DateTime(2026, 9, 9),
    salePrice: 1000,
    downPaymentAmount: 100,
    requiredInitialPayment: 200,
    paidInitialPayment: 200,
    pendingInitialPayment: 0,
    financedBalance: 800,
    pendingBalance: 800,
    monthlyInterest: 1,
    installmentCount: 12,
    status: 'activa',
    generatedInstallments: 12,
  );
}

class _FakeSalesRepository extends SalesRepository {
  _FakeSalesRepository();

  List<SaleSummary> Function(String query) onFetchAll = (_) => const [];
  bool failFetch = false;
  Object? fetchError;
  Completer<void>? fetchGate;
  final Map<String, Completer<void>> fetchGatesByQuery = {};

  /// Simula la lectura de cache/lista local con SQLite tomado por el writer.
  Completer<void>? cacheGate;
  List<SaleSummary> cached = const [];

  @override
  Future<List<SaleSummary>> fetchAll({
    String query = '',
    String? settlementFilter,
  }) async {
    final queryGate = fetchGatesByQuery[query];
    if (queryGate != null) {
      await queryGate.future;
    }
    final gate = fetchGate;
    if (gate != null) {
      await gate.future;
    }
    if (failFetch) {
      throw fetchError ?? Exception('backend no disponible');
    }
    return onFetchAll(query);
  }

  @override
  Future<List<SaleSummary>> fetchCachedList() async {
    final gate = cacheGate;
    if (gate != null) {
      await gate.future;
    }
    return cached;
  }

  @override
  Future<int> createSale(SaleDraft draft, {String? operationId}) async => 501;

  @override
  Future<void> updateSale(
    int saleId,
    SaleDraft draft, {
    String? operationId,
  }) async {}

  @override
  Future<void> deleteSale(int saleId) async {}

  @override
  Future<SaleDetail?> fetchDetail(int saleId) async => null;
}

class _FakeClientRepository extends ClientRepository {
  _FakeClientRepository();

  @override
  Future<List<Client>> fetchAll({String query = ''}) async => const [];
}

class _FakeLotRepository extends LotRepository {
  _FakeLotRepository();

  @override
  Future<List<Lot>> fetchAvailable({String query = ''}) async => const [];
}

class _FakeSellerRepository extends SellerRepository {
  _FakeSellerRepository();

  @override
  Future<List<Seller>> getAll() async => const [];
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository();

  @override
  Future<Map<String, AppSetting>> fetchByKeysWithDefaults(
    Map<String, String> defaults,
  ) async {
    return {
      for (final entry in defaults.entries)
        entry.key: AppSetting(
          key: entry.key,
          value: entry.value,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
    };
  }
}
