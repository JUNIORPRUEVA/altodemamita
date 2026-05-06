import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';
import 'package:sqflite_common/sqlite_api.dart';

const _targetScopes = ['products', 'sales', 'installments', 'payments'];
const _applyOrder = ['products', 'sales', 'installments', 'payments'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final startedAt = DateTime.now();
  final timestamp = _timestamp(startedAt);
  final workspaceRoot = Directory.current.path;
  final reportDir = Directory(path.join(workspaceRoot, 'backups', 'phase6_1'));
  await reportDir.create(recursive: true);

  final appDatabase = AppDatabase.instance;
  final configRepository = SyncConfigRepository();
  final syncQueueService = SyncQueueService.instance;
  final apiClient = SyncApiClient();
  final syncService = SyncService(
    repositories: [
      ClientRepository(
        appDatabase: appDatabase,
        syncQueueService: syncQueueService,
      ),
      ProductsSyncRepository(appDatabase: appDatabase),
      SellerRepository(
        database: appDatabase,
        syncQueueService: syncQueueService,
      ),
      SalesSyncRepository(appDatabase: appDatabase),
      InstallmentsSyncRepository(appDatabase: appDatabase),
      PaymentsSyncRepository(appDatabase: appDatabase),
    ],
    configRepository: configRepository,
    apiClient: apiClient,
    syncQueueService: syncQueueService,
    appDatabase: appDatabase,
  );

  final dbPath = await appDatabase.databasePath;
  await appDatabase.close();
  final sqliteBackupPath = path.join(
    reportDir.path,
    'sqlite_before_phase6_1_$timestamp.db',
  );
  await File(dbPath).copy(sqliteBackupPath);

  await appDatabase.initialize();
  final settings = await configRepository.loadSettings();
  if (!settings.isConfigured) {
    stderr.writeln('missing sync settings or jwt');
    exitCode = 2;
    return;
  }

  final epoch = DateTime.utc(1970, 1, 1);
  final remoteSnapshot = await apiClient.downloadChanges(
    settings: settings,
    updatedSinceByScope: {
      for (final scope in _targetScopes) scope: epoch,
    },
  );

  final remoteSnapshotPath = path.join(
    reportDir.path,
    'backend_snapshot_phase6_1_$timestamp.json',
  );
  await File(remoteSnapshotPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'server_time': remoteSnapshot.serverTime?.toIso8601String(),
      'scope_cursors': {
        for (final entry in remoteSnapshot.scopeCursors.entries)
          entry.key: entry.value?.toIso8601String(),
      },
      'records': remoteSnapshot.recordsByScope,
    }),
  );

  final db = await appDatabase.database;
  final before = await _buildPhaseReport(
    db: db,
    remoteRecordsByScope: remoteSnapshot.recordsByScope,
  );

  var appliedRecords = 0;
  var retryScopes = <String>{};
  final retryDetails = <Map<String, Object?>>[];
  for (final scope in _applyOrder) {
    final scopeRecords = remoteSnapshot.recordsForScope(scope);
    try {
      appliedRecords += await syncService.applyRemoteScopeRecords(
        scope: scope,
        records: scopeRecords,
        cursor: remoteSnapshot.cursorForScope(scope),
      );
    } catch (error) {
      if (error is RemoteSyncDependencyException) {
        retryScopes.add(scope);
        retryScopes.addAll(error.missingScopes.intersection(_targetScopes.toSet()));
        retryDetails.add({
          'scope': scope,
          'record_sync_id': error.recordSyncId,
          'missing_scopes': error.missingScopes.toList(),
          'message': error.message,
        });
        continue;
      }
      rethrow;
    }
  }

  if (retryScopes.isNotEmpty) {
    for (final scope in _applyOrder.where(retryScopes.contains)) {
      appliedRecords += await syncService.applyRemoteScopeRecords(
        scope: scope,
        records: remoteSnapshot.recordsForScope(scope),
        cursor: remoteSnapshot.cursorForScope(scope),
      );
    }
  }

  final after = await _buildPhaseReport(
    db: db,
    remoteRecordsByScope: remoteSnapshot.recordsByScope,
  );

  final report = {
    'started_at': startedAt.toIso8601String(),
    'finished_at': DateTime.now().toIso8601String(),
    'sqlite_backup': sqliteBackupPath,
    'backend_snapshot': remoteSnapshotPath,
    'since': epoch.toIso8601String(),
    'scopes': _targetScopes,
    'applied_records': appliedRecords,
    'retry_scopes': retryScopes.toList(),
    'retry_details': retryDetails,
    'before': before,
    'after': after,
  };

  final reportPath = path.join(
    reportDir.path,
    'phase6_1_reconcile_report_$timestamp.json',
  );
  await File(reportPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'report_path': reportPath,
      'sqlite_backup': sqliteBackupPath,
      'backend_snapshot': remoteSnapshotPath,
      'applied_records': appliedRecords,
      'before': before,
      'after': after,
      'retry_scopes': retryScopes.toList(),
    }),
  );

  await appDatabase.close();
}

String _timestamp(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  final ss = value.second.toString().padLeft(2, '0');
  return '${y}${m}${d}_$hh$mm$ss';
}

Future<Map<String, Object?>> _buildPhaseReport({
  required Database db,
  required Map<String, List<Map<String, dynamic>>> remoteRecordsByScope,
}) async {
  return {
    'local_summary': await _buildLocalSummary(db),
    'comparison': await _buildComparison(
      db: db,
      remoteRecordsByScope: remoteRecordsByScope,
    ),
  };
}

Future<Map<String, Object?>> _buildLocalSummary(Database db) async {
  return {
    'sync_queue_total': await _count(db, DatabaseSchema.syncQueueTable),
    'sync_queue_failed': await _count(
      db,
      DatabaseSchema.syncQueueTable,
      where: "COALESCE(last_error, '') <> ''",
    ),
    for (final scope in _targetScopes) scope: await _deletedCounts(db, scope),
  };
}

Future<Map<String, Object?>> _buildComparison({
  required Database db,
  required Map<String, List<Map<String, dynamic>>> remoteRecordsByScope,
}) async {
  return {
    for (final scope in _targetScopes)
      scope: await _buildScopeComparison(
        db: db,
        scope: scope,
        remoteRows: remoteRecordsByScope[scope] ?? const <Map<String, dynamic>>[],
      ),
  };
}

Future<Map<String, Object?>> _deletedCounts(Database db, String scope) async {
  final tableName = _tableForScope(scope);
  final localDeleted = await _count(
    db,
    tableName,
    where: 'deleted_at IS NOT NULL',
  );
  final localActive = await _count(
    db,
    tableName,
    where: 'deleted_at IS NULL',
  );
  return {
    'local_active': localActive,
    'local_deleted': localDeleted,
  };
}

Future<Map<String, Object?>> _buildScopeComparison({
  required Database db,
  required String scope,
  required List<Map<String, dynamic>> remoteRows,
}) async {
  final tableName = _tableForScope(scope);
  final localRows = await db.query(
    tableName,
    columns: const ['sync_id', 'deleted_at', 'sync_status'],
  );
  final localBySyncId = {
    for (final row in localRows)
      if (_readString(row['sync_id']) != null) _readString(row['sync_id'])!: row,
  };

  final backendDeleted = remoteRows
      .where((row) => _readString(row['deleted_at']) != null)
      .toList(growable: false);
  final missingDeletedSyncIds = <String>[];
  for (final row in backendDeleted) {
    final syncId = _readString(row['sync_id']);
    if (syncId == null) {
      continue;
    }
    final local = localBySyncId[syncId];
    if (local == null || _readString(local['deleted_at']) == null) {
      missingDeletedSyncIds.add(syncId);
    }
  }

  final localDeleted = localRows
      .where((row) => _readString(row['deleted_at']) != null)
      .length;
  return {
    'local_deleted': localDeleted,
    'backend_deleted': backendDeleted.length,
    'parity_deleted': localDeleted == backendDeleted.length,
    'missing_deleted_sync_ids': missingDeletedSyncIds,
  };
}

String _tableForScope(String scope) {
  return switch (scope) {
    'products' => DatabaseSchema.lotsTable,
    'sales' => DatabaseSchema.salesTable,
    'installments' => DatabaseSchema.installmentsTable,
    'payments' => DatabaseSchema.paymentsTable,
    _ => throw ArgumentError('unsupported scope: $scope'),
  };
}

Future<int> _count(
  Database db,
  String tableName, {
  String? where,
}) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM $tableName${where == null ? '' : ' WHERE $where'}',
  );
  if (rows.isEmpty) {
    return 0;
  }
  final value = rows.first['total'];
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _readString(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty || normalized == 'null') {
    return null;
  }
  return normalized;
}