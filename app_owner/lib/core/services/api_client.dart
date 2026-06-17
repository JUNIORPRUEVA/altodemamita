import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../models/owner_snapshot.dart';

class ApiClient {
  const ApiClient(this.baseUrl);

  final String baseUrl;

  /// Log de depuración para la URL base usada
  void _logUrl() {
    if (kDebugMode) {
      debugPrint('[OwnerApi] OWNER_API_BASE_URL=$baseUrl');
      developer.log(
        'OWNER_API_BASE_URL=$baseUrl',
        name: 'SistemaSolares.OwnerApi',
      );
    }
  }

  Future<OwnerSnapshot> fetchSnapshot() async {
    _logUrl();
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
      if (kDebugMode) {
        debugPrint('[OwnerApi] request url=$uri');
        developer.log(
          'request url=$uri',
          name: 'SistemaSolares.OwnerApi',
        );
      }
      final request = await client.getUrl(uri);
      request.headers.set('x-company-tenant-key', companyTenantKey);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (kDebugMode) {
        debugPrint('[OwnerApi] response status=${response.statusCode} url=$uri');
        developer.log(
          'response status=${response.statusCode} url=$uri',
          name: 'SistemaSolares.OwnerApi',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorMsg = 'HTTP ${response.statusCode}: $responseBody';
        if (kDebugMode) {
          debugPrint('[OwnerApi] request failed url=$uri error=$errorMsg');
          developer.log(
            'request failed url=$uri error=$errorMsg',
            name: 'SistemaSolares.OwnerApi',
          );
        }
        throw HttpException(errorMsg, uri: uri);
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const FormatException('Respuesta invalida del backend.');
      }
      return decoded.cast<String, dynamic>();
    } on SocketException catch (e) {
      if (kDebugMode) {
        debugPrint('[OwnerApi] connection error url=$uri error=$e');
        developer.log(
          'connection error url=$uri error=$e',
          name: 'SistemaSolares.OwnerApi',
        );
      }
      rethrow;
    } on HttpException catch (e) {
      if (kDebugMode) {
        debugPrint('[OwnerApi] http error url=$uri error=$e');
        developer.log(
          'http error url=$uri error=$e',
          name: 'SistemaSolares.OwnerApi',
        );
      }
      rethrow;
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
