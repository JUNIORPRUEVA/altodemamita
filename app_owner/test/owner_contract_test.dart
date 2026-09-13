import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_owner/core/constants.dart';
import 'package:sistema_solares_owner/core/models/owner_snapshot.dart';
import 'package:sistema_solares_owner/core/services/api_client.dart';

void main() {
  test('default owner API points to production backend', () {
    expect(baseUrl, 'https://altomamita-backend.gcdndd.easypanel.host');
    expect(baseUrl, isNot(contains('localhost')));
    expect(baseUrl, isNot(contains('127.0.0.1')));
    expect(baseUrl, isNot(contains('10.0.2.2')));
    expect(baseUrl, isNot(contains('3301')));
    expect(baseUrl, isNot(contains('3302')));
    expect(baseUrl, isNot(contains('acceptance')));
  });

  test('auth session parsing stores only user-facing session fields', () {
    final session = AuthSession.fromResponse({
      'success': true,
      'data': {
        'accessToken': 'jwt-test',
        'user': {'email': 'cliente@example.test', 'fullName': 'Cliente Owner'},
      },
    });

    expect(session.accessToken, 'jwt-test');
    expect(session.email, 'cliente@example.test');
    expect(session.userName, 'Cliente Owner');
    expect(
      session.toJson().keys,
      containsAll(['accessToken', 'userName', 'email']),
    );
    expect(session.toJson().keys, isNot(contains('password')));
    expect(session.toJson().keys, isNot(contains('DATABASE_URL')));
  });

  test('owner snapshot parses dashboard and customer-scoped lists', () {
    final snapshot = OwnerSnapshot.fromJson({
      'dashboard': {
        'scope': 'authenticated-customer',
        'counts': {'clients': 1, 'sales': 1},
      },
      'clients': [
        {'syncId': 'client-1', 'name': 'Cliente Uno'},
      ],
      'sales': [
        {'syncId': 'sale-1', 'clientSyncId': 'client-1'},
      ],
      'lots': [
        {'syncId': 'lot-1'},
      ],
      'installments': [
        {'syncId': 'installment-1', 'saleSyncId': 'sale-1'},
      ],
      'payments': [
        {'syncId': 'payment-1', 'saleSyncId': 'sale-1'},
      ],
      'sellers': [],
    });

    expect(snapshot.dashboard['scope'], 'authenticated-customer');
    expect(snapshot.clients, hasLength(1));
    expect(snapshot.sales.single['clientSyncId'], 'client-1');
    expect(snapshot.toJson()['payments'], hasLength(1));
  });
}
