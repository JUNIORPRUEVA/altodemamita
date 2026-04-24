import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recoveryCode = 'ABCD-EFGH-JKLM-NPQR';

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late FakeBackendState backendState;
  late FakeSyncConfigRepository configRepository;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_hybrid_auth_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState();
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

  test(
    'configura local, inicia offline y mantiene fallback online si existe backend',
    () async {
      final bootstrap = await authService.bootstrap();

      expect(bootstrap.requiresInitialSetup, isTrue);
      expect(bootstrap.isOnline, isTrue);
      expect(bootstrap.isCloudInitialized, isFalse);

      await authService.completeInitialSetup(
        companyName: 'Sistema Test',
        nombre: 'Admin General',
        email: 'admin@test.local',
        password: 'AdminSegura123',
        recoveryCode: recoveryCode,
      );

      expect(backendState.initialized, isFalse);
      expect(await authService.requiresInitialSetup(), isFalse);

      final localResult = await authService.signInHybrid(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );

      expect(localResult.user.email, 'admin@test.local');

      final offlineUser = await authService.loginOffline(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );

      expect(offlineUser.email, 'admin@test.local');
    },
  );

  test(
    'permite iniciar sesion offline aunque el backend no este configurado',
    () async {
      final seeded = buildFakeSettings();
      configRepository = FakeSyncConfigRepository(
        settings: SyncSettings(
          baseUrl: '',
          jwtToken: seeded.jwtToken,
          queueRetryInterval: seeded.queueRetryInterval,
          realtimePollingInterval: seeded.realtimePollingInterval,
          conflictStrategy: seeded.conflictStrategy,
          deviceId: seeded.deviceId,
        ),
      );
      authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );

      await authService.createUser(
        nombre: 'Operador Caja',
        email: 'caja@local.test',
        password: 'CajaSegura123',
        role: UserRole.user,
        permissions: const <PermissionModel>[],
      );

      final result = await authService.signInHybrid(
        email: 'caja@local.test',
        password: 'CajaSegura123',
      );

      expect(result.mode, AuthSignInMode.offline);
      expect(result.user.email, 'caja@local.test');
    },
  );
}
