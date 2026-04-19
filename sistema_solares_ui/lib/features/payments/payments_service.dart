import 'package:sistema_solares_ui/core/network/api_client.dart';

class PaymentsPageData {
  PaymentsPageData({
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

class PaymentsService {
  PaymentsService(this._apiClient);

  final ApiClient _apiClient;

  Future<PaymentsPageData> fetch({
    String? search,
    int page = 1,
    int limit = 30,
  }) async {
    final response =
        await _apiClient.get(
              '/payments',
              queryParameters: {
                'page': '$page',
                'limit': '$limit',
                if (search != null && search.trim().isNotEmpty)
                  'search': search.trim(),
              },
            )
            as Map<String, dynamic>;

    final items = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(_asMap)
        .toList();
    final meta = _asMap(response['meta'] ?? const <String, dynamic>{});

    return PaymentsPageData(
      items: items,
      total: _asInt(meta['total']),
      page: _asInt(meta['page'], fallback: page),
      limit: _asInt(meta['limit'], fallback: limit),
      totalPages: _resolveTotalPages(meta['totalPages'], total: _asInt(meta['total']), limit: limit),
    );
  }

  Future<Map<String, dynamic>> fetchDetail(String id) async {
    final response =
        await _apiClient.get('/payments/$id') as Map<dynamic, dynamic>;
    return _asMap(response);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return (value as Map<dynamic, dynamic>).map(
      (key, val) => MapEntry(key.toString(), _normalize(val)),
    );
  }

  Object? _normalize(dynamic value) {
    if (value is Map<dynamic, dynamic>) {
      return _asMap(value);
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
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

  int _resolveTotalPages(Object? value, {required int total, required int limit}) {
    final parsed = _asInt(value);
    if (parsed > 0) {
      return parsed;
    }
    if (total <= 0) {
      return 1;
    }
    final safeLimit = limit <= 0 ? 1 : limit;
    return (total / safeLimit).ceil();
  }
}
