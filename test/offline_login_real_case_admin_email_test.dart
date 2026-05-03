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
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('offline_real_admin_case_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@gmail.com'
      ..adminPassword = 'Ayleen10'
      ..adminFullName = 'Admin Real';

    authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: FakeSyncConfigRepository(settings: buildFakeSettings()),
      httpClient: FakeBackendHttpClient(state: backendState),
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('offline login works with Admin@gmail.com after one online login', () async {
    final online = await authService.signInHybrid(
      email: 'Admin@gmail.com',
      password: 'Ayleen10',
    );
    expect(online.mode, AuthSignInMode.online);

    await authService.signOut();
    backendState.offline = true;

    final offline = await authService.signInHybrid(
      email: 'Admin@gmail.com',
      password: 'Ayleen10',
    );

    expect(offline.mode, AuthSignInMode.offline);
    expect(offline.user.email, 'admin@gmail.com');
  });
}
