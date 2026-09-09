import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'new_pc_registers_device_id_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('PC nueva genera y reutiliza un device_id persistente', () async {
    final repository = SyncConfigRepository(
      settingsRepository: SettingsRepository(appDatabase: appDatabase),
      preferencesFactory: SharedPreferences.getInstance,
    );

    final firstDeviceId = await repository.getOrCreateDeviceId();
    final secondDeviceId = await repository.getOrCreateDeviceId();

    expect(firstDeviceId, isNotEmpty);
    expect(firstDeviceId, hasLength(32));
    expect(secondDeviceId, firstDeviceId);
  });

  test('reset de identificacion local rota el device_id', () async {
    final repository = SyncConfigRepository(
      settingsRepository: SettingsRepository(appDatabase: appDatabase),
      preferencesFactory: SharedPreferences.getInstance,
    );

    final firstDeviceId = await repository.getOrCreateDeviceId();
    final rotatedDeviceId = await repository.rotateDeviceId();
    final loadedAfterRotation = await repository.getOrCreateDeviceId();

    expect(firstDeviceId, isNotEmpty);
    expect(rotatedDeviceId, isNotEmpty);
    expect(rotatedDeviceId, isNot(firstDeviceId));
    expect(loadedAfterRotation, rotatedDeviceId);
  });
}
