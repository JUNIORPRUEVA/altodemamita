import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SettingsRepository settingsRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'read_only_configuration_hardening_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    settingsRepository = SettingsRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('fetchByKeysWithDefaults no persiste claves faltantes al solo leer', () async {
    final defaults = <String, String>{
      'test.read_only.alpha': 'A',
      'test.read_only.beta': 'B',
    };

    final values = await settingsRepository.fetchByKeysWithDefaults(defaults);
    final db = await appDatabase.database;
    final persistedRows = await db.query(
      DatabaseSchema.settingsTable,
      where: 'clave IN (?, ?)',
      whereArgs: defaults.keys.toList(growable: false),
    );

    expect(values['test.read_only.alpha']?.value, 'A');
    expect(values['test.read_only.beta']?.value, 'B');
    expect(persistedRows, isEmpty);
  });

  test('loadSettings usa defaults en memoria sin sembrarlos en settings', () async {
    final syncConfigRepository = SyncConfigRepository(
      settingsRepository: settingsRepository,
      preferencesFactory: SharedPreferences.getInstance,
    );

    final settings = await syncConfigRepository.loadSettings();
    final db = await appDatabase.database;
    final persistedRows = await db.query(
      DatabaseSchema.settingsTable,
      where: 'clave IN (?, ?, ?, ?)',
      whereArgs: const [
        SyncConfigRepository.syncBaseUrlKey,
        SyncConfigRepository.syncQueueRetrySecondsKey,
        SyncConfigRepository.syncRealtimePollingSecondsKey,
        SyncConfigRepository.syncConflictStrategyKey,
      ],
    );

    expect(
      settings.baseUrl,
      '',
    );
    expect(settings.queueRetryInterval, const Duration(seconds: 10));
    expect(settings.realtimePollingInterval, const Duration(seconds: 5));
    expect(persistedRows, isEmpty);
  });
}