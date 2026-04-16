import 'package:sistema_solares_ui/core/network/api_client.dart';

class ClientsPage {
  ClientsPage({required this.items, required this.total});

  final List<Map<String, dynamic>> items;
  final int total;
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
    return ClientsPage(items: items, total: meta['total'] as int? ?? items.length);
  }
}