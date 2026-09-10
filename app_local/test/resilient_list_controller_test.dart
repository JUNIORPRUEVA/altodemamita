import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/shared/controllers/resilient_list_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ResilientListController<String> build({
    required Future<List<String>> Function(String query) fetch,
    Future<List<String>> Function()? cache,
  }) {
    return ResilientListController<String>(
      moduleLabel: 'Prueba',
      fetch: fetch,
      fetchCache: cache,
    );
  }

  test('cache-first: muestra cache y refresca en segundo plano sin vaciar', () async {
    final gate = Completer<void>();
    final controller = build(
      fetch: (_) async {
        await gate.future;
        return ['cloud1', 'cloud2'];
      },
      cache: () async => ['cache1'],
    );

    final loadFuture = controller.load();
    await pumpEventQueue();
    expect(controller.hasVisibleData, isTrue);
    expect(controller.items, ['cache1']);
    expect(controller.isLoading, isFalse);
    expect(controller.isRefreshing, isTrue);
    expect(controller.loadError, isNull);

    gate.complete();
    await loadFuture;
    expect(controller.items, ['cloud1', 'cloud2']);
    expect(controller.isRefreshing, isFalse);
    controller.dispose();
  });

  test('refresh fallido conserva datos y no es fatal', () async {
    var fail = false;
    final controller = build(
      fetch: (_) async {
        if (fail) {
          throw Exception('down');
        }
        return ['a'];
      },
    );
    await controller.load();
    expect(controller.items, ['a']);

    fail = true;
    await controller.load();
    expect(controller.items, ['a']);
    expect(controller.refreshFailed, isTrue);
    expect(controller.loadError, isNull);
    controller.dispose();
  });

  test('sin datos + caida de red: fatal acotado, sin implicar corrupcion', () async {
    final controller = build(
      fetch: (_) async => throw SocketException('network unreachable'),
      cache: () async => const [],
    );
    await controller.load();
    expect(controller.loadError, isNotNull);
    expect(controller.loadError!.message, contains('no hay conexión'));
    controller.dispose();
  });

  test('cargar NO es vacio; vacio solo tras exito confirmado', () async {
    final gate = Completer<void>();
    final controller = build(
      fetch: (_) async {
        await gate.future;
        return const [];
      },
      cache: () async => const [],
    );
    final loadFuture = controller.load();
    await pumpEventQueue();
    expect(controller.isLoading, isTrue);
    expect(controller.items, isEmpty);
    expect(controller.loadError, isNull);

    gate.complete();
    await loadFuture;
    expect(controller.isLoading, isFalse);
    expect(controller.hasVisibleData, isFalse);
    expect(controller.loadError, isNull);
    controller.dispose();
  });

  test('respuesta tardia no pisa una carga mas nueva', () async {
    final firstGate = Completer<void>();
    var call = 0;
    final controller = build(
      fetch: (_) async {
        call++;
        if (call == 1) {
          await firstGate.future;
          return ['viejo'];
        }
        return ['nuevo'];
      },
      cache: () async => const [],
    );
    final first = controller.load();
    await pumpEventQueue();

    final second = controller.load();
    await second;
    expect(controller.items, ['nuevo']);

    firstGate.complete();
    await first;
    expect(controller.items, ['nuevo']);
    controller.dispose();
  });

  test('busqueda fallida es recuperable (searchFailed), no fatal', () async {
    var fail = false;
    final controller = build(
      fetch: (query) async {
        if (fail) {
          throw Exception('down');
        }
        return ['a'];
      },
    );
    await controller.load();
    fail = true;
    await controller.load(query: 'maria');
    expect(controller.searchFailed, isTrue);
    expect(controller.loadError, isNull);
    controller.dispose();
  });

  test('eliminar quita el item de la lista visible', () async {
    final controller = build(fetch: (_) async => ['a', 'b']);
    await controller.load();
    expect(controller.items, ['a', 'b']);
    controller.removeItemById((value) => value == 'a' ? 1 : 2, 1);
    expect(controller.items, ['b']);
    controller.dispose();
  });
}
