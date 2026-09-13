import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_owner/core/services/api_client.dart';

void main() {
  late HttpServer server;
  final requests = <String>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;

      if (request.method == 'POST' && request.uri.path == '/auth/refresh') {
        request.response.write(
          jsonEncode({
            'data': {
              'accessToken': 'owner-refreshed-token',
              'user': {'fullName': 'Dueño'},
            },
          }),
        );
        await request.response.close();
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path == '/customer/snapshot' &&
          request.headers.value(HttpHeaders.authorizationHeader) ==
              'Bearer owner-refreshed-token') {
        request.response.write(jsonEncode({'data': _snapshotPayload()}));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'error': 'not found'}));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('refreshes configured session and loads owner snapshot data', () async {
    final baseUrl = 'http://127.0.0.1:${server.port}';
    final refreshed = await ApiClient(
      baseUrl,
    ).refresh('owner-configured-token');
    final snapshot = await ApiClient(
      baseUrl,
      accessToken: refreshed.accessToken,
    ).fetchSnapshot();

    expect(refreshed.accessToken, 'owner-refreshed-token');
    expect(requests, contains('POST /auth/refresh'));
    expect(requests, contains('GET /customer/snapshot'));
    expect(snapshot.dashboard['counts']['sales'], 3);
    expect(snapshot.dashboard['counts']['installments'], 12);
    expect(snapshot.dashboard['totals']['balance'], 175000);
    expect(snapshot.clients.single['name'], 'Cliente de prueba');
    expect(snapshot.sales.single['client'], 'Cliente de prueba');
    expect(snapshot.sales.single['lot'], 'MA-S1');
    expect(snapshot.installments.single['status'], 'pendiente');
    expect(snapshot.payments.single['amount'], 25000);
  });
}

Map<String, Object?> _snapshotPayload() {
  return {
    'dashboard': {
      'counts': {'sales': 3, 'installments': 12, 'lots': 4},
      'totals': {'paid': 25000, 'balance': 175000, 'sold': 200000},
    },
    'clients': [
      {
        'syncId': 'client-owner-1',
        'name': 'Cliente de prueba',
        'document': '001',
      },
    ],
    'sellers': [
      {'syncId': 'seller-owner-1', 'name': 'Vendedor de prueba'},
    ],
    'lots': [
      {
        'syncId': 'lot-owner-1',
        'block': 'A',
        'number': '1',
        'status': 'vendido',
      },
    ],
    'sales': [
      {
        'syncId': 'sale-owner-1',
        'clientSyncId': 'client-owner-1',
        'lotSyncId': 'lot-owner-1',
        'sellerSyncId': 'seller-owner-1',
        'total': 200000,
        'balance': 175000,
      },
    ],
    'installments': [
      {
        'syncId': 'installment-owner-1',
        'saleSyncId': 'sale-owner-1',
        'installmentNumber': 1,
        'totalAmount': 15000,
        'paidAmount': 0,
        'status': 'pendiente',
      },
    ],
    'payments': [
      {
        'syncId': 'payment-owner-1',
        'saleSyncId': 'sale-owner-1',
        'clientSyncId': 'client-owner-1',
        'amount': 25000,
        'paymentType': 'abono_inicial',
      },
    ],
  };
}
