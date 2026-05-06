import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late FakeBackendState backendState;
  late FakeSyncConfigRepository configRepository;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('new_pc_offline_after_sync_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@test.local'
      ..adminPassword = 'AdminSegura123'
      ..adminFullName = 'Admin Remoto';
    configRepository = FakeSyncConfigRepository(settings: buildFakeSettings());
    authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: configRepository,
      httpClient: FakeBackendHttpClient(state: backendState),
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('PC nueva puede iniciar offline despues del primer login online', () async {
    await authService.signInHybrid(
      email: 'admin@test.local',
      password: 'AdminSegura123',
    );
    await authService.signOut();

    backendState.offline = true;
    final result = await authService.signInHybrid(
      email: 'admin@test.local',
      password: 'AdminSegura123',
    );

    expect(result.mode, AuthSignInMode.offline);
    expect(result.user.email, 'admin@test.local');
  });
}