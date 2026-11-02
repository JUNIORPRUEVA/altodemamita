import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';

/// API simulada que pagina igual que el backend real
/// (`GET /business/clients?page=&limit=` + `data.total`).
class _PagedApiClient extends BackendApiClient {
  _PagedApiClient({required this.total});

  final int total;
  final List<Map<String, String>> requests = [];

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
  }) async {
    requests.add(Map<String, String>.from(queryParameters ?? const {}));
    final page = int.tryParse(queryParameters?['page'] ?? '1') ?? 1;
    final limit = int.tryParse(queryParameters?['limit'] ?? '100') ?? 100;
    final start = (page - 1) * limit;
    final end = (start + limit) > total ? total : start + limit;
    final items = <Map<String, dynamic>>[
      for (var index = start; index < end; index++)
        {
          'id': 'remote-client-$index',
          'syncId': 'remote-sync-$index',
          'name': 'CLIENTE ${index.toString().padLeft(4, '0')}',
          'document': '001-0000000-$index',
          'phone': '8090000000',
          'version': 1,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
    ];
    return {
      'data': {
        'items': items,
        'total': total,
        'page': page,
        'pageSize': limit,
      },
    };
  }
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('clients_paging_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('lee mas de 100 clientes recorriendo todas las paginas', () async {
    // Esta prueba solo tiene sentido con el modo nube autoritativo, que se
    // activa por compilacion:
    //   flutter test --dart-define=CLOUD_CUTOVER_MODE=CLOUD_AUTHORITATIVE
    // Se omite (no se relaja ninguna asercion) cuando la compilacion usa el
    // modo local heredado, igual que `read_only_configuration_hardening_test`.
    if (!cloudCutoverMode.usesAuthoritativeBusinessWrites) {
      return;
    }

    final api = _PagedApiClient(total: 250);
    final repository = ClientRepository(
      appDatabase: appDatabase,
      apiClient: api,
    );

    final clients = await repository.fetchAll();

    expect(clients, hasLength(250));
    expect(clients.first.fullName, 'CLIENTE 0000');
    expect(clients.last.fullName, 'CLIENTE 0249');
    expect(api.requests.map((request) => request['page']), [
      '1',
      '2',
      '3',
    ]);
    // No se repiten clientes entre paginas.
    expect(clients.map((client) => client.fullName).toSet(), hasLength(250));
  });

  test('se detiene en una sola pagina cuando el total cabe en 100', () async {
    if (!cloudCutoverMode.usesAuthoritativeBusinessWrites) {
      return;
    }

    final api = _PagedApiClient(total: 97);
    final repository = ClientRepository(
      appDatabase: appDatabase,
      apiClient: api,
    );

    final clients = await repository.fetchAll();

    expect(clients, hasLength(97));
    expect(api.requests, hasLength(1));
  });
}
