import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_ui/features/reports/reports_service.dart';

void main() {
  group('ReportsService.buildUtcRangeQuery', () {
    test('uses UTC ISO-8601 timestamps (ends with Z)', () {
      final fromLocal = DateTime(2026, 4, 23, 0, 0, 0, 0);
      final toLocal = DateTime(2026, 4, 23, 23, 59, 59, 999);

      final query = ReportsService.buildUtcRangeQuery(
        from: fromLocal,
        to: toLocal,
      );

      expect(query['from'], fromLocal.toUtc().toIso8601String());
      expect(query['to'], toLocal.toUtc().toIso8601String());
      expect(query['from']!.endsWith('Z'), isTrue);
      expect(query['to']!.endsWith('Z'), isTrue);
    });
  });
}
