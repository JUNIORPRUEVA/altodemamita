import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/config/app_flags.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import '../../core/resilience/app_paths.dart';
import 'sync_api_client.dart';
import 'sync_config_repository.dart';
import 'sync_logger.dart';
import 'sync_service.dart';

class EmergencyRestorePreview {
  const EmergencyRestorePreview({
    required this.localCounts,
    required this.cloudCounts,
  });

  final Map<String, int> localCounts;
  final Map<String, int> cloudCounts;

  bool get hasLocalCommercialData =>
      localCounts.values.any((value) => value > 0);
}

class EmergencyRestoreResult {
  const EmergencyRestoreResult({
    required this.backupPath,
    required this.downloadedCounts,
    required this.localCountsAfter,
    required this.duration,
  });

  final String backupPath;
  final Map<String, int> downloadedCounts;
  final Map<String, int> localCountsAfter;
  final Duration duration;
}

class EmergencyCloudRestoreService {
  EmergencyCloudRestoreService({
    required SyncService syncService,
    SyncApiClient? apiClient,
    SyncConfigRepository? configRepository,
    AppDatabase? appDatabase,
    AppPaths? appPaths,
    SyncLogger? syncLogger,
  }) : _syncService = syncService,
       _apiClient = apiClient ?? SyncApiClient(),
       _configRepository = configRepository ?? SyncConfigRepository(),
       _appDatabase = appDatabase ?? AppDatabase.instance,
       _appPaths = appPaths ?? AppDatabase.instance.appPaths,
       _syncLogger = syncLogger ?? SyncLogger.instance;

  static const List<String> orderedScopes = <String>[
    'company_profiles',
    'clients',
    'sellers',
    'products',
    'sales',
    'installments',
    'payments',
  ];

  static const List<String> commercialScopes = <String>[
    'clients',
    'sellers',
    'products',
    'sales',
    'installments',
    'payments',
  ];

  final SyncService _syncService;
  final SyncApiClient _apiClient;
  final SyncConfigRepository _configRepository;
  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final SyncLogger _syncLogger;

  Future<EmergencyRestorePreview> preview() async {
    _ensureManualRestoreEnabled();
    final settings = await _configRepository.loadSettings();
    _ensureCloudSessionConfigured(settings.isConfigured);

    final cloudCounts = await _apiClient.previewManualRestore(
      settings: settings,
    );
    final localCounts = await _readLocalCommercialCounts();

    return EmergencyRestorePreview(
      localCounts: localCounts,
      cloudCounts: {
        for (final scope in orderedScopes) scope: cloudCounts[scope] ?? 0,
      },
    );
  }

  Future<EmergencyRestoreResult> restoreOnCleanPc({
    required String adminPassword,
    required String confirmationText,
    required String adminUser,
    required String deviceId,
    required String installationId,
  }) async {
    _ensureManualRestoreEnabled();
    if (confirmationText.trim().toUpperCase() != 'RESTAURAR') {
      throw Exception('Confirmacion invalida. Debe escribir RESTAURAR.');
    }

    final startedAt = DateTime.now();
    final settings = await _configRepository.loadSettings();
    _ensureCloudSessionConfigured(settings.isConfigured);

    final localCountsBefore = await _readLocalCommercialCounts();
    if (localCountsBefore.values.any((value) => value > 0)) {
      throw Exception(
        'Esta PC ya tiene datos comerciales locales. Por seguridad, primero haga backup o use una PC limpia.',
      );
    }

    final backupPath = await _createPreRestoreBackup();
    try {
      final payload = await _apiClient.downloadManualRestore(
        settings: settings,
        adminPassword: adminPassword,
        confirmationText: confirmationText,
      );

      final downloadedCounts = <String, int>{
        for (final scope in orderedScopes)
          scope: payload.recordsForScope(scope).length,
      };

      await _replaceLocalCommercialData(payload.recordsByScope);
      await _clearSyncQueueForRestoreScopes();

      final localCountsAfter = await _readLocalCommercialCounts();
      _validatePostRestoreCounts(
        cloudCounts: downloadedCounts,
        localCounts: localCountsAfter,
      );

      final duration = DateTime.now().difference(startedAt);
      await _syncLogger.log(
        action: 'manual-cloud-restore',
        entity: 'commercial-data',
        result: 'ok',
        extra: {
          'adminUser': adminUser,
          'deviceId': deviceId,
          'installationId': installationId,
          'backupPath': backupPath,
          'durationMs': duration.inMilliseconds,
          'downloadedCounts': downloadedCounts,
          'localCountsAfter': localCountsAfter,
        },
      );

      return EmergencyRestoreResult(
        backupPath: backupPath,
        downloadedCounts: downloadedCounts,
        localCountsAfter: localCountsAfter,
        duration: duration,
      );
    } catch (error) {
      await _rollbackFromBackup(backupPath);
      await _syncLogger.log(
        action: 'manual-cloud-restore',
        entity: 'commercial-data',
        result: 'error',
        error: error.toString(),
        extra: {
          'adminUser': adminUser,
          'deviceId': deviceId,
          'installationId': installationId,
          'backupPath': backupPath,
        },
      );
      rethrow;
    }
  }

  Future<Map<String, int>> _readLocalCommercialCounts() async {
    final db = await _appDatabase.database;
    Future<int> countFrom(String table, {String where = '1 = 1'}) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM $table WHERE $where',
      );
      final raw = rows.isEmpty ? 0 : rows.first['total'];
      if (raw is int) {
        return raw;
      }
      if (raw is num) {
        return raw.toInt();
      }
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return {
      'clients': await countFrom(
        DatabaseSchema.clientsTable,
        where: 'deleted_at IS NULL',
      ),
      'sellers': await countFrom(
        DatabaseSchema.sellersTable,
        where: 'deleted_at IS NULL',
      ),
      'products': await countFrom(
        DatabaseSchema.lotsTable,
        where: 'deleted_at IS NULL',
      ),
      'sales': await countFrom(
        DatabaseSchema.salesTable,
        where: 'deleted_at IS NULL',
      ),
      'installments': await countFrom(
        DatabaseSchema.installmentsTable,
        where: 'deleted_at IS NULL',
      ),
      'payments': await countFrom(
        DatabaseSchema.paymentsTable,
        where: 'deleted_at IS NULL',
      ),
    };
  }

  Future<void> _replaceLocalCommercialData(
    Map<String, List<Map<String, dynamic>>> recordsByScope,
  ) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.delete(DatabaseSchema.paymentsTable);
      await txn.delete(DatabaseSchema.installmentsTable);
      await txn.delete(DatabaseSchema.salesTable);
      await txn.delete(DatabaseSchema.clientsTable);
      await txn.delete(DatabaseSchema.sellersTable);
      await txn.delete(DatabaseSchema.lotsTable);
    });

    for (final scope in orderedScopes) {
      final records = recordsByScope[scope] ?? const <Map<String, dynamic>>[];
      if (records.isEmpty) {
        continue;
      }
      await _syncService.applyRemoteScopeRecords(
        scope: scope,
        records: records,
      );
    }
  }

  Future<void> _clearSyncQueueForRestoreScopes() async {
    final db = await _appDatabase.database;
    final scopes = <String>['company_profiles', ...commercialScopes];
    final placeholders = List.filled(scopes.length, '?').join(', ');
    await db.rawDelete(
      'DELETE FROM ${DatabaseSchema.syncQueueTable} WHERE scope IN ($placeholders)',
      scopes,
    );
  }

  void _validatePostRestoreCounts({
    required Map<String, int> cloudCounts,
    required Map<String, int> localCounts,
  }) {
    for (final scope in commercialScopes) {
      final cloud = cloudCounts[scope] ?? 0;
      final local = localCounts[scope] ?? 0;
      if (cloud != local) {
        throw Exception(
          'Validacion fallida en $scope: local=$local y cloud=$cloud.',
        );
      }
    }
  }

  Future<String> _createPreRestoreBackup() async {
    await _appPaths.ensureCriticalDirectories();
    final restoreDir = Directory(
      path.join(_appPaths.backupsDirectory, 'Restore'),
    );
    await restoreDir.create(recursive: true);

    final now = DateTime.now();
    final twoDigits = (int value) => value.toString().padLeft(2, '0');
    final fileName =
        'restore_backup_before_cloud_restore_${now.year}_${twoDigits(now.month)}_${twoDigits(now.day)}_${twoDigits(now.hour)}_${twoDigits(now.minute)}.db';
    final backupPath = path.join(restoreDir.path, fileName);

    final databasePath = await _appDatabase.databasePath;
    await _appDatabase.close();

    final source = File(databasePath);
    if (!await source.exists()) {
      throw Exception('No se encontro base local para crear backup previo.');
    }

    await source.copy(backupPath);
    await _appDatabase.initialize();
    return backupPath;
  }

  Future<void> _rollbackFromBackup(String backupPath) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      return;
    }

    final databasePath = await _appDatabase.databasePath;
    await _appDatabase.close();
    await backupFile.copy(databasePath);
    await _appDatabase.initialize();
  }

  void _ensureManualRestoreEnabled() {
    if (!allowManualCloudRestore) {
      throw Exception('Operacion bloqueada: ALLOW_MANUAL_CLOUD_RESTORE=false.');
    }
  }

  void _ensureCloudSessionConfigured(bool isConfigured) {
    if (!isConfigured) {
      throw Exception(
        'No hay sesion online activa. Inicia sesion en linea antes de restaurar.',
      );
    }
  }
}
