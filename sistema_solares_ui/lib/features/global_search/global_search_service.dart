import 'package:sistema_solares_ui/core/network/api_client.dart';

class GlobalSearchSummary {
  GlobalSearchSummary({
    required this.client,
    required this.sales,
    required this.matchTypes,
  });

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> sales;
  final Set<String> matchTypes;

  String get clientId => client['id']?.toString() ?? '';
}

class GlobalSearchDetail {
  GlobalSearchDetail({
    required this.client,
    required this.sales,
  });

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> sales;
}

class GlobalSearchService {
  GlobalSearchService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<GlobalSearchSummary>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const <GlobalSearchSummary>[];
    }

    final results = await Future.wait<dynamic>([
      _apiClient.get(
        '/clients',
        queryParameters: {
          'search': query,
          'page': '1',
          'limit': '12',
        },
      ),
      _apiClient.get(
        '/sales',
        queryParameters: {
          'search': query,
          'page': '1',
          'limit': '30',
        },
      ),
    ]);

    final clientsResponse = _asMap(results[0]);
    final salesResponse = _asMap(results[1]);
    final clientItems = _asList(clientsResponse['items']);
    final matchedSales = _asList(salesResponse['items']);

    final candidateClientIds = <String>[];
    final matchTypesByClient = <String, Set<String>>{};

    for (final client in clientItems) {
      final clientId = client['id']?.toString() ?? '';
      if (clientId.isEmpty) {
        continue;
      }
      if (!candidateClientIds.contains(clientId)) {
        candidateClientIds.add(clientId);
      }
      matchTypesByClient.putIfAbsent(clientId, () => <String>{}).add('client');
    }

    for (final sale in matchedSales) {
      final client = _asMap(sale['client']);
      final clientId = client['id']?.toString() ?? '';
      if (clientId.isEmpty) {
        continue;
      }
      if (!candidateClientIds.contains(clientId)) {
        candidateClientIds.add(clientId);
      }
      matchTypesByClient.putIfAbsent(clientId, () => <String>{}).add('sale');
    }

    if (candidateClientIds.isEmpty) {
      return const <GlobalSearchSummary>[];
    }

    final bundles = await Future.wait(
      candidateClientIds.map((clientId) => _buildSummary(clientId)),
    );

    final summaries = <GlobalSearchSummary>[];
    for (var index = 0; index < bundles.length; index++) {
      final bundle = bundles[index];
      if (bundle == null) {
        continue;
      }
      final clientId = bundle.client['id']?.toString() ?? candidateClientIds[index];
      summaries.add(
        GlobalSearchSummary(
          client: bundle.client,
          sales: bundle.sales,
          matchTypes: matchTypesByClient[clientId] ?? <String>{'client'},
        ),
      );
    }

    summaries.sort((left, right) {
      final bySales = right.sales.length.compareTo(left.sales.length);
      if (bySales != 0) {
        return bySales;
      }
      return _fullName(left.client).compareTo(_fullName(right.client));
    });
    return summaries;
  }

  Future<GlobalSearchDetail> fetchDetail(String clientId) async {
    final summary = await _buildSummary(clientId, includeDeepSales: true);
    if (summary == null) {
      throw ApiException('No se pudo cargar el detalle del cliente.');
    }

    return GlobalSearchDetail(client: summary.client, sales: summary.sales);
  }

  Future<_ClientSearchBundle?> _buildSummary(
    String clientId, {
    bool includeDeepSales = false,
  }) async {
    if (clientId.trim().isEmpty) {
      return null;
    }

    final results = await Future.wait<dynamic>([
      _apiClient.get('/clients/$clientId'),
      _apiClient.get(
        '/sales',
        queryParameters: {
          'clientId': clientId,
          'page': '1',
          'limit': includeDeepSales ? '100' : '20',
        },
      ),
    ]);

    final client = _asMap(results[0]);
    final salesList = _asList(_asMap(results[1])['items']);

    if (!includeDeepSales || salesList.isEmpty) {
      return _ClientSearchBundle(client: client, sales: salesList);
    }

    final detailedSales = await Future.wait(
      salesList.map((sale) async {
        final saleId = sale['id']?.toString() ?? '';
        if (saleId.isEmpty) {
          return sale;
        }
        return _asMap(await _apiClient.get('/sales/$saleId'));
      }),
    );

    return _ClientSearchBundle(client: client, sales: detailedSales);
  }

  static List<Map<String, dynamic>> _asList(Object? value) {
    return (value as List<dynamic>? ?? const <dynamic>[]).map(_asMap).toList();
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  static String _fullName(Map<String, dynamic> client) {
    final firstName = client['firstName']?.toString() ?? '';
    final lastName = client['lastName']?.toString() ?? '';
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'Sin nombre' : name;
  }
}

class _ClientSearchBundle {
  _ClientSearchBundle({required this.client, required this.sales});

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> sales;
}
