import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../models/owner_snapshot.dart';

class ApiClient {
  const ApiClient(this.baseUrl);

  final String baseUrl;

  Future<OwnerSnapshot> fetchSnapshot() async {
    final results = await Future.wait([
      _get('/owner/dashboard'),
      _list('/owner/clients'),
      _list('/owner/sellers'),
      _list('/owner/lots'),
      _list('/owner/sales'),
      _list('/owner/installments'),
      _list('/owner/payments'),
    ]);
    return OwnerSnapshot(
      dashboard: (results[0]['data'] as Map).cast<String, dynamic>(),
      clients: listOfMaps(results[1]['items']),
      sellers: listOfMaps(results[2]['items']),
      lots: listOfMaps(results[3]['items']),
      sales: listOfMaps(results[4]['items']),
      installments: listOfMaps(results[5]['items']),
      payments: listOfMaps(results[6]['items']),
    );
  }

  Future<Map<String, dynamic>> _list(String path) async {
    final body = await _get('$path?pageSize=200');
    return (body['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final parsed = Uri.parse('$baseUrl$path');
    final uri = parsed.replace(
      queryParameters: {
        ...parsed.queryParameters,
        'companyTenantKey': companyTenantKey,
      },
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('x-company-tenant-key', companyTenantKey);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: $responseBody',
          uri: uri,
        );
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const FormatException('Respuesta invalida del backend.');
      }
      return decoded.cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }
}

List<Map<String, dynamic>> listOfMaps(Object? maybeList) {
  if (maybeList is List) {
    return maybeList.cast<Map<String, dynamic>>();
  }
  return [];
}
