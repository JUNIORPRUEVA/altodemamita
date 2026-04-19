import 'package:sistema_solares_ui/core/network/api_client.dart';

class ClientsPage {
  ClientsPage({
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

  int get visibleFrom => total == 0 ? 0 : ((page - 1) * limit) + 1;

  int get visibleTo {
    if (total == 0) {
      return 0;
    }
    final lastVisible = ((page - 1) * limit) + items.length;
    return lastVisible > total ? total : lastVisible;
  }

  bool get hasPreviousPage => page > 1;

  bool get hasNextPage => page < totalPages;
}

class ClientsService {
  ClientsService(this._apiClient);

  final ApiClient _apiClient;

  Future<ClientsPage> fetch({String search = '', int page = 1}) async {
    final response = await _apiClient.get(
      '/clients',
      queryParameters: {
        'page': '$page',
        'limit': '20',
        'search': search,
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
    final total = meta['total'] as int? ?? items.length;
    final resolvedPage = meta['page'] as int? ?? page;
    final limit = meta['limit'] as int? ?? 20;
    final totalPages = meta['totalPages'] as int? ??
        (total == 0 ? 1 : ((total + limit - 1) ~/ limit));

    return ClientsPage(
      items: items,
      total: total,
      page: resolvedPage,
      limit: limit,
      totalPages: totalPages,
    );
  }
}