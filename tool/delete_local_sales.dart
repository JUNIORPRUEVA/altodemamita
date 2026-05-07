import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);
  if (parsed.showHelp) {
    _printUsage();
    return;
  }

  final appDatabase = AppDatabase.instance;
  final db = await appDatabase.database;

  try {
    if (parsed.listOnly) {
      final allSales = await _loadAllSales(db);
      if (allSales.isEmpty) {
        stdout.writeln('No hay ventas locales.');
        return;
      }
      stdout.writeln('Ventas locales actuales: ${allSales.length}');
      for (final sale in allSales) {
        stdout.writeln(
          '  - id=${sale['id']} sync_id=${sale['sync_id']} cliente_id=${sale['cliente_id']} estado=${sale['estado']}',
        );
      }
      return;
    }

    List<Map<String, Object?>> targetSales;
    if (parsed.keepSaleIds.isNotEmpty || parsed.keepSaleSyncIds.isNotEmpty) {
      targetSales = await _loadSalesToDeleteKeeping(
        db,
        keepSaleIds: parsed.keepSaleIds,
        keepSaleSyncIds: parsed.keepSaleSyncIds,
      );
    } else {
      if (parsed.saleIds.isEmpty && parsed.saleSyncIds.isEmpty) {
        stderr.writeln(
          'Error: debes indicar --sale-id/--sync-id o usar --keep-sale-id/--keep-sync-id.',
        );
        _printUsage();
        exitCode = 2;
        return;
      }
      targetSales = await _loadTargetSales(
        db,
        saleIds: parsed.saleIds,
        saleSyncIds: parsed.saleSyncIds,
      );
    }

    if (targetSales.isEmpty) {
      stdout.writeln('No se encontraron ventas con esos filtros.');
      return;
    }

    final saleIds = targetSales.map((row) => row['id'] as int).toSet();
    final saleSyncIds = targetSales
        .map((row) => (row['sync_id'] as String? ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    final installmentRows = await _queryRowsBySaleIds(
      db,
      table: DatabaseSchema.installmentsTable,
      saleIds: saleIds,
    );
    final paymentRows = await _queryRowsBySaleIds(
      db,
      table: DatabaseSchema.paymentsTable,
      saleIds: saleIds,
    );

    final installmentSyncIds = installmentRows
        .map((row) => (row['sync_id'] as String? ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final paymentSyncIds = paymentRows
        .map((row) => (row['sync_id'] as String? ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    stdout.writeln('--- RESUMEN ---');
    stdout.writeln('Ventas objetivo: ${saleIds.length}');
    for (final sale in targetSales) {
      stdout.writeln(
        '  - id=${sale['id']} sync_id=${sale['sync_id']} cliente_id=${sale['cliente_id']} estado=${sale['estado']}',
      );
    }
    stdout.writeln('Cuotas relacionadas: ${installmentRows.length}');
    stdout.writeln('Pagos relacionados: ${paymentRows.length}');
    stdout.writeln('Queue sales ids: ${saleSyncIds.length}');
    stdout.writeln('Queue installments ids: ${installmentSyncIds.length}');
    stdout.writeln('Queue payments ids: ${paymentSyncIds.length}');

    if (!parsed.apply) {
      stdout.writeln('');
      stdout.writeln('Modo simulacion. No se aplicaron cambios.');
      stdout.writeln(
        'Ejecuta con --apply para borrar realmente y con backup automatico.',
      );
      return;
    }

    final backupPath = await _createSqliteBackup(db, appDatabase);
    stdout.writeln('Backup creado en: $backupPath');

    await db.transaction((txn) async {
      if (paymentRows.isNotEmpty) {
        await _deleteByIds(
          txn,
          table: DatabaseSchema.paymentsTable,
          idColumn: 'id',
          ids: paymentRows.map((row) => row['id'] as int).toSet(),
        );
      }

      if (installmentRows.isNotEmpty) {
        await _deleteByIds(
          txn,
          table: DatabaseSchema.installmentsTable,
          idColumn: 'id',
          ids: installmentRows.map((row) => row['id'] as int).toSet(),
        );
      }

      if (saleSyncIds.isNotEmpty) {
        await _deleteSyncQueueByScopeAndRecordIds(
          txn,
          scope: 'sales',
          recordSyncIds: saleSyncIds,
        );
        await _deleteConflictLogsByScopeAndRecordIds(
          txn,
          scope: 'sales',
          recordSyncIds: saleSyncIds,
        );
      }

      if (installmentSyncIds.isNotEmpty) {
        await _deleteSyncQueueByScopeAndRecordIds(
          txn,
          scope: 'installments',
          recordSyncIds: installmentSyncIds,
        );
        await _deleteConflictLogsByScopeAndRecordIds(
          txn,
          scope: 'installments',
          recordSyncIds: installmentSyncIds,
        );
      }

      if (paymentSyncIds.isNotEmpty) {
        await _deleteSyncQueueByScopeAndRecordIds(
          txn,
          scope: 'payments',
          recordSyncIds: paymentSyncIds,
        );
        await _deleteConflictLogsByScopeAndRecordIds(
          txn,
          scope: 'payments',
          recordSyncIds: paymentSyncIds,
        );
      }

      await _deleteByIds(
        txn,
        table: DatabaseSchema.salesTable,
        idColumn: 'id',
        ids: saleIds,
      );
    });

    final configRepository = SyncConfigRepository();
    await configRepository.clearCursors(const [
      'clients',
      'sellers',
      'products',
      'sales',
      'installments',
      'payments',
    ]);

    stdout.writeln('Borrado completado.');
    stdout.writeln('Cursores de sync limpiados para forzar descarga completa.');
    stdout.writeln(
      'Siguiente paso: abre la app y ejecuta Configuracion > Reparar sincronizacion.',
    );
  } finally {
    await appDatabase.close();
  }
}

class _ParsedArgs {
  _ParsedArgs({
    required this.apply,
    required this.showHelp,
    required this.listOnly,
    required this.saleIds,
    required this.saleSyncIds,
    required this.keepSaleIds,
    required this.keepSaleSyncIds,
  });

  final bool apply;
  final bool showHelp;
  final bool listOnly;
  final Set<int> saleIds;
  final Set<String> saleSyncIds;
  final Set<int> keepSaleIds;
  final Set<String> keepSaleSyncIds;
}

_ParsedArgs _parseArgs(List<String> args) {
  var apply = false;
  var showHelp = false;
  var listOnly = false;
  final saleIds = <int>{};
  final saleSyncIds = <String>{};
  final keepSaleIds = <int>{};
  final keepSaleSyncIds = <String>{};

  for (var i = 0; i < args.length; i++) {
    final arg = args[i].trim();
    if (arg.isEmpty) {
      continue;
    }

    if (arg == '--apply') {
      apply = true;
      continue;
    }
    if (arg == '--help' || arg == '-h') {
      showHelp = true;
      continue;
    }
    if (arg == '--list') {
      listOnly = true;
      continue;
    }

    if (arg.startsWith('--sale-id=')) {
      final raw = arg.substring('--sale-id='.length);
      _parseIntCsv(raw, saleIds);
      continue;
    }
    if (arg == '--sale-id' && i + 1 < args.length) {
      _parseIntCsv(args[++i], saleIds);
      continue;
    }

    if (arg.startsWith('--sync-id=')) {
      final raw = arg.substring('--sync-id='.length);
      _parseStringCsv(raw, saleSyncIds);
      continue;
    }
    if (arg == '--sync-id' && i + 1 < args.length) {
      _parseStringCsv(args[++i], saleSyncIds);
      continue;
    }

    if (arg.startsWith('--keep-sale-id=')) {
      final raw = arg.substring('--keep-sale-id='.length);
      _parseIntCsv(raw, keepSaleIds);
      continue;
    }
    if (arg == '--keep-sale-id' && i + 1 < args.length) {
      _parseIntCsv(args[++i], keepSaleIds);
      continue;
    }

    if (arg.startsWith('--keep-sync-id=')) {
      final raw = arg.substring('--keep-sync-id='.length);
      _parseStringCsv(raw, keepSaleSyncIds);
      continue;
    }
    if (arg == '--keep-sync-id' && i + 1 < args.length) {
      _parseStringCsv(args[++i], keepSaleSyncIds);
      continue;
    }
  }

  return _ParsedArgs(
    apply: apply,
    showHelp: showHelp,
    listOnly: listOnly,
    saleIds: saleIds,
    saleSyncIds: saleSyncIds,
    keepSaleIds: keepSaleIds,
    keepSaleSyncIds: keepSaleSyncIds,
  );
}

void _parseIntCsv(String raw, Set<int> output) {
  for (final part in raw.split(',')) {
    final value = int.tryParse(part.trim());
    if (value != null) {
      output.add(value);
    }
  }
}

void _parseStringCsv(String raw, Set<String> output) {
  for (final part in raw.split(',')) {
    final value = part.trim();
    if (value.isNotEmpty) {
      output.add(value);
    }
  }
}

void _printUsage() {
  stdout.writeln('Uso:');
  stdout.writeln('  dart run tool/delete_local_sales.dart --list');
  stdout.writeln('  dart run tool/delete_local_sales.dart --sale-id 12,15');
  stdout.writeln(
    '  dart run tool/delete_local_sales.dart --sync-id sale_abc,sale_xyz',
  );
  stdout.writeln(
    '  dart run tool/delete_local_sales.dart --sale-id 12 --sync-id sale_abc --apply',
  );
  stdout.writeln(
    '  dart run tool/delete_local_sales.dart --keep-sale-id 12 --apply',
  );
  stdout.writeln(
    '  dart run tool/delete_local_sales.dart --keep-sync-id sale_abc --apply',
  );
  stdout.writeln('');
  stdout.writeln('Notas:');
  stdout.writeln('  - Sin --apply solo simula (no borra).');
  stdout.writeln('  - Con --apply crea backup antes de borrar.');
  stdout.writeln(
    '  - --keep-sale-id/--keep-sync-id borra TODO excepto la(s) venta(s) indicada(s).',
  );
}

Future<List<Map<String, Object?>>> _loadAllSales(dynamic db) {
  return db.query(
    DatabaseSchema.salesTable,
    columns: ['id', 'sync_id', 'cliente_id', 'estado'],
    orderBy: 'id ASC',
  );
}

Future<List<Map<String, Object?>>> _loadTargetSales(
  dynamic db, {
  required Set<int> saleIds,
  required Set<String> saleSyncIds,
}) async {
  final filters = <String>[];
  final args = <Object?>[];

  if (saleIds.isNotEmpty) {
    filters.add('id IN (${List.filled(saleIds.length, '?').join(',')})');
    args.addAll(saleIds);
  }
  if (saleSyncIds.isNotEmpty) {
    filters.add(
      'sync_id IN (${List.filled(saleSyncIds.length, '?').join(',')})',
    );
    args.addAll(saleSyncIds);
  }

  final whereClause = filters.join(' OR ');
  return db.query(
    DatabaseSchema.salesTable,
    columns: ['id', 'sync_id', 'cliente_id', 'estado'],
    where: whereClause,
    whereArgs: args,
  );
}

Future<List<Map<String, Object?>>> _loadSalesToDeleteKeeping(
  dynamic db, {
  required Set<int> keepSaleIds,
  required Set<String> keepSaleSyncIds,
}) async {
  final exclusions = <String>[];
  final args = <Object?>[];

  if (keepSaleIds.isNotEmpty) {
    exclusions.add(
      'id NOT IN (${List.filled(keepSaleIds.length, '?').join(',')})',
    );
    args.addAll(keepSaleIds);
  }
  if (keepSaleSyncIds.isNotEmpty) {
    exclusions.add(
      'sync_id NOT IN (${List.filled(keepSaleSyncIds.length, '?').join(',')})',
    );
    args.addAll(keepSaleSyncIds);
  }

  if (exclusions.isEmpty) {
    return const [];
  }

  final whereClause = exclusions.join(' AND ');
  return db.query(
    DatabaseSchema.salesTable,
    columns: ['id', 'sync_id', 'cliente_id', 'estado'],
    where: whereClause,
    whereArgs: args,
    orderBy: 'id ASC',
  );
}

Future<List<Map<String, Object?>>> _queryRowsBySaleIds(
  dynamic db, {
  required String table,
  required Set<int> saleIds,
}) async {
  if (saleIds.isEmpty) {
    return const [];
  }

  final placeholders = List.filled(saleIds.length, '?').join(',');
  return db.query(
    table,
    columns: ['id', 'sync_id'],
    where: 'venta_id IN ($placeholders)',
    whereArgs: saleIds.toList(growable: false),
  );
}

Future<void> _deleteByIds(
  dynamic txn, {
  required String table,
  required String idColumn,
  required Set<int> ids,
}) async {
  if (ids.isEmpty) {
    return;
  }

  final placeholders = List.filled(ids.length, '?').join(',');
  await txn.rawDelete(
    'DELETE FROM $table WHERE $idColumn IN ($placeholders)',
    ids.toList(growable: false),
  );
}

Future<void> _deleteSyncQueueByScopeAndRecordIds(
  dynamic txn, {
  required String scope,
  required Set<String> recordSyncIds,
}) async {
  if (recordSyncIds.isEmpty) {
    return;
  }

  final placeholders = List.filled(recordSyncIds.length, '?').join(',');
  await txn.rawDelete(
    'DELETE FROM ${DatabaseSchema.syncQueueTable} '
    'WHERE scope = ? AND record_sync_id IN ($placeholders)',
    [scope, ...recordSyncIds],
  );
}

Future<void> _deleteConflictLogsByScopeAndRecordIds(
  dynamic txn, {
  required String scope,
  required Set<String> recordSyncIds,
}) async {
  if (recordSyncIds.isEmpty) {
    return;
  }

  final placeholders = List.filled(recordSyncIds.length, '?').join(',');
  await txn.rawDelete(
    'DELETE FROM ${DatabaseSchema.conflictLogsTable} '
    'WHERE scope = ? AND record_sync_id IN ($placeholders)',
    [scope, ...recordSyncIds],
  );
}

Future<String> _createSqliteBackup(dynamic db, AppDatabase appDatabase) async {
  final dbPath = await appDatabase.databasePath;
  final now = DateTime.now();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';

  final backupPath = path.join(
    path.dirname(dbPath),
    'sistema_solares_pre_delete_sales_$stamp.db',
  );

  final escapedPath = backupPath.replaceAll("'", "''");
  await db.execute("VACUUM INTO '$escapedPath'");
  return backupPath;
}
