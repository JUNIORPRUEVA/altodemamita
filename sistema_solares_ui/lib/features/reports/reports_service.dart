import 'package:sistema_solares_ui/core/network/api_client.dart';

class ReportsBundle {
  ReportsBundle({
    required this.sales,
    required this.payments,
    required this.delinquency,
  });

  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> delinquency;
}

class ReportsService {
  ReportsService(this._apiClient);

  final ApiClient _apiClient;

  Future<ReportsBundle> fetchBundle({required int days}) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days)).toIso8601String();
    final query = {'from': from, 'to': now.toIso8601String()};

    final sales = await _apiClient.get('/reports/sales', queryParameters: query) as List<dynamic>;
    final payments = await _apiClient.get('/reports/payments', queryParameters: query) as List<dynamic>;
    final delinquency = await _apiClient.get('/reports/delinquency', queryParameters: query) as List<dynamic>;

    return ReportsBundle(
      sales: sales.map(_asMap).toList(),
      payments: payments.map(_asMap).toList(),
      delinquency: delinquency.map(_asMap).toList(),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return (value as Map<dynamic, dynamic>).map(
      (key, val) => MapEntry(key.toString(), val),
    );
  }
}