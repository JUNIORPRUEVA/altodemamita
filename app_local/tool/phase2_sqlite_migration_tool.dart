import 'dart:io';

import 'package:sistema_solares/core/cloud_foundation/sqlite_migration_tool.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/phase2_sqlite_migration_tool.dart <sqlite-copy-path> [output-dir]\n'
      '       dart run tool/phase2_sqlite_migration_tool.dart --create-synthetic <sqlite-path> [output-dir]',
    );
    exitCode = 64;
    return;
  }

  final tool = SqliteMigrationTool();
  if (args.first == '--create-synthetic') {
    if (args.length < 2) {
      stderr.writeln('Missing synthetic SQLite output path.');
      exitCode = 64;
      return;
    }
    final summary = await tool.createSyntheticDatabase(args[1]);
    stdout.writeln('Synthetic database: ${summary.path}');
    for (final entry in summary.counts.entries) {
      stdout.writeln('${entry.key}: ${entry.value}');
    }
    if (args.length > 2) {
      final report = await tool.inspect(args[1]);
      await tool.writeReports(report: report, outputDirectory: args[2]);
    }
    return;
  }

  final report = await tool.inspect(args[0]);
  if (args.length > 1) {
    await tool.writeReports(report: report, outputDirectory: args[1]);
  }
  stdout.writeln(report.toMarkdown());
  if (!report.passed) {
    exitCode = 2;
  }
}
