import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/core/network/backend_entity_id_registry.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

import 'helpers/fake_backend.dart';
import 'helpers/fake_sync_download_api_client.dart';

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
      // CONTRATO REAL (evidencia): backend/src/routes/owner.routes.ts
      //   ownerRouter.get('/sales', listSales)
      // y `listSales` solo lee page, pageSize, includeDeleted, settlement y lotId.
      // `GET /owner/sales` NO implementa `search` (ese parametro existe solo en
      // /payments/work-queue; la busqueda de pagos usa `q`). Por eso el filtrado
      // por texto lo hace el CLIENTE (_filterSummariesByQuery) y el fake debe
      // devolver SIEMPRE la lista completa, como hace PostgreSQL.
      final client = await _backendClient((request) async {
        if (request.url.queryParameters.containsKey('search')) {
          requestedSearches.add(request.url.queryParameters['search']!);
        }
        return _json(200, {
          'data': {
            'items': [
              _saleJson('sale-remote-1', client: 'Cliente Cache'),
              _saleJson('sale-remote-2', client: 'Maria Resultado Busqueda'),
            ],
          },
        });
      });
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      // Default: lista completa y cacheada.
      final all = await sales.fetchAll();
      expect(all, hasLength(2));
      expect(await sales.fetchCachedList(), hasLength(2));

      // Busqueda: el cliente filtra la lista real y devuelve SOLO la coincidencia.
      final searchResults = await sales.fetchAll(query: 'maria');
      expect(requestedSearches, ['maria']);
      expect(searchResults, hasLength(1));
      expect(searchResults.first.clientName, 'Maria Resultado Busqueda');

      // La busqueda NO contamina ni reemplaza el cache default.
      final cached = await SalesRepository(
        appDatabase: appDatabase,
        apiClient: client,
      ).fetchCachedList();
      expect(cached, hasLength(2));
      expect(
        cached.map((item) => item.clientName),
        containsAll(<String>['Cliente Cache', 'Maria Resultado Busqueda']),
      );
    },
  );

  test(
    'CLOUD_AUTHORITATIVE: busqueda sin coincidencias devuelve lista vacia (no excepcion) y no pisa el cache',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient(
        (_) async => _json(
          200,
          _saleItemsJson(_saleJson('sale-remote-1', client: 'Cliente Cache')),
        ),
      );
      final sales = SalesRepository(appDatabase: appDatabase, apiClient: client);

      await sales.fetchAll();
      expect(await sales.fetchCachedList(), hasLength(1));

      // Sin coincidencias: lista vacia, sin lanzar, y el cache default intacto.
      final noMatches = await sales.fetchAll(query: 'zzz-sin-coincidencias');
      expect(noMatches, isEmpty);
      expect(await sales.fetchCachedList(), hasLength(1));

      // Query vacia mantiene el comportamiento default.
      final emptyQuery = await sales.fetchAll(query: '   ');
      expect(emptyQuery, hasLength(1));
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

  test(
    'CACHE HARDENING: registrar un pago invalida el snapshot de la lista de ventas',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/owner/sales') {
          return _json(200, _saleItemsJson(_saleJson('sale-remote-1')));
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/authoritative/payments') {
          return _json(200, {
            'data': {'paymentIds': ['payment-remote-1']},
          });
        }
        return _json(404, {'message': 'unexpected ${request.url.path}'});
      });
      final sales = SalesRepository(appDatabase: appDatabase, apiClient: client);
      final payments = PaymentsRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      final summaries = await sales.fetchAll();
      expect(summaries, hasLength(1));
      // PRE: la lista queda cacheada (con su overdueInstallmentCount).
      expect(await sales.fetchCachedList(), hasLength(1));

      await payments.registerPayment(
        PaymentDraft(
          saleId: summaries.single.id,
          amountPaid: 100,
          paymentDate: DateTime.now(),
          paymentMethod: 'efectivo',
        ),
      );

      // POST (inmediato, sin restart ni limpieza manual): el conteo derivado ya no
      // puede servirse del snapshot anterior.
      expect(await sales.fetchCachedList(), isEmpty);
    },
  );

  test(
    'CACHE HARDENING: anular un pago invalida el snapshot de la lista de ventas',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/owner/sales') {
          return _json(200, _saleItemsJson(_saleJson('sale-remote-1')));
        }
        if (request.method == 'POST') {
          return _json(200, {
            'data': {'ok': true},
          });
        }
        return _json(404, {'message': 'unexpected ${request.url.path}'});
      });
      final sales = SalesRepository(appDatabase: appDatabase, apiClient: client);
      final payments = PaymentsRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      await sales.fetchAll();
      expect(await sales.fetchCachedList(), hasLength(1));

      // El id remoto del pago debe existir en el registro para poder anularlo.
      final paymentRemoteId = 'payment-remote-1';
      final localPaymentId = BackendEntityIdRegistry.instance.register(
        'payments',
        paymentRemoteId,
      );
      expect(
        BackendEntityIdRegistry.instance.resolveRemoteId(
          'payments',
          localPaymentId,
        ),
        paymentRemoteId,
      );

      await payments.deletePayment(
        localPaymentId,
        reason: 'Pago registrado por error',
      );

      // Anular un pago puede volver a marcar cuotas como vencidas: el snapshot
      // anterior no puede sobrevivir.
      expect(await sales.fetchCachedList(), isEmpty);
    },
  );

  test(
    'CACHE HARDENING: liquidar (venta definitiva) invalida el snapshot de la lista',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      var settled = false;
      final client = await _backendClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/owner/sales') {
          return _json(200, _saleItemsJson(_saleJson('sale-remote-1')));
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/settlement-quote')) {
          return _json(200, {
            'data': {
              'saleId': 'sale-remote-1',
              'asOfDate': '2026-09-16T00:00:00.000Z',
              'principalOutstanding': 800,
              'dueInterest': 8,
              'lateFees': 0,
              'futureInterestWaived': 100,
              'settlementAmount': 808,
              'quoteVersion': 'v1',
            },
          });
        }
        if (request.method == 'POST' && request.url.path.endsWith('/settle')) {
          settled = true;
          return _json(200, {
            'data': {'ok': true},
          });
        }
        return _json(404, {'message': 'unexpected ${request.url.path}'});
      });
      final sales = SalesRepository(appDatabase: appDatabase, apiClient: client);
      final payments = PaymentsRepository(
        appDatabase: appDatabase,
        apiClient: client,
      );

      await sales.fetchAll();
      expect(await sales.fetchCachedList(), hasLength(1));

      final localSaleId = BackendEntityIdRegistry.instance.register(
        'sales',
        'sale-remote-1',
      );
      final quote = await payments.fetchSettlementQuote(localSaleId);
      await payments.settleSale(
        saleId: localSaleId,
        quote: quote,
        paymentMethod: 'efectivo',
      );

      // La liquidacion salda la venta: el snapshot anterior (con su conteo de
      // vencidas) no puede sobrevivir.
      expect(settled, isTrue, reason: 'debe usar el endpoint real /settle');
      expect(await sales.fetchCachedList(), isEmpty);
    },
  );

  test(
    'CACHE HARDENING: un snapshot de otro dia de negocio se descarta (day rollover)',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient(
        (_) async => _json(200, _saleItemsJson(_saleJson('sale-remote-1'))),
      );
      final sales = SalesRepository(appDatabase: appDatabase, apiClient: client);

      await sales.fetchAll();
      expect(await sales.fetchCachedList(), hasLength(1));

      // Se envejece el snapshot a un dia de negocio anterior: una cuota puede
      // pasar a vencida solo porque cambio el dia, sin ninguna escritura.
      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.salesListCacheTable,
        columns: ['payload'],
        where: 'cache_key = ?',
        whereArgs: const ['default'],
        limit: 1,
      );
      final payload =
          jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
      payload['savedAt'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 3))
          .toIso8601String();
      await db.update(
        DatabaseSchema.salesListCacheTable,
        {'payload': jsonEncode(payload)},
        where: 'cache_key = ?',
        whereArgs: const ['default'],
      );

      // El conteo de ayer NO puede sobrevivir al cambio de dia de negocio.
      expect(await sales.fetchCachedList(), isEmpty);
    },
  );

  test(
    'CACHE HARDENING: la lista cachea el NUMERO de vencidas, nunca el texto',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final client = await _backendClient(
        (_) async => _json(
          200,
          _saleItemsJson(_saleJson('sale-remote-1', overdueInstallmentCount: 2)),
        ),
      );
      final sales = SalesRepository(appDatabase: appDatabase, apiClient: client);

      final summaries = await sales.fetchAll();
      expect(summaries.single.overdueInstallmentCount, 2);

      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.salesListCacheTable,
        columns: ['payload'],
        where: 'cache_key = ?',
        whereArgs: const ['default'],
        limit: 1,
      );
      final payload = rows.first['payload'] as String;
      expect(payload.contains('"overdueInstallmentCount":2'), isTrue);
      expect(payload.toLowerCase().contains('cuota vencida'), isFalse);

      // La UI es la unica que arma el texto a partir del entero.
      expect(summaries.single.overdueInstallmentsLabel, '2 cuotas vencidas');
    },
  );

  test(
    'CLOUD DOWNLOAD REAL: descargar cuotas invalida el snapshot de la lista',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: await _backendClient(
          (_) async => _json(200, _saleItemsJson(_saleJson('sale-remote-1'))),
        ),
      );
      await sales.fetchAll();
      expect(await sales.fetchCachedList(), hasLength(1));

      // RUTA REAL: respuesta cloud -> SyncService -> merge -> invalidacion.
      final api = FakeSyncDownloadApiClient()
        ..recordsByScope = {
          'installments': [_cloudInstallmentRecord()],
        };
      final syncService = await _syncDownloadServiceFor(appDatabase, api);
      await syncService.downloadUpdatesForScopes(['installments']);

      expect(api.downloadCalls, greaterThan(0));
      // Una descarga financiera puede cambiar el conteo derivado: el snapshot
      // anterior no puede seguir sirviendose. Sin reiniciar ni limpiar a mano.
      expect(await sales.fetchCachedList(), isEmpty);
    },
  );

  test(
    'CLOUD DOWNLOAD REAL sin registros financieros: el snapshot valido se conserva',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: await _backendClient(
          (_) async => _json(200, _saleItemsJson(_saleJson('sale-remote-1'))),
        ),
      );
      await sales.fetchAll();
      expect(await sales.fetchCachedList(), hasLength(1));

      final api = FakeSyncDownloadApiClient()
        ..recordsByScope = {'installments': const <Map<String, dynamic>>[]};
      final syncService = await _syncDownloadServiceFor(appDatabase, api);
      await syncService.downloadUpdatesForScopes(['installments']);

      expect(api.downloadCalls, greaterThan(0));
      // Sin cambios financieros no hay invalidacion innecesaria: no se degrada
      // el arranque visual de Ventas.
      expect(await sales.fetchCachedList(), hasLength(1));
    },
  );
}

/// Arnés minimo del camino REAL de descarga para la invalidacion de caches.
Future<SyncService> _syncDownloadServiceFor(
  AppDatabase appDatabase,
  FakeSyncDownloadApiClient apiClient,
) async {
  final configRepository = SyncConfigRepository(
    settingsRepository: SettingsRepository(appDatabase: appDatabase),
    preferencesFactory: SharedPreferences.getInstance,
  );
  final queueService = SyncQueueService.test(
    appDatabase: appDatabase,
    configRepository: configRepository,
    apiClient: apiClient,
    conflictService: SyncConflictService(appDatabase: appDatabase),
  );
  final syncService = SyncService(
    repositories: [InstallmentsSyncRepository(appDatabase: appDatabase)],
    configRepository: configRepository,
    apiClient: apiClient,
    syncQueueService: queueService,
    appDatabase: appDatabase,
    allowCloudPullOverride: true,
  );
  await configRepository.saveBaseUrl('http://127.0.0.1:9999/api');
  await configRepository.saveJwtToken('jwt-test');
  return syncService;
}

Map<String, dynamic> _cloudInstallmentRecord() {
  return {
    'id': 'remote-inst-1',
    'sync_id': 'inst-sync-1',
    'sale_sync_id': 'sale-sync-1',
    'version': 2,
    'installment_number': 1,
    'due_date': '2026-09-15T00:00:00.000',
    'opening_balance': 1000.0,
    'principal_amount': 900.0,
    'interest_amount': 100.0,
    'total_amount': 1000.0,
    'paid_amount': 0.0,
    'paid_principal_amount': 0.0,
    'paid_interest_amount': 0.0,
    'ending_balance': 100.0,
    'status': 'pendiente',
    'created_at': '2026-08-15T00:00:00.000',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'deleted_at': null,
  };
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
  int overdueInstallmentCount = 0,
}) {
  return {
    'id': remoteId,
    'syncId': 'sale-sync-$remoteId',
    'client': client,
    'cedula': '00112345678',
    'overdueInstallmentCount': overdueInstallmentCount,
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
