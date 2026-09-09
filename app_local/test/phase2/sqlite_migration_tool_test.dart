import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/cloud_foundation/sqlite_migration_tool.dart';

void main() {
  test(
    'synthetic SQLite migration report reconciles business payload',
    () async {
      final root = await Directory.systemTemp.createTemp('phase2_migration_');
      addTearDown(() => root.delete(recursive: true));

      final tool = SqliteMigrationTool();
      final dbPath = path.join(root.path, 'synthetic.db');
      final summary = await tool.createSyntheticDatabase(dbPath);
      final report = await tool.inspect(dbPath);

      expect(summary.counts['clientes'], 40);
      expect(summary.counts['ventas'], 20);
      expect(summary.counts['cuotas'], 240);
      expect(summary.counts['pagos'], 20);
      expect(report.passed, isTrue);
      expect(
        report.payload.keys,
        containsAll(SqliteMigrationTool.businessTables),
      );
      expect(report.payload.keys, isNot(contains('sync_queue')));
      expect(
        report.reconciliation.payloadCounts['ventas'],
        report.tableCounts['ventas'],
      );
      expect(report.reconciliation.money['sumSales'], 4000000);
    },
  );
}
