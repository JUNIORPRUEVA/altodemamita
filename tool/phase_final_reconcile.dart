import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/permissions_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/role_permissions_sync_repository.dart';
import 'package:sistema_solares/repositories/roles_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/repositories/user_roles_sync_repository.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';
import 'package:sqflite_common/sqlite_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final startedAt = DateTime.now();
  final workspaceRoot = Directory.current.path;
  final timestamp = _timestamp(startedAt);
  final reportDir = Directory(path.join(workspaceRoot, 'backups', 'phase_final'));
  await reportDir.create(recursive: true);

  final appDatabase = AppDatabase.instance;
  final syncQueueService = SyncQueueService.instance;
  final configRepository = SyncConfigRepository();
  final apiClient = SyncApiClient();

  stdout.writeln('[PhaseFinal] started_at=${startedAt.toIso8601String()}');

  final dbPath = await appDatabase.databasePath;
  await appDatabase.close();
  final sqliteBackupPath = path.join(
    reportDir.path,
    'sqlite_before_$timestamp.db',
  );
  await File(dbPath).copy(sqliteBackupPath);
  stdout.writeln('[PhaseFinal] sqlite_backup=$sqliteBackupPath');

  await appDatabase.initialize();
  final settings = await configRepository.loadSettings();
  if (!settings.isConfigured) {
    stderr.writeln('[PhaseFinal] missing sync settings or JWT.');
    exitCode = 2;
    return;
  }

  final beforeDb = await appDatabase.database;
  final beforeSummary = await _buildLocalSummary(beforeDb);

  final remoteSnapshot = await apiClient.downloadChanges(settings: settings);
  final remoteSnapshotPath = path.join(
    reportDir.path,
    'backend_snapshot_before_$timestamp.json',
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
  stdout.writeln('[PhaseFinal] backend_snapshot=$remoteSnapshotPath');

  final beforeComparison = await _buildComparison(
    db: beforeDb,
    remoteRecordsByScope: remoteSnapshot.recordsByScope,
  );

  final syncService = SyncService(
    repositories: [
      UsersSyncRepository(appDatabase: appDatabase),
      RolesSyncRepository(appDatabase: appDatabase),
      UserRolesSyncRepository(appDatabase: appDatabase),
      RolePermissionsSyncRepository(appDatabase: appDatabase),
      PermissionsSyncRepository(appDatabase: appDatabase),
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

  final syncReport = await syncService.syncNow(forceFullDownload: true);
  stdout.writeln(
    '[PhaseFinal] sync_report uploaded=${syncReport.uploadedRecords} downloaded=${syncReport.downloadedRecords} pending=${syncReport.pendingRecords} skipped=${syncReport.wasSkipped} connectivity_error=${syncReport.hadConnectivityError} error=${syncReport.errorMessage ?? ''}',
  );

  final afterDb = await appDatabase.database;
  final afterSummary = await _buildLocalSummary(afterDb);
  final afterComparison = await _buildComparison(
    db: afterDb,
    remoteRecordsByScope: remoteSnapshot.recordsByScope,
  );

  final finalReport = {
    'started_at': startedAt.toIso8601String(),
    'finished_at': DateTime.now().toIso8601String(),
    'sqlite_backup': sqliteBackupPath,
    'backend_snapshot': remoteSnapshotPath,
    'sync_report': {
      'uploaded_records': syncReport.uploadedRecords,
      'downloaded_records': syncReport.downloadedRecords,
      'pending_records': syncReport.pendingRecords,
      'was_skipped': syncReport.wasSkipped,
      'had_connectivity_error': syncReport.hadConnectivityError,
      'error_message': syncReport.errorMessage,
      'warnings': syncReport.warnings,
    },
    'before': {
      'local_summary': beforeSummary,
      'comparison': beforeComparison,
    },
    'after': {
      'local_summary': afterSummary,
      'comparison': afterComparison,
    },
  };

  final reportPath = path.join(
    reportDir.path,
    'phase_final_reconcile_report_$timestamp.json',
  );
  await File(reportPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(finalReport),
  );
  stdout.writeln('[PhaseFinal] report=$reportPath');

  await appDatabase.close();
}

String _timestamp(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  final ss = value.second.toString().padLeft(2, '0');
  return '${y}${m}${d}_${hh}${mm}${ss}';
}

Future<Map<String, Object?>> _buildLocalSummary(Database db) async {
  return {
    'sync_queue_total': await _count(db, DatabaseSchema.syncQueueTable),
    'sync_queue_failed': await _count(
      db,
      DatabaseSchema.syncQueueTable,
      where: "COALESCE(last_error, '') <> ''",
    ),
    'clients': await _activeDeletedCounts(db, DatabaseSchema.clientsTable),
    'products': await _activeDeletedCounts(db, DatabaseSchema.lotsTable),
    'sales': await _activeDeletedCounts(db, DatabaseSchema.salesTable),
    'installments': await _activeDeletedCounts(
      db,
      DatabaseSchema.installmentsTable,
    ),
    'payments': await _activeDeletedCounts(db, DatabaseSchema.paymentsTable),
  };
}

Future<Map<String, Object?>> _buildComparison({
  required Database db,
  required Map<String, List<Map<String, dynamic>>> remoteRecordsByScope,
}) async {
  final remoteInstallmentsBySale = _countChildrenByParentSyncId(
    remoteRecordsByScope['installments'] ?? const [],
    'sale_sync_id',
  );
  final remotePaymentsBySale = _countChildrenByParentSyncId(
    remoteRecordsByScope['payments'] ?? const [],
    'sale_sync_id',
  );

  final result = <String, Object?>{};
  for (final scope in _scopeConfigs) {
    final localRows = await _loadLocalRows(db, scope);
    final remoteRows = remoteRecordsByScope[scope.remoteScope] ?? const [];
    result[scope.remoteScope] = _compareScope(
      scope: scope,
      localRows: localRows,
      remoteRows: remoteRows,
      remoteInstallmentsBySale: remoteInstallmentsBySale,
      remotePaymentsBySale: remotePaymentsBySale,
    );
  }
  return result;
}

Map<String, Object?> _compareScope({
  required _ScopeConfig scope,
  required List<Map<String, Object?>> localRows,
  required List<Map<String, dynamic>> remoteRows,
  required Map<String, int> remoteInstallmentsBySale,
  required Map<String, int> remotePaymentsBySale,
}) {
  final localBySyncId = <String, Map<String, Object?>>{
    for (final row in localRows)
      if (_readString(row['sync_id']) != null)
        _readString(row['sync_id'])!: row,
  };
  final remoteBySyncId = <String, Map<String, dynamic>>{
    for (final row in remoteRows)
      if (_readString(row['sync_id']) != null)
        _readString(row['sync_id'])!: row,
  };

  final backendActiveNotInLocal = <Map<String, Object?>>[];
  final backendDeletedNotInLocal = <Map<String, Object?>>[];
  final localDeletedBackendActive = <Map<String, Object?>>[];
  final localActiveNotInBackend = <Map<String, Object?>>[];

  for (final entry in remoteBySyncId.entries) {
    final syncId = entry.key;
    final remoteRow = entry.value;
    final localRow = localBySyncId[syncId];
    final remoteDeleted = _readString(remoteRow['deleted_at']) != null;
    if (localRow == null) {
      final payload = _buildReportRow(
        scope: scope,
        syncId: syncId,
        localRow: null,
        remoteRow: remoteRow,
        remoteInstallmentsBySale: remoteInstallmentsBySale,
        remotePaymentsBySale: remotePaymentsBySale,
      );
      if (remoteDeleted) {
        backendDeletedNotInLocal.add(payload);
      } else {
        backendActiveNotInLocal.add(payload);
      }
      continue;
    }

    final localDeleted = _readString(localRow['deleted_at']) != null;
    if (localDeleted && !remoteDeleted) {
      localDeletedBackendActive.add(
        _buildReportRow(
          scope: scope,
          syncId: syncId,
          localRow: localRow,
          remoteRow: remoteRow,
          remoteInstallmentsBySale: remoteInstallmentsBySale,
          remotePaymentsBySale: remotePaymentsBySale,
        ),
      );
    }
  }

  for (final entry in localBySyncId.entries) {
    final syncId = entry.key;
    final localRow = entry.value;
    final remoteRow = remoteBySyncId[syncId];
    final localDeleted = _readString(localRow['deleted_at']) != null;
    if (!localDeleted && remoteRow == null) {
      localActiveNotInBackend.add(
        _buildReportRow(
          scope: scope,
          syncId: syncId,
          localRow: localRow,
          remoteRow: null,
          remoteInstallmentsBySale: remoteInstallmentsBySale,
          remotePaymentsBySale: remotePaymentsBySale,
        ),
      );
    }
  }

  return {
    'local_active': localRows.where((row) => _readString(row['deleted_at']) == null).length,
    'local_deleted': localRows.where((row) => _readString(row['deleted_at']) != null).length,
    'backend_active': remoteRows.where((row) => _readString(row['deleted_at']) == null).length,
    'backend_deleted': remoteRows.where((row) => _readString(row['deleted_at']) != null).length,
    'backend_active_not_in_local': backendActiveNotInLocal,
    'local_active_not_in_backend': localActiveNotInBackend,
    'backend_deleted_not_in_local': backendDeletedNotInLocal,
    'local_deleted_backend_active': localDeletedBackendActive,
    'local_pending_queue': const <Map<String, Object?>>[],
  };
}

Map<String, Object?> _buildReportRow({
  required _ScopeConfig scope,
  required String syncId,
  required Map<String, Object?>? localRow,
  required Map<String, dynamic>? remoteRow,
  required Map<String, int> remoteInstallmentsBySale,
  required Map<String, int> remotePaymentsBySale,
}) {
  final payload = <String, Object?>{
    'sync_id': syncId,
    'local_deleted_at': _readString(localRow?['deleted_at']),
    'local_sync_status': _readString(localRow?['sync_status']),
    'remote_deleted_at': _readString(remoteRow?['deleted_at']),
    'remote_id': _readString(remoteRow?['id']),
  };

  if (scope.remoteScope == 'sales') {
    payload['remote_installments'] = remoteInstallmentsBySale[syncId] ?? 0;
    payload['remote_payments'] = remotePaymentsBySale[syncId] ?? 0;
  }

  return payload;
}

Map<String, int> _countChildrenByParentSyncId(
  List<Map<String, dynamic>> rows,
  String parentKey,
) {
  final counts = <String, int>{};
  for (final row in rows) {
    final parentSyncId = _readString(row[parentKey]);
    if (parentSyncId == null) {
      continue;
    }
    counts[parentSyncId] = (counts[parentSyncId] ?? 0) + 1;
  }
  return counts;
}

Future<List<Map<String, Object?>>> _loadLocalRows(
  Database db,
  _ScopeConfig scope,
) {
  return db.query(
    scope.tableName,
    columns: const ['sync_id', 'deleted_at', 'sync_status'],
  );
}

Future<Map<String, int>> _activeDeletedCounts(Database db, String tableName) async {
  return {
    'active': await _count(db, tableName, where: 'deleted_at IS NULL'),
    'deleted': await _count(db, tableName, where: 'deleted_at IS NOT NULL'),
  };
}

Future<int> _count(
  Database db,
  String tableName, {
  String? where,
}) async {
  final rows = await db.query(
    tableName,
    columns: const ['COUNT(*) AS total'],
    where: where,
  );
  final value = rows.first['total'];
  if (value is int) {
    return value;
  }
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

class _ScopeConfig {
  const _ScopeConfig({required this.remoteScope, required this.tableName});

  final String remoteScope;
  final String tableName;
}

const List<_ScopeConfig> _scopeConfigs = [
  _ScopeConfig(remoteScope: 'clients', tableName: DatabaseSchema.clientsTable),
  _ScopeConfig(remoteScope: 'products', tableName: DatabaseSchema.lotsTable),
  _ScopeConfig(remoteScope: 'sales', tableName: DatabaseSchema.salesTable),
  _ScopeConfig(
    remoteScope: 'installments',
    tableName: DatabaseSchema.installmentsTable,
  ),
  _ScopeConfig(remoteScope: 'payments', tableName: DatabaseSchema.paymentsTable),
];