import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late FakeBackendState backendState;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('roles_permissions_offline_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@test.local'
      ..adminPassword = 'AdminSegura123'
      ..adminFullName = 'Admin Remoto';

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

  test('roles and permissions remain available for offline login from local cache', () async {
    await authService.signInHybrid(
      email: 'admin@test.local',
      password: 'AdminSegura123',
    );
    await authService.signOut();

    backendState.offline = true;
    final offline = await authService.signInHybrid(
      email: 'admin@test.local',
      password: 'AdminSegura123',
    );

    expect(offline.mode, AuthSignInMode.offline);
    expect(
      offline.user.allows(PermissionCatalog.settings, PermissionAction.read),
      isTrue,
    );
    expect(
      offline.user.allows(PermissionCatalog.dashboard, PermissionAction.read),
      isTrue,
    );
  });
}
