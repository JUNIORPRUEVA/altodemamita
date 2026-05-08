import 'package:sistema_solares_ui/core/network/api_client.dart';

class SalesPageData {
  SalesPageData({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  final List<Map<String, dynamic>> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
}

class SalesService {
  SalesService(this._apiClient);

  final ApiClient _apiClient;

  Future<SalesPageData> fetch({
    String? search,
    int page = 1,
    int limit = 30,
  }) async {
    final response = await _apiClient.get(
      '/sales',
      queryParameters: {
        'page': '$page',
        'limit': '$limit',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    ) as Map<String, dynamic>;

    final items = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(_asMap)
        .toList();
    final meta = _asMap(response['meta'] ?? const <String, dynamic>{});

    return SalesPageData(
      items: items,
      total: _asInt(meta['total']),
      page: _asInt(meta['page'], fallback: page),
      limit: _asInt(meta['limit'], fallback: limit),
      totalPages: _asInt(meta['totalPages'], fallback: 1),
    );
  }

  Future<Map<String, dynamic>> fetchDetail(String id) async {
    final response = await _apiClient.get('/sales/$id') as Map<dynamic, dynamic>;
    return _asMap(response);
  }

  Future<void> forceDeleteFromCloud({
    required String saleId,
    required String adminPassword,
  }) async {
    final normalizedId = saleId.trim();
    final normalizedPassword = adminPassword.trim();
    if (normalizedId.isEmpty) {
      throw ApiException('La venta no tiene un ID valido.');
    }
    if (normalizedPassword.isEmpty) {
      throw ApiException('Debes ingresar la contrasena de administrador.');
    }

    await _apiClient.delete(
      '/sales/force-delete/$normalizedId',
      authorized: false,
      customHeaders: {'x-admin-key': normalizedPassword},
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return (value as Map<dynamic, dynamic>).map(
      (key, val) => MapEntry(key.toString(), val),
    );
  }

  int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}