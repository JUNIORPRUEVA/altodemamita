import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sales_list_cache_cloud_',
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

  test(
    'CLOUD_AUTHORITATIVE: fetchAll escribe cache y fetchCachedList la lee en otra instancia',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient(
        (_) async => _json(200, _saleItemsJson(_saleJson('sale-remote-1'))),
      );
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      final first = await sales.fetchAll();
      expect(first, hasLength(1));
      final localId = first.single.id;

      // Nueva instancia sobre la misma DB (simula reapertura / restart).
      final sales2 = SalesRepository(
        appDatabase: appDatabase,
        apiClient: await _backendClient(
          (_) async => _json(
            200,
            _saleItemsJson(_saleJson('sale-remote-1')),
          ),
        ),
      );
      final cached = await sales2.fetchCachedList();
      expect(cached, hasLength(1));
      expect(cached.single.id, localId);
      expect(cached.single.clientName, 'Cliente Cache');
    },
  );

  test(
    'CLOUD_AUTHORITATIVE: fetchAll con query (busqueda) NO pisa el cache default',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final requestedSearches = <String>[];
      final client = await _backendClient((request) async {
        final hasSearch = request.url.queryParameters.containsKey('search');
        if (hasSearch) {
          requestedSearches.add(request.url.queryParameters['search']!);
          return _json(200, {
            'data': {
              'items': [
                _saleJson('sale-search-1', client: 'Resultado Busqueda'),
              ],
            },
          });
        }
        return _json(200, {
          'data': {
            'items': [_saleJson('sale-remote-1')],
          },
        });
      });
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      await sales.fetchAll();
      final searchResults = await sales.fetchAll(query: 'maria');
      expect(searchResults.single.clientName, 'Resultado Busqueda');
      expect(requestedSearches, ['maria']);

      // El cache default conserva la lista completa original.
      final cached = await SalesRepository(
        appDatabase: appDatabase,
        apiClient: client,
      ).fetchCachedList();
      expect(cached, hasLength(1));
      expect(cached.single.clientName, 'Cliente Cache');
    },
  );

  test(
    'CLOUD_AUTHORITATIVE: deleteSale invalida el cache para no mostrar datos stale',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.startsWith('/api/authoritative/sales/') &&
            request.url.path.endsWith('/cancel')) {
          return _json(200, {'data': {'ok': true}});
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/owner/sales') {
          return _json(200, {
            'data': {
              'items': [_saleJson('sale-remote-1')],
            },
          });
        }
        return _json(404, {'message': 'unexpected ${request.url.path}'});
      });
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      final summaries = await sales.fetchAll();
      expect(summaries, hasLength(1));
      expect(await sales.fetchCachedList(), hasLength(1));

      await sales.deleteSale(summaries.single.id);

      // Cache invalidado: no debe quedar un snapshot con la venta eliminada.
      expect(await sales.fetchCachedList(), isEmpty);
    },
  );
}

Future<BackendApiClient> _backendClient(
  Future<http.Response> Function(http.Request) handler,
) async {
  final configRepository = FakeSyncConfigRepository(
    settings: buildFakeSettings(),
  );
  await configRepository.saveJwtToken('jwt-test-token');
  return BackendApiClient(
    syncConfigRepository: configRepository,
    client: MockClient((request) async {
      final token = request.headers['authorization'];
      expect(token, 'Bearer jwt-test-token');
      return handler(request);
    }),
  );
}

Map<String, Object?> _saleJson(
  String remoteId, {
  String client = 'Cliente Cache',
}) {
  return {
    'id': remoteId,
    'syncId': 'sale-sync-$remoteId',
    'client': client,
    'cedula': '00112345678',
    'clientEntity': {
      'id': 'client-remote-1',
      'syncId': 'client-sync-1',
      'name': client,
      'document': '00112345678',
    },
    'lot': 'MA-S1',
    'lotEntity': {
      'id': 'lot-remote-1',
      'syncId': 'product-sync-1',
      'block': 'A',
      'number': '1',
      'code': 'MA-S1',
    },
    'status': 'activa',
    'saleDate': '2026-09-09T10:00:00.000Z',
    'total': '1000',
    'initialRequiredAmount': '200',
    'initialPaid': '200',
    'initialPendingAmount': '0',
    'reservationPaidAmount': '0',
    'financedBalance': '800',
    'balance': '800',
    'monthlyInterestRate': '1',
    'installmentCount': 12,
    'updatedAt': '2026-09-09T10:00:00.000Z',
    'createdAt': '2026-09-09T10:00:00.000Z',
  };
}

Map<String, Object?> _saleItemsJson(Map<String, Object?> sale) {
  return {
    'data': {
      'items': [sale],
    },
  };
}

http.Response _json(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
