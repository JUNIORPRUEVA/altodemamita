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
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'cloud_first_business_repositories_',
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
    'CLOUD_AUTHORITATIVE uses backend for online business writes without sync_queue',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      await configRepository.saveJwtToken('jwt-test-token');
      final requested = <String>[];
      final backendClient = BackendApiClient(
        syncConfigRepository: configRepository,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          expect(request.headers['authorization'], 'Bearer jwt-test-token');

          if (request.method == 'POST' &&
              request.url.path == '/api/business/clients') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['name'], 'Cliente Cloud');
            return _json(201, {
              'data': {
                'client': {
                  'id': 'client-remote-1',
                  'syncId': 'client-sync-1',
                  'name': 'Cliente Cloud',
                  'document': '00112345678',
                  'phone': null,
                  'address': null,
                  'version': 1,
                  'createdAt': '2026-09-09T10:00:00.000Z',
                  'updatedAt': '2026-09-09T10:00:00.000Z',
                  'deletedAt': null,
                },
              },
            });
          }

          if (request.method == 'GET' &&
              request.url.path == '/api/business/clients') {
            return _json(200, {
              'data': {
                'items': [
                  {
                    'id': 'client-remote-1',
                    'syncId': 'client-sync-1',
                    'name': 'Cliente Cloud',
                    'document': '00112345678',
                    'createdAt': '2026-09-09T10:00:00.000Z',
                    'updatedAt': '2026-09-09T10:00:00.000Z',
                  },
                ],
              },
            });
          }

          if (request.method == 'POST' &&
              request.url.path == '/api/business/lots') {
            return _json(201, {
              'data': {
                'lot': {
                  'id': 'lot-remote-1',
                  'syncId': 'product-sync-1',
                  'block': 'A',
                  'number': '1',
                  'area': 100,
                  'price': 10,
                  'status': 'disponible',
                  'version': 1,
                  'createdAt': '2026-09-09T10:00:00.000Z',
                  'updatedAt': '2026-09-09T10:00:00.000Z',
                  'deletedAt': null,
                },
              },
            });
          }

          if (request.method == 'GET' &&
              request.url.path == '/api/business/lots') {
            return _json(200, {
              'data': {
                'items': [
                  {
                    'id': 'lot-remote-1',
                    'syncId': 'product-sync-1',
                    'block': 'A',
                    'number': '1',
                    'area': 100,
                    'price': 10,
                    'status': 'disponible',
                    'createdAt': '2026-09-09T10:00:00.000Z',
                    'updatedAt': '2026-09-09T10:00:00.000Z',
                  },
                ],
              },
            });
          }

          if (request.method == 'POST' &&
              request.url.path == '/api/authoritative/sales') {
            expect(request.headers['idempotency-key'], isNotEmpty);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['clientId'], 'client-remote-1');
            expect(body['lotId'], 'lot-remote-1');
            return _json(201, {
              'data': {'saleId': 'sale-remote-1', 'saleSyncId': 'sale-sync-1'},
            });
          }

          if (request.method == 'PATCH' &&
              request.url.path == '/api/business/sales/sale-remote-1') {
            expect(request.headers['idempotency-key'], isNotEmpty);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['clientId'], 'client-remote-1');
            expect(body['lotId'], 'lot-remote-1');
            expect(body['salePrice'], 1100);
            expect(body['installmentCount'], 10);
            return _json(200, {
              'data': {
                'saleId': 'sale-remote-1',
                'saleSyncId': 'sale-sync-1',
                'status': 'activa',
                'balance': 880,
                'initialRequiredAmount': 220,
                'initialPaid': 220,
                'initialPendingAmount': 0,
              },
            });
          }

          if (request.method == 'GET' &&
              request.url.path == '/api/owner/sales') {
            return _json(200, {
              'data': {
                'items': [
                  {
                    'id': 'sale-remote-1',
                    'syncId': 'sale-sync-1',
                    'client': 'Cliente Cloud',
                    'cedula': '00112345678',
                    'lot': 'MA-S1',
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
                  },
                ],
              },
            });
          }

          if (request.method == 'POST' &&
              request.url.path == '/api/authoritative/payments') {
            expect(request.headers['idempotency-key'], isNotEmpty);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['saleId'], 'sale-remote-1');
            expect(body['amountPaid'], 50);
            return _json(201, {
              'data': {
                'saleId': 'sale-remote-1',
                'paymentIds': ['payment-remote-1'],
              },
            });
          }

          return _json(404, {'message': 'unexpected ${request.url.path}'});
        }),
      );

      final clients = ClientRepository(
        appDatabase: appDatabase,
        apiClient: backendClient,
      );
      final lots = LotRepository(
        appDatabase: appDatabase,
        apiClient: backendClient,
      );
      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: backendClient,
      );
      final payments = PaymentsRepository(
        appDatabase: appDatabase,
        apiClient: backendClient,
      );
      final now = DateTime.parse('2026-09-09T10:00:00.000Z');

      await clients.save(
        Client(
          fullName: 'Cliente Cloud',
          documentId: '00112345678',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await lots.save(
        Lot(
          blockNumber: 'A',
          lotNumber: '1',
          area: 100,
          pricePerSquareMeter: 10,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final remoteClients = await clients.fetchAll();
      final remoteLots = await lots.fetchAll();
      final saleId = await sales.createSale(
        SaleDraft(
          clientId: remoteClients.single.id!,
          lotId: remoteLots.single.id!,
          userId: 1,
          saleDate: now,
          salePrice: 1000,
          downPaymentPercentage: 20,
          requiredInitialPayment: 200,
          initialPaymentPaid: 0,
          initialPaymentDeadline: now.add(const Duration(days: 30)),
          monthlyInterest: 1,
          installmentCount: 12,
          status: 'apartado',
        ),
      );
      await sales.fetchAll();
      await sales.updateSale(
        saleId,
        SaleDraft(
          clientId: remoteClients.single.id!,
          lotId: remoteLots.single.id!,
          userId: 1,
          saleDate: now,
          salePrice: 1100,
          downPaymentPercentage: 20,
          requiredInitialPayment: 220,
          initialPaymentPaid: 220,
          monthlyInterest: 1,
          installmentCount: 10,
          status: 'activa',
        ),
      );
      await payments.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: now,
          amountPaid: 50,
          paymentMethod: 'efectivo',
        ),
      );

      expect(requested, contains('POST /api/business/clients'));
      expect(requested, contains('POST /api/business/lots'));
      expect(requested, contains('POST /api/authoritative/sales'));
      expect(requested, contains('PATCH /api/business/sales/sale-remote-1'));
      expect(requested, contains('POST /api/authoritative/payments'));
      expect(await _syncQueueCount(appDatabase), 0);
    },
  );

  test(
    'CLOUD_AUTHORITATIVE fetchDetail trae cuotas desde /owner/sales/:id (resumen financiero no vacio)',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      await configRepository.saveJwtToken('jwt-test-token');

      final requested = <String>[];
      final backendClient = BackendApiClient(
        syncConfigRepository: configRepository,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          expect(request.headers['authorization'], 'Bearer jwt-test-token');

          if (request.method == 'GET' &&
              request.url.path == '/api/owner/sales') {
            return _json(200, {
              'data': {
                'items': [
                  _saleDetailCloudJson(saleRemoteId: 'sale-remote-1'),
                ],
              },
            });
          }

          if (request.method == 'GET' &&
              request.url.path == '/api/owner/sales/sale-remote-1') {
            return _json(200, {
              'data': {
                'sale': _saleDetailCloudJson(saleRemoteId: 'sale-remote-1'),
              },
            });
          }

          return _json(404, {'message': 'unexpected ${request.url.path}'});
        }),
      );

      final sales = SalesRepository(
        appDatabase: appDatabase,
        apiClient: backendClient,
      );

      final summaries = await sales.fetchAll();
      expect(summaries, hasLength(1));
      final localSaleId = summaries.single.id;

      final fetched = await sales.fetchDetail(localSaleId);
      expect(requested, contains('GET /api/owner/sales/sale-remote-1'));
      if (fetched == null) {
        fail('fetchDetail devolvió null; esperaba el detalle con cuotas.');
      }
      final detail = fetched;
      expect(detail.installments, hasLength(12));
      expect(detail.installments.first.installmentNumber, 1);
      expect(
        detail.installments.first.principalAmount,
        closeTo(35481.95, 0.01),
      );
      expect(detail.installments.first.interestAmount, closeTo(4500, 0.01));
      expect(detail.installments.first.totalAmount, closeTo(39981.95, 0.01));
      expect(detail.installments.last.installmentNumber, 12);
      expect(detail.sale.paidInitialPayment, closeTo(200, 0.001));
      expect(detail.sale.pendingBalance, closeTo(800, 0.001));
      expect(detail.initialPaymentMethod, 'efectivo');
    },
  );
}

Map<String, Object?> _saleDetailCloudJson({required String saleRemoteId}) {
  final installments = List.generate(12, (index) {
    final number = index + 1;
    // Amortización real de 800 financiados a 1% mensual en 12 cuotas.
    const principal = [35481.95, 35836.77, 36195.14, 36557.09, 36922.66, 37291.89, 37664.8, 38041.45, 38421.87, 38806.09, 39194.15, 39586.14];
    const interest = [4500.0, 4145.18, 3786.81, 3424.86, 3059.29, 2690.06, 2317.15, 1940.5, 1560.08, 1175.86, 787.8, 395.86];
    return {
      'id': 'installment-remote-$number',
      'syncId': 'installment-sync-$number',
      'installmentNumber': number,
      'dueDate': '2026-10-09T15:42:14.243Z',
      'principalAmount': '${principal[number - 1]}',
      'interestAmount': '${interest[number - 1]}',
      'amount': '39981.95',
      'paidAmount': '0',
      'status': 'pendiente',
      'createdAt': '2026-09-09T15:42:14.243Z',
      'updatedAt': '2026-09-09T15:42:14.243Z',
    };
  });

  return {
    'id': saleRemoteId,
    'saleId': saleRemoteId,
    'syncId': 'sale-sync-1',
    'client': 'Cliente Cloud',
    'cedula': '00112345678',
    'clientEntity': {
      'id': 'client-remote-1',
      'syncId': 'client-sync-1',
      'name': 'Cliente Cloud',
      'document': '00112345678',
      'phone': '8090000000',
    },
    'lot': 'MA-S1',
    'lotEntity': {
      'id': 'lot-remote-1',
      'syncId': 'product-sync-1',
      'block': 'A',
      'number': '1',
      'area': '100',
      'price': '10',
      'pricePerSquareMeter': '10',
      'status': 'disponible',
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
    'createdAt': '2026-09-09T10:00:00.000Z',
    'updatedAt': '2026-09-09T10:00:00.000Z',
    'payments': [
      {
        'method': 'efectivo',
        'amount': '200',
        'paidAt': '2026-09-09T10:00:00.000Z',
      },
    ],
    'installments': installments,
  };
}

http.Response _json(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Future<int> _syncQueueCount(AppDatabase appDatabase) async {
  final db = await appDatabase.database;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM ${DatabaseSchema.syncQueueTable}',
  );
  return (rows.first['total'] as num?)?.toInt() ?? 0;
}
