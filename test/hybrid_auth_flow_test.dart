import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/config/backend_config.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

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
    'configura local, bootstrapea nube si esta disponible y mantiene fallback offline',
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

      expect(backendState.initialized, isTrue);
      expect(await authService.requiresInitialSetup(), isFalse);

      final localResult = await authService.signInHybrid(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );

      expect(localResult.user.email, 'admin@test.local');
      expect(localResult.mode, AuthSignInMode.online);
      expect(localResult.syncTriggered, isTrue);

      final offlineUser = await authService.loginOffline(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );

      expect(offlineUser.email, 'admin@test.local');
    },
  );

  test(
    'backend offline y sin sesion local previa no permite setup falso ni login',
    () async {
      backendState.offline = true;

      final bootstrap = await authService.bootstrap();

      expect(bootstrap.requiresInitialSetup, isFalse);
      expect(bootstrap.isOnline, isFalse);

      await expectLater(
        authService.signInHybrid(
          email: 'admin@test.local',
          password: 'AdminSegura123',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            contains('No se puede iniciar sin conexion en una PC nueva'),
          ),
        ),
      );
    },
  );

  test(
    'PC nueva con nube ya inicializada no muestra setup sino login',
    () async {
      // Simula: otra PC ya hizo el setup inicial y la nube está inicializada
      backendState.initialized = true;
      backendState.adminEmail = 'admin@test.local';
      backendState.adminPassword = 'AdminSegura123';
      backendState.adminFullName = 'Admin General';

      // BD local vacía (PC nueva, primer arranque)
      final bootstrap = await authService.bootstrap();

      // No debe pedir setup — la nube ya está lista
      expect(bootstrap.requiresInitialSetup, isFalse);
      expect(bootstrap.isOnline, isTrue);
      expect(bootstrap.isCloudInitialized, isTrue);

      // Debe poder autenticarse con credenciales de la nube
      final result = await authService.signInHybrid(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );
      expect(result.mode, AuthSignInMode.online);
      expect(result.user.email, 'admin@test.local');
      expect(configRepository.savedJwtToken, 'jwt-test-token');

      // El usuario ahora debe estar en caché local
      expect(await authService.requiresInitialSetup(), isFalse);
    },
  );

  test(
    'PC nueva corrige una URL local vieja y usa el backend oficial',
    () async {
      configRepository = FakeSyncConfigRepository(
        settings: SyncSettings(
          baseUrl: 'http://127.0.0.1:3000/api',
          jwtToken: '',
          queueRetryInterval: const Duration(seconds: 10),
          realtimePollingInterval: const Duration(seconds: 5),
          conflictStrategy: SyncConflictStrategy.manual,
          deviceId: 'test-device',
        ),
      );
      backendState.unreachableHosts.add('127.0.0.1');
      backendState.initialized = true;
      backendState.adminEmail = 'admin@test.local';
      backendState.adminPassword = 'AdminSegura123';
      backendState.adminFullName = 'Admin General';
      authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );

      final bootstrap = await authService.bootstrap();

      expect(bootstrap.requiresInitialSetup, isFalse);
      expect(bootstrap.isOnline, isTrue);
      expect(bootstrap.isCloudInitialized, isTrue);
      expect(
        (await configRepository.loadSettings()).normalizedBaseUrl,
        SyncConfigRepository.normalizeBackendBaseUrl(
          SyncConfigRepository.defaultSyncBaseUrl,
        ),
      );
    },
  );

  test('PC nueva usa host legado si el host canonico no responde', () async {
    configRepository = FakeSyncConfigRepository(
      settings: SyncSettings(
        baseUrl: SyncConfigRepository.normalizeBackendBaseUrl(
          SyncConfigRepository.defaultSyncBaseUrl,
        ),
        jwtToken: '',
        queueRetryInterval: const Duration(seconds: 10),
        realtimePollingInterval: const Duration(seconds: 5),
        conflictStrategy: SyncConflictStrategy.manual,
        deviceId: 'test-device',
      ),
    );
    backendState.unreachableHosts.add(
      'altodemanita-altodemamita-backend.onqyr1.easypanel.host',
    );
    backendState.initialized = true;
    backendState.adminEmail = 'admin@test.local';
    backendState.adminPassword = 'AdminSegura123';
    backendState.adminFullName = 'Admin General';
    authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: configRepository,
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    final bootstrap = await authService.bootstrap();

    expect(bootstrap.requiresInitialSetup, isFalse);
    expect(bootstrap.isOnline, isTrue);
    expect(bootstrap.isCloudInitialized, isTrue);
    expect(
      (await configRepository.loadSettings()).normalizedBaseUrl,
      SyncConfigRepository.normalizeBackendBaseUrl(LEGACY_BASE_URL),
    );
  });

  test(
    'login local sin JWT contra nube inicializada no cae silenciosamente a offline',
    () async {
      backendState.initialized = true;
      backendState.adminEmail = 'admin@test.local';
      backendState.adminPassword = 'PasswordNube123';
      backendState.adminFullName = 'Admin Nube';

      await authService.createUser(
        nombre: 'Admin Local',
        email: 'admin@test.local',
        password: 'PasswordLocal123',
        role: UserRole.admin,
        permissions: const <PermissionModel>[],
      );

      await expectLater(
        authService.signInHybrid(
          email: 'admin@test.local',
          password: 'PasswordLocal123',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            contains('No se pudo iniciar sesion en la nube'),
          ),
        ),
      );
      expect(configRepository.savedJwtToken, isEmpty);
    },
  );

  test(
    'vincular nube guarda JWT y enlaza usuario local con remoteAuthId',
    () async {
      backendState.initialized = true;
      backendState.adminEmail = 'admin@test.local';
      backendState.adminPassword = 'PasswordNube123';
      backendState.adminFullName = 'Admin Nube';

      await authService.createUser(
        nombre: 'Admin Local',
        email: 'admin@test.local',
        password: 'PasswordLocal123',
        role: UserRole.admin,
        permissions: const <PermissionModel>[],
      );

      final linked = await authService.connectToCloudForSync(
        email: 'admin@test.local',
        password: 'PasswordNube123',
      );

      expect(configRepository.savedJwtToken, 'jwt-test-token');
      expect(linked.email, 'admin@test.local');
      expect(linked.remoteAuthId, 'remote-admin-1');
      expect(linked.authSource, AuthSource.cloud);

      final syncService = SyncService(
        repositories: const [],
        configRepository: configRepository,
      );
      expect(await syncService.startupBlockReason(), isNull);
    },
  );
}
