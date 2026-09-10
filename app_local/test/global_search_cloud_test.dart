import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/global_search/data/global_search_repository.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';

import 'helpers/fake_backend.dart';

/// Regresión: el Buscador en CLOUD_AUTHORITATIVE debe obtener el historial del
/// cliente (ventas/cuotas/pagos) desde PostgreSQL vía
/// `GET /owner/clients/:clientId`, no desde joins SQLite con ids locales que no
/// coinciden con los ids sintéticos cloud.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'global_search_cloud_',
    );
    appDatabase = AppDatabase.test(p.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<GlobalSearchRepository> buildRepository(
    MockClient client,
  ) async {
    final configRepository = FakeSyncConfigRepository(
      settings: buildFakeSettings(),
    );
    await configRepository.saveJwtToken('jwt-test-token');
    final apiClient = BackendApiClient(
      syncConfigRepository: configRepository,
      client: client,
    );
    final clients = ClientRepository(appDatabase: appDatabase, apiClient: apiClient);
    final lots = LotRepository(appDatabase: appDatabase, apiClient: apiClient);
    return GlobalSearchRepository(
      appDatabase: appDatabase,
      clientRepository: clients,
      lotRepository: lots,
      apiClient: apiClient,
    );
  }

  test(
    'CLOUD_AUTHORITATIVE buscador muestra cliente con 1 venta y su historial real',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final repository = await buildRepository(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/business/clients') {
            return _json(200, {
              'data': {
                'items': [_clientJson()],
                'total': 1,
              },
            });
          }
          if (path == '/api/business/lots') {
            return _json(200, {'data': {'items': <Object>[], 'total': 0}});
          }
          if (path == '/api/owner/clients/client-remote-1') {
            return _json(200, {
              'data': {
                'client': _clientJson(),
                'summary': {
                  'sales': 1,
                  'activeSales': 1,
                  'installments': 12,
                  'payments': 1,
                  'totalSold': 500000,
                  'totalPaid': 50000,
                  'pendingBalance': 450000,
                },
                'sales': [_saleJson()],
              },
            });
          }
          return _json(404, {'message': 'unexpected $path'});
        }),
      );

      final results = await repository.search('Junior');
      expect(results, hasLength(1));
      final result = results.single;
      expect(result.matchType, 'client');
      expect(result.client?.fullName, 'Junior pruebas');
      expect(result.relatedSales, hasLength(1));
      expect(result.displaySubtitle, contains('1 venta(s)'));

      final sale = result.relatedSales.single;
      expect(sale['precio_venta'] as double, closeTo(500000, 0.001));
      expect(sale['saldo_pendiente'] as double, closeTo(450000, 0.001));
      expect(sale['estado'], 'activa');
      expect(sale['manzana_numero'], 'md');
      expect(sale['solar_numero'], '122');
      expect(sale['cantidad_cuotas'], 12);

      expect(result.relatedInstallments, hasLength(12));
      expect(
        result.relatedInstallments.first.principalAmount,
        closeTo(35481.95, 0.01),
      );
      expect(
        result.relatedInstallments.last.installmentNumber,
        12,
      );

      expect(result.relatedPayments, hasLength(1));
      final payment = result.relatedPayments.single;
      expect(payment['monto_pagado'] as double, closeTo(50000, 0.001));
      expect(payment['tipo_pago'], 'abono_inicial');
      expect(result.pendingInstallmentsCount, greaterThan(0));
    },
  );

  test(
    'CLOUD_AUTHORITATIVE buscador muestra 0 venta(s) para cliente sin historial',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final repository = await buildRepository(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/business/clients') {
            return _json(200, {
              'data': {
                'items': [_clientJson(id: 'client-no-sale', syncId: 'client-nosale-sync')],
                'total': 1,
              },
            });
          }
          if (path == '/api/business/lots') {
            return _json(200, {'data': {'items': <Object>[], 'total': 0}});
          }
          if (path == '/api/owner/clients/client-no-sale') {
            return _json(200, {
              'data': {
                'client': _clientJson(id: 'client-no-sale', syncId: 'client-nosale-sync'),
                'summary': {
                  'sales': 0,
                  'activeSales': 0,
                  'installments': 0,
                  'payments': 0,
                },
                'sales': <Object>[],
              },
            });
          }
          return _json(404, {'message': 'unexpected $path'});
        }),
      );

      final results = await repository.search('40299999999');
      expect(results, hasLength(1));
      final result = results.single;
      expect(result.relatedSales, isEmpty);
      expect(result.relatedInstallments, isEmpty);
      expect(result.relatedPayments, isEmpty);
      expect(result.displaySubtitle, contains('0 venta(s)'));
    },
  );
}

Map<String, Object?> _clientJson({String id = 'client-remote-1', String syncId = 'client-sync-1'}) {
  return {
    'id': id,
    'syncId': syncId,
    'name': 'Junior pruebas',
    'document': '40238377333',
    'phone': '8091234567',
    'address': null,
    'createdAt': '2026-09-09T10:00:00.000Z',
    'updatedAt': '2026-09-09T10:00:00.000Z',
  };
}

Map<String, Object?> _saleJson() {
  final installments = List.generate(12, (index) {
    final number = index + 1;
    const principal = [35481.95, 35836.77, 36195.14, 36557.09, 36922.66, 37291.89, 37664.8, 38041.45, 38421.87, 38806.09, 39194.15, 39586.14];
    const interest = [4500.0, 4145.18, 3786.81, 3424.86, 3059.29, 2690.06, 2317.15, 1940.5, 1560.08, 1175.86, 787.8, 395.86];
    return {
      'id': 'installment-remote-$number',
      'syncId': 'installment-sync-$number',
      'installmentNumber': number,
      'dueDate': '2026-10-09T15:42:14.243Z',
      'openingBalance': '450000',
      'principalAmount': '${principal[number - 1]}',
      'interestAmount': '${interest[number - 1]}',
      'amount': '39981.95',
      'paidAmount': '0',
      'endingBalance': '0',
      'status': 'pendiente',
      'createdAt': '2026-09-09T15:42:14.243Z',
      'updatedAt': '2026-09-09T15:42:14.243Z',
    };
  });

  return {
    'id': 'sale-remote-1',
    'syncId': 'sale-sync-1',
    'status': 'activa',
    'saleDate': '2026-09-09T10:00:00.000Z',
    'createdAt': '2026-09-09T10:00:00.000Z',
    'updatedAt': '2026-09-09T10:00:00.000Z',
    'total': '500000',
    'initialPercentage': '10',
    'initialRequiredAmount': '50000',
    'initialPaid': '50000',
    'initialPendingAmount': '0',
    'reservationMinimumAmount': null,
    'reservationPaidAmount': '0',
    'initialPaymentDeadline': null,
    'activationDate': '2026-09-09T10:00:00.000Z',
    'financedBalance': '450000',
    'monthlyInterestRate': '1',
    'installmentCount': 12,
    'balance': '450000',
    'lotCode': 'Mmd-S122',
    'lot': {
      'id': 'lot-remote-1',
      'syncId': 'lot-sync-1',
      'block': 'md',
      'number': '122',
      'area': '200',
      'price': '2500',
      'status': 'vendido',
    },
    'sellerName': 'Vendedor Uno',
    'operatorUserName': 'Administrador',
    'installments': installments,
    'payments': [
      {
        'id': 'payment-remote-1',
        'syncId': 'payment-sync-1',
        'paidAt': '2026-09-09T10:05:00.000Z',
        'amount': '50000',
        'method': 'efectivo',
        'paymentType': 'initial',
        'reference': 'REF-001',
        'yearToPay': null,
      },
    ],
  };
}

http.Response _json(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
