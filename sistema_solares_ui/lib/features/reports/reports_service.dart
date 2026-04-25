import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:flutter/foundation.dart';

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

  Future<ReportsBundle> fetchBundle({
    required DateTime from,
    required DateTime to,
  }) async {
    final query = _buildRangeQuery(from: from, to: to);

    final sales =
        await _apiClient.get('/reports/sales', queryParameters: query)
            as List<dynamic>;
    final payments =
        await _apiClient.get('/reports/payments', queryParameters: query)
            as List<dynamic>;
    final delinquency =
        await _apiClient.get('/reports/delinquency', queryParameters: query)
            as List<dynamic>;

    return ReportsBundle(
      sales: sales.map(_asMap).toList(),
      payments: payments.map(_asMap).toList(),
      delinquency: delinquency.map(_asMap).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> fetchPayments({
    required DateTime from,
    required DateTime to,
  }) async {
    final payments =
        await _apiClient.get(
              '/reports/payments',
              queryParameters: _buildRangeQuery(from: from, to: to),
            )
            as List<dynamic>;

    return payments.map(_asMap).toList();
  }

  @visibleForTesting
  static Map<String, String> buildUtcRangeQuery({
    required DateTime from,
    required DateTime to,
  }) {
    return {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    };
  }

  Map<String, String> _buildRangeQuery({
    required DateTime from,
    required DateTime to,
  }) {
    return buildUtcRangeQuery(from: from, to: to);
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
}
