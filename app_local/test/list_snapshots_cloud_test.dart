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
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('list_snapshots_');
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
    'CLOUD_AUTHORITATIVE: clientes escribe snapshot y fetchCachedList la lee',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final apiClient = await _backendClient((request) async {
        if (request.url.path == '/api/business/clients') {
          return _json(200, {
            'data': {
              'items': [
                {
                  'id': 'client-remote-1',
                  'syncId': 'client-sync-1',
                  'name': 'Cliente Cache',
                  'document': '00112345678',
                  'createdAt': '2026-09-09T10:00:00.000Z',
                  'updatedAt': '2026-09-09T10:00:00.000Z',
                },
              ],
            },
          });
        }
        return _json(404, {'message': 'unexpected'});
      });

      final repo = ClientRepository(appDatabase: appDatabase, apiClient: apiClient);
      final fetched = await repo.fetchAll();
      expect(fetched, hasLength(1));

      final fresh = ClientRepository(
        appDatabase: appDatabase,
        apiClient: apiClient,
      );
      final cached = await fresh.fetchCachedList();
      expect(cached, hasLength(1));
      expect(cached.single.fullName, 'Cliente Cache');
    },
  );

  test(
    'CLOUD_AUTHORITATIVE: solares escribe snapshot y fetchCachedList la lee',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final apiClient = await _backendClient((request) async {
        if (request.url.path == '/api/business/lots') {
          return _json(200, {
            'data': {
              'items': [
                {
                  'id': 'lot-remote-1',
                  'syncId': 'product-sync-1',
                  'block': 'A',
                  'number': '1',
                  'area': '100',
                  'price': '10',
                  'status': 'disponible',
                  'createdAt': '2026-09-09T10:00:00.000Z',
                  'updatedAt': '2026-09-09T10:00:00.000Z',
                },
              ],
            },
          });
        }
        return _json(404, {'message': 'unexpected'});
      });

      final repo = LotRepository(appDatabase: appDatabase, apiClient: apiClient);
      final fetched = await repo.fetchAll();
      expect(fetched, hasLength(1));

      final cached = await LotRepository(
        appDatabase: appDatabase,
        apiClient: apiClient,
      ).fetchCachedList();
      expect(cached, hasLength(1));
      expect(cached.single.displayCode, contains('A'));
    },
  );

  test(
    'CLOUD_AUTHORITATIVE: vendedores escribe snapshot y fetchCachedList la lee',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final apiClient = await _backendClient((request) async {
        if (request.url.path == '/api/business/sellers') {
          return _json(200, {
            'data': {
              'items': [
                {
                  'id': 'seller-remote-1',
                  'syncId': 'seller-sync-1',
                  'name': 'Vendedor Cache',
                  'document': '001-0000001',
                  'phone': '8090000000',
                  'createdAt': '2026-09-09T10:00:00.000Z',
                  'updatedAt': '2026-09-09T10:00:00.000Z',
                },
              ],
            },
          });
        }
        return _json(404, {'message': 'unexpected'});
      });

      final repo = SellerRepository(database: appDatabase, apiClient: apiClient);
      final fetched = await repo.getAll();
      expect(fetched, hasLength(1));

      final cached = await SellerRepository(
        database: appDatabase,
        apiClient: apiClient,
      ).fetchCachedList();
      expect(cached, hasLength(1));
      expect(cached.single.name, 'Vendedor Cache');
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
      expect(request.headers['authorization'], 'Bearer jwt-test-token');
      return handler(request);
    }),
  );
}

http.Response _json(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
