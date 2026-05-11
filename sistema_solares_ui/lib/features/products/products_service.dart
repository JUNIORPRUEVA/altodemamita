import 'package:sistema_solares_ui/core/network/api_client.dart';

class ProductsPage {
  ProductsPage({required this.items, required this.total});

  final List<Map<String, dynamic>> items;
  final int total;
}

class ProductsService {
  ProductsService(this._apiClient);

  final ApiClient _apiClient;

  Future<ProductsPage> fetch({
    String search = '',
    int page = 1,
    bool includeInactive = true,
    bool includeDeleted = false,
  }) async {
    // CONSISTENCY_LOCKDOWN: panel must never request soft-deleted products.
    final effectiveIncludeDeleted = false;
    final response = await _apiClient.get(
      '/products',
      queryParameters: {
        'page': '$page',
        'limit': '20',
        'search': search,
        'includeInactive': '$includeInactive',
        'includeDeleted': '$effectiveIncludeDeleted',
      },
    ) as Map<String, dynamic>;

    final items = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => (item as Map<dynamic, dynamic>).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();

    final meta = response['meta'] as Map<String, dynamic>? ?? const {};
    return ProductsPage(items: items, total: meta['total'] as int? ?? items.length);
  }
}
