import 'dart:io';

import 'package:sistema_solares/core/cloud_foundation/cloud_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('real client service layer works through public HTTPS UAT', () async {
    final env = Platform.environment;
    final api = CloudApiClient(baseUrl: env['UAT_BASE_URL']);
    final prefix = requireEnv(env, 'UAT_PREFIX');

    Future<CloudApiResponse> expectSuccess(
      String name,
      Future<CloudApiResponse> future,
    ) async {
      final response = await future;
      expect(
        response.isSuccess,
        isTrue,
        reason: '$name failed: ${response.statusCode} ${response.body}',
      );
      stdout.writeln('$name PASS');
      return response;
    }

    final login = await expectSuccess(
      'login',
      api.login(
        email: requireEnv(env, 'UAT_EMAIL'),
        password: requireEnv(env, 'UAT_PASSWORD'),
      ),
    );
    final token =
        login.body['accessToken']?.toString() ??
        ((login.body['data'] as Map?)?['accessToken']?.toString() ?? '');
    expect(token, isNotEmpty, reason: 'login failed: missing access token');

    await expectSuccess('refresh', api.refresh(refreshToken: token));
    await expectSuccess('auth me', api.me(accessToken: token));
    await expectSuccess(
      'initial load profile',
      api.getCompanyProfile(accessToken: token),
    );
    await expectSuccess(
      'initial load financial parameters',
      api.getFinancialParameters(accessToken: token),
    );

    final sale = await expectSuccess(
      'online sale',
      api.sendOperation(
        operationType: 'sale.create',
        operationId: '$prefix-client-sale-op',
        accessToken: token,
        payload: {
          'clientId': requireEnv(env, 'UAT_CLIENT_ID'),
          'lotId': requireEnv(env, 'UAT_LOT_ID'),
          'sellerId': requireEnv(env, 'UAT_SELLER_ID'),
          'salePrice': 75000,
          'downPaymentPercentage': 20,
          'initialPaymentPaid': 15000,
          'monthlyInterest': 1,
          'installmentCount': 12,
          'initialPaymentMethod': 'efectivo',
          'reference': '$prefix-client-init',
          'saleDate': '2026-09-08T12:00:00.000Z',
          'syncId': '$prefix-client-sale',
        },
      ),
    );
    final saleData = sale.body['data'] as Map<String, Object?>;
    final saleId = saleData['saleId']?.toString() ?? '';
    expect(saleId, isNotEmpty, reason: 'online sale failed: missing saleId');

    await expectSuccess(
      'online payment',
      api.sendOperation(
        operationType: 'payment.register',
        operationId: '$prefix-client-payment-op',
        accessToken: token,
        payload: {
          'saleId': saleId,
          'paymentDate': '2026-10-08T12:00:00.000Z',
          'amountPaid': 1000,
          'paymentMethod': 'efectivo',
          'paymentType': 'cuota',
          'reference': '$prefix-client-payment',
        },
      ),
    );

    final readBack = await expectSuccess(
      'read-back sales',
      api.get('/owner/sales', accessToken: token, query: {'pageSize': '20'}),
    );
    final items =
        ((readBack.body['data'] as Map?)?['items'] as List?) ?? const [];
    expect(
      items.any((item) => item is Map && item['id'] == saleId),
      isTrue,
      reason: 'read-back sales failed: sale not found',
    );
    stdout.writeln('REAL_CLIENT_PUBLIC_HTTPS PASS saleId=$saleId');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

String requireEnv(Map<String, String> env, String key) {
  final value = env[key]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('missing env $key');
    exit(1);
  }
  return value;
}
