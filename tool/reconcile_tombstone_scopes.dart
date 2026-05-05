import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/repositories/payments_sync_repository.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sistema_solares/repositories/sales_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';
import 'package:sqflite_common/sqlite_api.dart';

const _targetScopes = ['products', 'sales', 'installments', 'payments'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  await appDatabase.initialize();
  final settings = await configRepository.loadSettings();
  if (!settings.isConfigured) {
    stderr.writeln('missing sync settings or jwt');
    exitCode = 2;
    return;
  }

  final epoch = DateTime.utc(1970, 1, 1);
  for (final scope in _targetScopes) {
    await configRepository.saveCursor(scope, epoch);
  }

  final remoteSnapshot = await apiClient.downloadChanges(
    settings: settings,
    updatedSinceByScope: {
      for (final scope in _targetScopes) scope: epoch,
    },
  );

  final beforeStats = await getSyncStats(
    db: await appDatabase.database,
    remoteRecordsByScope: remoteSnapshot.recordsByScope,
  );

  final downloaded = await syncService.downloadUpdatesForScopes(_targetScopes);

  final afterStats = await getSyncStats(
    db: await appDatabase.database,
    remoteRecordsByScope: remoteSnapshot.recordsByScope,
  );

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'downloaded_records': downloaded,
      'scopes': _targetScopes,
      'since': '1970-01-01T00:00:00.000Z',
      'before': beforeStats,
      'after': afterStats,
    }),
  );

  await appDatabase.close();
}

Future<Map<String, Object?>> getSyncStats({
  required Database db,
  required Map<String, List<Map<String, dynamic>>> remoteRecordsByScope,
}) async {
  return {
    for (final scope in _targetScopes)
      scope: await _buildScopeStats(
        db,
        scope,
        remoteRecordsByScope[scope] ?? const <Map<String, dynamic>>[],
      ),
  };
}

Future<Map<String, Object?>> _buildScopeStats(
  Database db,
  String scope,
  List<Map<String, dynamic>> remoteRows,
) async {
  final tableName = switch (scope) {
    'products' => DatabaseSchema.lotsTable,
    'sales' => DatabaseSchema.salesTable,
    'installments' => DatabaseSchema.installmentsTable,
    'payments' => DatabaseSchema.paymentsTable,
    _ => throw ArgumentError('unsupported scope: $scope'),
  };
  final localRows = await db.query(
    tableName,
    columns: const ['sync_id', 'deleted_at', 'sync_status'],
  );
  final localBySyncId = {
    for (final row in localRows)
      if (_readString(row['sync_id']) != null) _readString(row['sync_id'])!: row,
  };
  final remoteBySyncId = {
    for (final row in remoteRows)
      if (_readString(row['sync_id']) != null) _readString(row['sync_id'])!: row,
  };

  final missingDeleted = <String>[];
  for (final entry in remoteBySyncId.entries) {
    final remoteDeleted = _readString(entry.value['deleted_at']) != null;
    final localRow = localBySyncId[entry.key];
    if (!remoteDeleted) {
      continue;
    }
    if (localRow == null || _readString(localRow['deleted_at']) == null) {
      missingDeleted.add(entry.key);
    }
  }

  return {
    'local_deleted': localRows.where((row) => _readString(row['deleted_at']) != null).length,
    'backend_deleted': remoteRows.where((row) => _readString(row['deleted_at']) != null).length,
    'missing_deleted_sync_ids': missingDeleted,
  };
}

String? _readString(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty || normalized == 'null') {
    return null;
  }
  return normalized;
}