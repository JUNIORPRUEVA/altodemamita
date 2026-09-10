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

  test(
    'cache-first: muestra la ultima lista guardada de inmediato y refresca en segundo plano sin vaciar',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..cached = [_summary(1, 'Cliente A')]
        ..onFetchAll = (_) => [_summary(1, 'Cliente A'), _summary(2, 'Cliente B')];
      final gate = Completer<void>();
      fakeSales.fetchGate = gate;

      final controller = _buildController(sales: fakeSales);
      final loadFuture = controller.load();
      await pumpEventQueue();

      // Cache visible de inmediato mientras cloud aun no responde.
      expect(controller.hasVisibleData, isTrue);
      expect(controller.sales.map((s) => s.id), [1]);
      expect(controller.isLoading, isFalse);
      expect(controller.isRefreshing, isTrue);
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

  test(
    'una respuesta tardia (carrera) no pisa una carga mas nueva',
    () async {
      final fakeSales = _FakeSalesRepository()
        ..cached = const []
        ..onFetchAll = (_) => [_summary(99, 'Respuesta vieja')];
      final gate = Completer<void>();
      fakeSales.fetchGate = gate;

      final controller = _buildController(sales: fakeSales);
      final firstLoad = controller.load();
      await pumpEventQueue();

      fakeSales.fetchGate = null;
      fakeSales.onFetchAll = (_) => [_summary(1, 'Nuevo'), _summary(2, 'Nuevo 2')];
      final secondLoad = controller.load();
      await secondLoad;
      expect(controller.sales.map((s) => s.id), [1, 2]);

      gate.complete();
      await firstLoad;
      // La respuesta vieja NO debe sobrescribir la nueva.
      expect(controller.sales.map((s) => s.id), [1, 2]);
      controller.dispose();
    },
  );

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

SaleSummary _summary(int id, String clientName) {
  return SaleSummary(
    id: id,
    syncStatus: 'synced',
    clientName: clientName,
    clientDocumentId: '001-0000000-$id',
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
  List<SaleSummary> cached = const [];

  @override
  Future<List<SaleSummary>> fetchAll({
    String query = '',
    String? settlementFilter,
  }) async {
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
  Future<List<SaleSummary>> fetchCachedList() async => cached;

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
