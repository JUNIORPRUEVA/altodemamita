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
import 'package:sistema_solares/repositories/permissions_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/role_permissions_sync_repository.dart';
import 'package:sistema_solares/repositories/roles_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/repositories/user_roles_sync_repository.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';
import 'package:sqflite_common/sqlite_api.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final workspaceRoot = Directory.current.path;
  final snapshotPath = args.isNotEmpty
      ? args.first
      : path.join(
          workspaceRoot,
          'backups',
          'phase_final',
          'backend_snapshot_before_20260505_145351.json',
        );
  final snapshotFile = File(snapshotPath);
  if (!await snapshotFile.exists()) {
    stderr.writeln('[PhaseFinalSnapshot] snapshot_not_found=$snapshotPath');
    exitCode = 2;
    return;
  }

  final startedAt = DateTime.now();
  final timestamp = _timestamp(startedAt);
  final reportDir = Directory(path.join(workspaceRoot, 'backups', 'phase_final'));
  await reportDir.create(recursive: true);

  final appDatabase = AppDatabase.instance;
  final syncQueueService = SyncQueueService.instance;
  final configRepository = SyncConfigRepository();

  final dbPath = await appDatabase.databasePath;
  await appDatabase.close();
  final sqliteBackupPath = path.join(
    reportDir.path,
    'sqlite_before_snapshot_apply_$timestamp.db',
  );
  await File(dbPath).copy(sqliteBackupPath);
  stdout.writeln('[PhaseFinalSnapshot] sqlite_backup=$sqliteBackupPath');

  final snapshotJson = jsonDecode(await snapshotFile.readAsString())
      as Map<String, dynamic>;
  final remoteRecordsByScope = <String, List<Map<String, dynamic>>>{
    for (final entry in (snapshotJson['records'] as Map<String, dynamic>).entries)
      entry.key: (entry.value as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
  };

  await appDatabase.initialize();
  final beforeDb = await appDatabase.database;
  final beforeSummary = await _buildLocalSummary(beforeDb);
  final beforeComparison = await _buildComparison(
    db: beforeDb,
    remoteRecordsByScope: remoteRecordsByScope,
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
    syncQueueService: syncQueueService,
    appDatabase: appDatabase,
  );

  var appliedRecords = 0;
  var retryScopes = <String>{};
  final retryDetails = <Map<String, Object?>>[];
  for (final scope in _applyOrder) {
    final scopeRecords = remoteRecordsByScope[scope] ?? const <Map<String, dynamic>>[];
    try {
      appliedRecords += await syncService.applyRemoteScopeRecords(
        scope: scope,
        records: scopeRecords,
      );
    } catch (error) {
      if (error is RemoteSyncDependencyException) {
        retryScopes.add(scope);
        retryScopes.addAll(error.missingScopes);
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

  for (var pass = 0; pass < 2 && retryScopes.isNotEmpty; pass++) {
    final pendingScopes = retryScopes;
    retryScopes = <String>{};
    for (final scope in _applyOrder.where(pendingScopes.contains)) {
      final scopeRecords = remoteRecordsByScope[scope] ?? const <Map<String, dynamic>>[];
      try {
        appliedRecords += await syncService.applyRemoteScopeRecords(
          scope: scope,
          records: scopeRecords,
        );
      } catch (error) {
        if (error is RemoteSyncDependencyException) {
          retryScopes.add(scope);
          retryScopes.addAll(error.missingScopes);
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
  }

  final afterDb = await appDatabase.database;
  final afterSummary = await _buildLocalSummary(afterDb);
  final afterComparison = await _buildComparison(
    db: afterDb,
    remoteRecordsByScope: remoteRecordsByScope,
  );

  final reportPath = path.join(
    reportDir.path,
    'phase_final_snapshot_apply_report_$timestamp.json',
  );
  await File(reportPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'started_at': startedAt.toIso8601String(),
      'finished_at': DateTime.now().toIso8601String(),
      'sqlite_backup': sqliteBackupPath,
      'snapshot_path': snapshotPath,
      'applied_records': appliedRecords,
      'remaining_retry_scopes': retryScopes.toList(),
      'retry_details': retryDetails,
      'before': {
        'local_summary': beforeSummary,
        'comparison': beforeComparison,
      },
      'after': {
        'local_summary': afterSummary,
        'comparison': afterComparison,
      },
    }),
  );

  stdout.writeln('[PhaseFinalSnapshot] report=$reportPath');
  stdout.writeln('[PhaseFinalSnapshot] applied_records=$appliedRecords');
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
    final localRows = await db.query(
      scope.tableName,
      columns: const ['sync_id', 'deleted_at', 'sync_status'],
    );
    result[scope.remoteScope] = _compareScope(
      scope: scope,
      localRows: localRows,
      remoteRows: remoteRecordsByScope[scope.remoteScope] ?? const [],
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

  for (final entry in remoteBySyncId.entries) {
    final syncId = entry.key;
    final remoteRow = entry.value;
    final localRow = localBySyncId[syncId];
    final remoteDeleted = _readString(remoteRow['deleted_at']) != null;
    if (localRow != null) {
      continue;
    }

    final payload = <String, Object?>{
      'sync_id': syncId,
      'remote_deleted_at': _readString(remoteRow['deleted_at']),
      'remote_id': _readString(remoteRow['id']),
    };
    if (scope.remoteScope == 'sales') {
      payload['remote_installments'] = remoteInstallmentsBySale[syncId] ?? 0;
      payload['remote_payments'] = remotePaymentsBySale[syncId] ?? 0;
    }
    if (remoteDeleted) {
      backendDeletedNotInLocal.add(payload);
    } else {
      backendActiveNotInLocal.add(payload);
    }
  }

  return {
    'local_active': localRows.where((row) => _readString(row['deleted_at']) == null).length,
    'local_deleted': localRows.where((row) => _readString(row['deleted_at']) != null).length,
    'backend_active': remoteRows.where((row) => _readString(row['deleted_at']) == null).length,
    'backend_deleted': remoteRows.where((row) => _readString(row['deleted_at']) != null).length,
    'backend_active_not_in_local': backendActiveNotInLocal,
    'backend_deleted_not_in_local': backendDeletedNotInLocal,
  };
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

const List<String> _applyOrder = [
  'users',
  'roles',
  'user_roles',
  'role_permissions',
  'permissions',
  'clients',
  'products',
  'sellers',
  'sales',
  'installments',
  'payments',
];

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