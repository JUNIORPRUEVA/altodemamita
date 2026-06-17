import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_runtime_state.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('reconcile_cursor_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('tombstone_download_ignores_advanced_cursor_when_force_full_test', () async {
    final repository = _RecordingRepository('products');
    final config = _FakeConfigRepository();
    final api = _EpochAwareApiClient();
    final service = SyncService(
      repositories: [repository],
      configRepository: config,
      apiClient: api,
      appDatabase: appDatabase,
    );

    final count = await service.downloadUpdatesForScopes(
      const ['products'],
      forceFullDownload: true,
    );

    expect(count, greaterThanOrEqualTo(1));
    expect(repository.mergedRecords, isNotEmpty);
    final hasDelete = repository.mergedRecords.any((r) =>
        (r['sync_id']?.toString() == 'product-old-delete') &&
        (r['deleted_at']?.toString().isNotEmpty ?? false));
    expect(hasDelete, isTrue);
    expect(api.repairCallSeen, isTrue,
        reason: 'Force full must trigger epoch-based tombstone repair pass');
  });
}

class _RecordingRepository implements SyncRepository {
  _RecordingRepository(this.scope);

  @override
  final String scope;

  final List<Map<String, dynamic>> mergedRecords = [];

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/download';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async => const [];

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {}

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {}

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    mergedRecords.addAll(records);
  }
}

class _FakeConfigRepository extends SyncConfigRepository {
  _FakeConfigRepository();

  final Map<String, DateTime?> _cursors = {
    'products': DateTime.now().toUtc(),
  };

  final SyncSettings _settings = const SyncSettings(
    baseUrl: 'https://example.com',
    jwtToken: 'token',
    queueRetryInterval: Duration(seconds: 10),
    realtimePollingInterval: Duration(seconds: 5),
    conflictStrategy: SyncConflictStrategy.lastWriteWins,
    deviceId: 'device-1',
  );

  @override
  Future<SyncSettings> loadSettings() async => _settings;

  @override
  Future<DateTime?> loadCursor(String scope) async => _cursors[scope];

  @override
  Future<void> saveCursor(String scope, DateTime timestamp) async {
    _cursors[scope] = timestamp;
  }

  @override
  Future<void> clearCursor(String scope) async {
    _cursors.remove(scope);
  }

  @override
  Future<void> clearCursors(Iterable<String> scopes) async {
    for (final scope in scopes) {
      _cursors.remove(scope);
    }
  }

  @override
  Future<void> saveLastRun({
    String? errorMessage,
    SyncRuntimeStatus status = SyncRuntimeStatus.ok,
  }) async {}
}

class _EpochAwareApiClient extends SyncApiClient {
  bool repairCallSeen = false;

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    final cursor = updatedSinceByScope?['products'];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final isEpochCall = cursor != null && cursor.isAtSameMomentAs(epoch);
    if (isEpochCall) {
      repairCallSeen = true;
      return SyncDownloadResponse(
        recordsByScope: {
          'products': [
            {
              'id': 'remote-product-old-delete',
              'sync_id': 'product-old-delete',
              'version': 2,
              'block_number': 'X',
              'lot_number': '77',
              'area': 100,
              'price_per_square_meter': 1000,
              'status': 'vendido',
              'created_at': '1970-01-02T00:00:00.000Z',
              'updated_at': '1970-01-02T00:00:00.000Z',
              'deleted_at': '1970-01-03T00:00:00.000Z',
            },
          ],
        },
        serverTime: DateTime.now().toUtc(),
        scopeCursors: {'products': DateTime.now().toUtc()},
      );
    }

    return SyncDownloadResponse(
      recordsByScope: {
        'products': const <Map<String, dynamic>>[],
      },
      serverTime: DateTime.now().toUtc(),
      scopeCursors: {'products': DateTime.now().toUtc()},
    );
  }
}
