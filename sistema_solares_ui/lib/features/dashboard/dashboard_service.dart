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

    final summary = await _apiClient.get('/reports/summary') as Map<String, dynamic>;
    final sales = await _apiClient.get(
      '/reports/sales',
      queryParameters: {'from': from, 'to': now.toIso8601String()},
    ) as List<dynamic>;
    final payments = await _apiClient.get(
      '/reports/payments',
      queryParameters: {'from': from, 'to': now.toIso8601String()},
    ) as List<dynamic>;

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