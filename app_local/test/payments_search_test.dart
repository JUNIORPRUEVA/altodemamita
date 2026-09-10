import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payments_controller.dart';

/// Reproduce el reporte real: la venta existe en Ventas y en PostgreSQL, pero
/// NO esta dentro de la primera pagina de la cola de trabajo de Pagos.
const PaymentSaleOption _saleOutsideWorkQueue = PaymentSaleOption(
  saleId: 9001,
  clientId: 7001,
  clientName: 'prueva tres',
  clientDocumentId: '001-0000000-9',
  clientPhone: '7568577557',
  lotDisplayCode: 'Mgf-S1212',
  pendingBalance: 225000,
  requiredInitialPayment: 25000,
  paidInitialPayment: 25000,
  pendingInitialPayment: 0,
  status: 'activa',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la busqueda de Pagos trae ventas que no estan en la cola de trabajo',
      () async {
    final repository = FakeSearchPaymentsRepository(
      resultsByQuery: const {
        '1212': [_saleOutsideWorkQueue],
      },
    );
    final controller = PaymentsController(paymentsRepository: repository);

    await controller.searchSales('1212');

    expect(controller.searchResults, hasLength(1));
    expect(controller.searchResults.single.saleId, 9001);
    expect(controller.searchResults.single.lotDisplayCode, 'Mgf-S1212');
    expect(controller.isSearching, isFalse);
    expect(controller.searchError, isNull);
    expect(repository.queries, ['1212']);

    controller.dispose();
  });

  test('la busqueda consulta el backend por cedula y telefono, no solo por la lista local',
      () async {
    final repository = FakeSearchPaymentsRepository(
      resultsByQuery: const {
        '7568577557': [_saleOutsideWorkQueue],
        '001-0000000-9': [_saleOutsideWorkQueue],
      },
    );
    final controller = PaymentsController(paymentsRepository: repository);

    await controller.searchSales('7568577557');
    expect(controller.searchResults, hasLength(1));

    await controller.searchSales('001-0000000-9');
    expect(controller.searchResults, hasLength(1));
    expect(repository.queries, ['7568577557', '001-0000000-9']);

    controller.dispose();
  });

  test('una respuesta fuera de orden no sobreescribe la busqueda mas reciente',
      () async {
    final slow = Completer<void>();
    final fast = Completer<void>();
    final repository = FakeSearchPaymentsRepository(
      resultsByQuery: const {
        'aaa': [_saleOutsideWorkQueue],
        'bbb': [],
      },
      gateByQuery: {'aaa': slow, 'bbb': fast},
    );
    final controller = PaymentsController(paymentsRepository: repository);

    final firstRun = controller.searchSales('aaa');
    final secondRun = controller.searchSales('bbb');

    fast.complete();
    await secondRun;
    slow.complete();
    await firstRun;

    // La consulta vieja ('aaa') llega tarde y NO debe imponerse.
    expect(controller.searchResults, isEmpty);

    controller.dispose();
  });

  test('al cambiar la consulta no se heredan resultados del cliente anterior',
      () async {
    final gate = Completer<void>();
    final repository = FakeSearchPaymentsRepository(
      resultsByQuery: const {
        'todoterreno': [_saleOutsideWorkQueue],
        'x': [],
      },
      gateByQuery: {'x': gate},
    );
    final controller = PaymentsController(paymentsRepository: repository);

    await controller.searchSales('todoterreno');
    expect(controller.searchResults, hasLength(1));

    final pending = controller.searchSales('xyz');
    // Mientras la nueva consulta esta en vuelo, ya no debe mostrarse el
    // resultado anterior como si fuera coincidencia.
    expect(controller.searchResults, isEmpty);
    expect(controller.isSearching, isTrue);

    gate.complete();
    await pending;
    expect(controller.isSearching, isFalse);

    controller.dispose();
  });

  test('las consultas muy cortas no llegan al backend', () async {
    final repository = FakeSearchPaymentsRepository();
    final controller = PaymentsController(paymentsRepository: repository);

    await controller.searchSales('1');
    expect(repository.queries, isEmpty);
    expect(controller.searchResults, isEmpty);

    await controller.searchSales('   ');
    expect(repository.queries, isEmpty);

    controller.dispose();
  });

  test('clearSearch limpia resultados y estado de busqueda', () async {
    final repository = FakeSearchPaymentsRepository(
      resultsByQuery: const {
        '1212': [_saleOutsideWorkQueue],
      },
    );
    final controller = PaymentsController(paymentsRepository: repository);

    await controller.searchSales('1212');
    expect(controller.searchResults, isNotEmpty);

    controller.clearSearch();
    expect(controller.searchResults, isEmpty);
    expect(controller.isSearching, isFalse);
    expect(controller.searchError, isNull);

    controller.dispose();
  });

  test('un fallo de red en la busqueda no rompe el modulo', () async {
    final repository = FakeSearchPaymentsRepository(failQueries: {'1212'});
    final controller = PaymentsController(paymentsRepository: repository);

    await controller.searchSales('1212');

    expect(controller.searchResults, isEmpty);
    expect(controller.searchError, isNotNull);
    expect(controller.isSearching, isFalse);

    controller.dispose();
  });
}

class FakeSearchPaymentsRepository extends PaymentsRepository {
  FakeSearchPaymentsRepository({
    this.resultsByQuery = const {},
    this.gateByQuery = const {},
    this.failQueries = const {},
  });

  final Map<String, List<PaymentSaleOption>> resultsByQuery;
  final Map<String, Completer<void>> gateByQuery;
  final Set<String> failQueries;
  final List<String> queries = [];

  @override
  Future<List<PaymentSaleOption>> searchSales(
    String query, {
    int limit = 25,
  }) async {
    queries.add(query);
    final gate = gateByQuery[query];
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    if (failQueries.contains(query)) {
      throw Exception('network down');
    }
    return resultsByQuery[query] ?? const [];
  }
}
