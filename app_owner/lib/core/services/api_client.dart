import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../models/owner_snapshot.dart';

const Duration _ownerRequestTimeout = Duration(seconds: 45);

class ApiClient {
  const ApiClient(this.baseUrl, {this.accessToken});

  final String baseUrl;
  final String? accessToken;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final body = await _post('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    return AuthSession.fromResponse(body);
  }

  Future<AuthSession> refresh(String token) async {
    final body = await _post('/auth/refresh', {'token': token});
    return AuthSession.fromResponse(body);
  }

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
    final client = _createHttpClient();
    final List<Object?> results;
    try {
      results = await Future.wait([_get('/customer/snapshot', client: client)]);
    } finally {
      client.close(force: true);
    }
    final snapshotData = ((results[0] as Map<String, dynamic>)['data'] as Map)
        .cast<String, dynamic>();
    final clients = _normalizeClients(listOfMaps(snapshotData['clients']));
    final sellers = _normalizeSellers(listOfMaps(snapshotData['sellers']));
    final lots = _normalizeLots(listOfMaps(snapshotData['lots']));
    final sales = _normalizeSales(
      listOfMaps(snapshotData['sales']),
      clients: clients,
      sellers: sellers,
      lots: lots,
    );
    final installments = _normalizeInstallments(
      listOfMaps(snapshotData['installments']),
      sales: sales,
    );
    final payments = _normalizePayments(
      listOfMaps(snapshotData['payments']),
      clients: clients,
      sales: sales,
      installments: installments,
    );
    return OwnerSnapshot(
      dashboard:
          (snapshotData['dashboard'] as Map?)?.cast<String, dynamic>() ?? {},
      clients: clients,
      sellers: sellers,
      lots: lots,
      sales: sales,
      installments: installments,
      payments: payments,
    );
  }

  Future<OwnerSnapshot> fetchDashboardSnapshot() async {
    _logUrl();
    final snapshotBody = await _get('/customer/snapshot');
    final snapshotData = (snapshotBody['data'] as Map).cast<String, dynamic>();
    return OwnerSnapshot(
      dashboard:
          (snapshotData['dashboard'] as Map?)?.cast<String, dynamic>() ?? {},
      clients: const [],
      sellers: const [],
      lots: const [],
      sales: const [],
      installments: const [],
      payments: const [],
    );
  }

  Future<Map<String, dynamic>> _get(String path, {HttpClient? client}) async {
    final parsed = Uri.parse('$baseUrl$path');
    final uri = parsed.replace(
      queryParameters: {
        ...parsed.queryParameters,
        'companyTenantKey': companyTenantKey,
      },
    );
    final httpClient = client ?? _createHttpClient();
    try {
      if (kDebugMode) {
        debugPrint('[OwnerApi] request url=$uri');
        developer.log('request url=$uri', name: 'SistemaSolares.OwnerApi');
      }
      final request = await httpClient
          .getUrl(uri)
          .timeout(_ownerRequestTimeout);
      _setRequestHeaders(request);
      final response = await request.close().timeout(_ownerRequestTimeout);
      return _decodeResponse(response, uri);
    } finally {
      if (client == null) {
        httpClient.close(force: true);
      }
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final httpClient = _createHttpClient();
    try {
      if (kDebugMode) {
        debugPrint('[OwnerApi] request url=$uri method=POST');
        developer.log(
          'request url=$uri method=POST',
          name: 'SistemaSolares.OwnerApi',
        );
      }
      final request = await httpClient
          .postUrl(uri)
          .timeout(_ownerRequestTimeout);
      _setRequestHeaders(request);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_ownerRequestTimeout);
      return _decodeResponse(response, uri);
    } finally {
      httpClient.close(force: true);
    }
  }

  void _setRequestHeaders(HttpClientRequest request) {
    request.headers.set('x-company-tenant-key', companyTenantKey);
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    final token = accessToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
  }

  Future<Map<String, dynamic>> _decodeResponse(
    HttpClientResponse response,
    Uri uri,
  ) async {
    final responseBody = await utf8.decoder
        .bind(response)
        .join()
        .timeout(_ownerRequestTimeout);
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
  }

  HttpClient _createHttpClient() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30);
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.userName,
    required this.email,
  });

  final String accessToken;
  final String userName;
  final String email;

  factory AuthSession.fromResponse(Map<String, dynamic> body) {
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? body;
    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? {};
    final token = (data['accessToken'] ?? body['accessToken'])?.toString();
    if (token == null || token.trim().isEmpty) {
      throw const FormatException('Respuesta de autenticacion invalida.');
    }
    return AuthSession(
      accessToken: token,
      userName: (user['fullName'] ?? user['name'] ?? '').toString(),
      email: (user['email'] ?? '').toString(),
    );
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'accessToken': accessToken, 'userName': userName, 'email': email};
  }
}

List<Map<String, dynamic>> listOfMaps(Object? maybeList) {
  if (maybeList is List) {
    return maybeList.cast<Map<String, dynamic>>();
  }
  return [];
}

List<Map<String, dynamic>> _normalizeClients(List<Map<String, dynamic>> items) {
  return items
      .map((item) {
        return {
          ...item,
          'syncId': _firstText(item, ['syncId', 'sync_id']),
          'name': _firstText(item, ['name', 'nombre', 'full_name']),
          'document': _firstText(item, ['document', 'document_id', 'cedula']),
          'phone': _firstText(item, ['phone', 'telefono']),
          'address': _firstText(item, ['address', 'direccion']),
          'updatedAt': _firstText(item, ['updatedAt', 'updated_at']),
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _normalizeSellers(List<Map<String, dynamic>> items) {
  return items
      .map((item) {
        return {
          ...item,
          'syncId': _firstText(item, ['syncId', 'sync_id']),
          'name': _firstText(item, ['name', 'nombre', 'full_name']),
          'document': _firstText(item, ['document', 'document_id', 'cedula']),
          'phone': _firstText(item, ['phone', 'telefono']),
          'updatedAt': _firstText(item, ['updatedAt', 'updated_at']),
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _normalizeLots(List<Map<String, dynamic>> items) {
  return items
      .map((item) {
        final block = _firstText(item, ['block', 'block_number', 'manzana']);
        final number = _firstText(item, ['number', 'lot_number', 'numero']);
        return {
          ...item,
          'syncId': _firstText(item, ['syncId', 'sync_id']),
          'block': block,
          'number': number,
          'display': _lotDisplay(block, number),
          'status': _firstText(item, ['status', 'estado']),
          'area': _firstValue(item, ['area', 'metros_cuadrados']),
          'price': _firstValue(item, ['price', 'price_per_square_meter']),
          'updatedAt': _firstText(item, ['updatedAt', 'updated_at']),
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _normalizeSales(
  List<Map<String, dynamic>> items, {
  required List<Map<String, dynamic>> clients,
  required List<Map<String, dynamic>> sellers,
  required List<Map<String, dynamic>> lots,
}) {
  final clientsBySyncId = _bySyncId(clients);
  final sellersBySyncId = _bySyncId(sellers);
  final lotsBySyncId = _bySyncId(lots);

  return items
      .map((item) {
        final clientSyncId = _firstText(item, [
          'clientSyncId',
          'client_sync_id',
        ]);
        final lotSyncId = _firstText(item, [
          'lotSyncId',
          'product_sync_id',
          'lot_sync_id',
          'solar_sync_id',
        ]);
        final sellerSyncId = _firstText(item, [
          'sellerSyncId',
          'seller_sync_id',
        ]);
        final client = clientsBySyncId[clientSyncId];
        final lot = lotsBySyncId[lotSyncId];
        final seller = sellersBySyncId[sellerSyncId];
        return {
          ...item,
          'syncId': _firstText(item, ['syncId', 'sync_id']),
          'saleId': _firstText(item, ['saleId', 'id']),
          'clientSyncId': clientSyncId,
          'lotSyncId': lotSyncId,
          'sellerSyncId': sellerSyncId,
          'client': _firstText(item, ['client']) ?? client?['name'],
          'cedula':
              _firstText(item, ['cedula', 'document']) ?? client?['document'],
          'clientPhone':
              _firstText(item, ['clientPhone', 'phone']) ?? client?['phone'],
          'clientAddress':
              _firstText(item, ['clientAddress', 'address']) ??
              client?['address'],
          'lot': _firstText(item, ['lot']) ?? lot?['display'],
          'seller': _firstText(item, ['seller']) ?? seller?['name'],
          'status': _firstText(item, ['status', 'estado']),
          'saleDate': _firstText(item, [
            'saleDate',
            'sale_date',
            'fecha_venta',
          ]),
          'total': _firstValue(item, ['total', 'sale_price', 'precio_venta']),
          'initialPaid': _firstValue(item, [
            'initialPaid',
            'paid_initial_payment',
            'inicial',
          ]),
          'balance': _firstValue(item, ['balance', 'saldo_pendiente']),
          'updatedAt': _firstText(item, ['updatedAt', 'updated_at']),
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _normalizeInstallments(
  List<Map<String, dynamic>> items, {
  required List<Map<String, dynamic>> sales,
}) {
  final salesBySyncId = _bySyncId(sales);
  return items
      .map((item) {
        final saleSyncId = _firstText(item, ['saleSyncId', 'sale_sync_id']);
        final sale = salesBySyncId[saleSyncId];
        return {
          ...item,
          'syncId': _firstText(item, ['syncId', 'sync_id']),
          'saleSyncId': saleSyncId,
          'saleId': sale?['saleId'] ?? sale?['syncId'],
          'client': sale?['client'],
          'lot': sale?['lot'],
          'installmentNumber': _firstValue(item, [
            'installmentNumber',
            'installment_number',
          ]),
          'dueDate': _firstText(item, ['dueDate', 'due_date']),
          'totalAmount': _firstValue(item, ['totalAmount', 'total_amount']),
          'paidAmount': _firstValue(item, ['paidAmount', 'paid_amount']),
          'endingBalance': _firstValue(item, [
            'endingBalance',
            'ending_balance',
          ]),
          'status': _firstText(item, ['status', 'estado']),
          'updatedAt': _firstText(item, ['updatedAt', 'updated_at']),
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _normalizePayments(
  List<Map<String, dynamic>> items, {
  required List<Map<String, dynamic>> clients,
  required List<Map<String, dynamic>> sales,
  required List<Map<String, dynamic>> installments,
}) {
  final clientsBySyncId = _bySyncId(clients);
  final salesBySyncId = _bySyncId(sales);
  final installmentsBySyncId = _bySyncId(installments);
  return items
      .map((item) {
        final saleSyncId = _firstText(item, ['saleSyncId', 'sale_sync_id']);
        final clientSyncId = _firstText(item, [
          'clientSyncId',
          'client_sync_id',
        ]);
        final installmentSyncId = _firstText(item, [
          'installmentSyncId',
          'installment_sync_id',
        ]);
        final sale = salesBySyncId[saleSyncId];
        final client = clientsBySyncId[clientSyncId];
        final installment = installmentsBySyncId[installmentSyncId];
        return {
          ...item,
          'syncId': _firstText(item, ['syncId', 'sync_id']),
          'saleSyncId': saleSyncId,
          'clientSyncId': clientSyncId,
          'installmentSyncId': installmentSyncId,
          'client': sale?['client'] ?? client?['name'],
          'lot': sale?['lot'],
          'installmentNumber': installment?['installmentNumber'],
          'paidAt': _firstText(item, ['paidAt', 'payment_date', 'fecha_pago']),
          'amount': _firstValue(item, [
            'amount',
            'amount_paid',
            'monto_pagado',
          ]),
          'method': _firstText(item, [
            'method',
            'payment_method',
            'metodo_pago',
          ]),
          'paymentType': _firstText(item, ['paymentType', 'payment_type']),
          'reference': _firstText(item, ['reference', 'referencia']),
          'yearToPay': _firstValue(item, ['yearToPay', 'year_to_pay']),
          'updatedAt': _firstText(item, ['updatedAt', 'updated_at']),
        };
      })
      .toList(growable: false);
}

Map<String, Map<String, dynamic>> _bySyncId(List<Map<String, dynamic>> items) {
  return {
    for (final item in items)
      if ((item['syncId']?.toString().trim() ?? '').isNotEmpty)
        item['syncId'].toString(): item,
  };
}

String? _firstText(Map<String, dynamic> item, List<String> keys) {
  final value = _firstValue(item, keys);
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

Object? _firstValue(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isEmpty) continue;
    return value;
  }
  return null;
}

String _lotDisplay(String? block, String? number) {
  final cleanBlock = block?.trim() ?? '';
  final cleanNumber = number?.trim() ?? '';
  if (cleanBlock.isNotEmpty && cleanNumber.isNotEmpty) {
    return 'M$cleanBlock-S$cleanNumber';
  }
  if (cleanNumber.isNotEmpty) return 'Solar $cleanNumber';
  if (cleanBlock.isNotEmpty) return 'Manzana $cleanBlock';
  return '-';
}
