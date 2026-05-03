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
    tempDirectory = await Directory.systemTemp.createTemp('offline_email_normalize_');
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

  test('offline login normalizes email casing and surrounding spaces', () async {
    await authService.signInHybrid(
      email: 'Admin@gmail.com',
      password: 'Ayleen10',
    );
    await authService.signOut();
    backendState.offline = true;

    for (final identifier in [
      'Admin@gmail.com',
      'admin@gmail.com',
      ' Admin@gmail.com ',
    ]) {
      final result = await authService.signInHybrid(
        email: identifier,
        password: 'Ayleen10',
      );
      expect(result.mode, AuthSignInMode.offline);
      await authService.signOut();
    }
  });
}
