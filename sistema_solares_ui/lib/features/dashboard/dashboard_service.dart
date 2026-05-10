import 'package:sistema_solares_ui/core/network/api_client.dart';

class DashboardSnapshot {
  DashboardSnapshot({
    required this.summary,
    required this.recentSales,
    required this.recentPayments,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> recentSales;
  final List<Map<String, dynamic>> recentPayments;
}

class DashboardService {
  DashboardService(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardSnapshot> fetchSnapshot() async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30)).toIso8601String();

    final results = await Future.wait<dynamic>([
      _apiClient.get('/reports/summary'),
      _apiClient.get(
        '/reports/sales',
        queryParameters: {'from': from, 'to': now.toIso8601String()},
      ),
      _apiClient.get(
        '/reports/payments',
        queryParameters: {'from': from, 'to': now.toIso8601String()},
      ),
      _apiClient.get(
        '/clients',
        queryParameters: {'page': '1', 'limit': '1'},
      ),
    ]);

    final summary = Map<String, dynamic>.from(results[0] as Map<String, dynamic>);
    final sales = results[1] as List<dynamic>;
    final payments = results[2] as List<dynamic>;
    final clientsPage = results[3] as Map<String, dynamic>;
    final clientsMeta = clientsPage['meta'] as Map<String, dynamic>? ?? const {};
    summary['clients'] = clientsMeta['total'] as int? ?? summary['clients'];

    return DashboardSnapshot(
      summary: summary,
      recentSales: sales.take(5).map(_asMap).toList(),
      recentPayments: payments.take(5).map(_asMap).toList(),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return (value as Map<dynamic, dynamic>).map(
      (key, val) => MapEntry(key.toString(), val),
    );
  }
}
