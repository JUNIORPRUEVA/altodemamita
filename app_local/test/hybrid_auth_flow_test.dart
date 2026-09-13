import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
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
            contains(
              'Esta PC todavía no ha sido activada. Conéctala a internet e inicia sesión una vez para habilitar el acceso offline.',
            ),
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

  test('valid production-style OWNER user login maps successfully', () async {
    backendState.initialized = true;
    backendState.adminEmail = 'admin@sistema.local';
    backendState.adminPassword = 'PasswordNube123';
    backendState.adminFullName = 'Admin Produccion';
    backendState.authRoles = const ['SUPER_ADMIN'];
    backendState.authPermissions = const [
      'clients.read',
      'clients.write',
      'products.read',
      'products.write',
      'sellers.read',
      'sellers.write',
      'sales.read',
      'sales.write',
      'payments.read',
      'payments.write',
      'installments.read',
      'installments.write',
      'users.read',
      'users.write',
      'reports.read',
      'sync.manage',
    ];

    final result = await authService.signInHybrid(
      email: 'admin@sistema.local',
      password: 'PasswordNube123',
    );

    expect(result.mode, AuthSignInMode.online);
    expect(result.user.email, 'admin@sistema.local');
    expect(result.user.remoteAuthId, 'remote-admin-1');
    expect(result.user.role, UserRole.admin);
    expect(result.user.activo, isTrue);
    expect(
      result.user.allows(PermissionCatalog.sales, PermissionAction.read),
      isTrue,
    );
  });

  test(
    'clean cache fresh cloud OWNER login maps and restores via auth me',
    () async {
      backendState.initialized = true;
      backendState.adminEmail = 'admin@sistema.local';
      backendState.adminPassword = 'PasswordNube123';
      backendState.adminFullName = 'Admin Produccion';
      backendState.authRoles = const ['SUPER_ADMIN'];
      backendState.authPermissions = const [
        'clients.read',
        'clients.write',
        'products.read',
        'products.write',
        'sellers.read',
        'sellers.write',
        'sales.read',
        'sales.write',
        'payments.read',
        'payments.write',
        'installments.read',
        'installments.write',
        'users.read',
        'users.write',
        'reports.read',
        'sync.manage',
      ];

      final loginResult = await authService.signInHybrid(
        email: 'admin@sistema.local',
        password: 'PasswordNube123',
      );

      expect(loginResult.mode, AuthSignInMode.online);
      expect(loginResult.user.email, 'admin@sistema.local');
      expect(loginResult.user.remoteAuthId, 'remote-admin-1');
      expect(loginResult.user.role, UserRole.admin);
      expect(loginResult.user.authSource, AuthSource.cloud);
      expect(configRepository.savedJwtToken, 'jwt-test-token');
      expect(backendState.authLoginRequests, 1);

      final db = await appDatabase.database;
      await db.delete('sesiones_auth');

      final restored = await authService.bootstrap();

      expect(restored.requiresInitialSetup, isFalse);
      expect(restored.isOnline, isTrue);
      expect(restored.isCloudInitialized, isTrue);
      expect(restored.currentUser?.email, 'admin@sistema.local');
      expect(restored.currentUser?.remoteAuthId, 'remote-admin-1');
      expect(restored.currentUser?.authSource, AuthSource.cloud);
      expect(backendState.authMeRequests, 1);
    },
  );

  test(
    'session persistence stores no password and logout clears session',
    () async {
      backendState.initialized = true;
      backendState.adminEmail = 'admin@sistema.local';
      backendState.adminPassword = 'PasswordNube123';
      backendState.adminFullName = 'Admin Produccion';

      await authService.signInHybrid(
        email: 'admin@sistema.local',
        password: 'PasswordNube123',
      );

      final preferences = await SharedPreferences.getInstance();
      for (final key in preferences.getKeys()) {
        expect(
          preferences.get(key)?.toString(),
          isNot(contains('PasswordNube123')),
          reason: 'La sesion no debe persistir la contrasena en $key.',
        );
      }

      final db = await appDatabase.database;
      final sessionRows = await db.query('sesiones_auth');
      expect(sessionRows, isNotEmpty);
      expect(
        sessionRows.any(
          (row) => row.values.any(
            (value) => value?.toString().contains('PasswordNube123') ?? false,
          ),
        ),
        isFalse,
      );

      await authService.signOut();

      expect(configRepository.savedJwtToken, isEmpty);
      final revokedRows = await db.query(
        'sesiones_auth',
        where: 'revoked_at IS NOT NULL',
      );
      expect(revokedRows.length, sessionRows.length);
      expect(await authService.restoreSession(), isNull);
    },
  );

  test('logout then login enters immediately through auth result', () async {
    backendState.initialized = true;
    backendState.adminEmail = 'admin@sistema.local';
    backendState.adminPassword = 'PasswordNube123';
    backendState.adminFullName = 'Admin Produccion';

    final first = await authService.signInHybrid(
      email: 'admin@sistema.local',
      password: 'PasswordNube123',
    );
    expect(first.user.email, 'admin@sistema.local');
    expect(first.mode, AuthSignInMode.online);

    await authService.signOut();

    final second = await authService.signInHybrid(
      email: 'admin@sistema.local',
      password: 'PasswordNube123',
    );

    expect(second.user.email, 'admin@sistema.local');
    expect(second.mode, AuthSignInMode.online);
    expect(await authService.requiresInitialSetup(), isFalse);
  });

  test('missing truly-required remote user id still fails safely', () async {
    backendState.initialized = true;
    backendState.adminEmail = 'admin@sistema.local';
    backendState.adminPassword = 'PasswordNube123';
    backendState.adminFullName = 'Admin Produccion';
    backendState.omitAuthSub = true;

    await expectLater(
      authService.signInHybrid(
        email: 'admin@sistema.local',
        password: 'PasswordNube123',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'El usuario remoto no incluye los datos minimos requeridos.',
        ),
      ),
    );
  });

  test(
    'PC nueva sin backend configurado queda offline sin fallback automatico',
    () async {
      configRepository = FakeSyncConfigRepository(
        settings: SyncSettings(
          baseUrl: '',
          jwtToken: '',
          queueRetryInterval: const Duration(seconds: 10),
          realtimePollingInterval: const Duration(seconds: 5),
          conflictStrategy: SyncConflictStrategy.manual,
          deviceId: 'test-device',
        ),
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
      expect(bootstrap.isOnline, isFalse);
      expect(bootstrap.isCloudInitialized, isFalse);
      expect((await configRepository.loadSettings()).normalizedBaseUrl, '');
    },
  );

  test(
    'PC nueva no intenta host legado cuando el backend no esta configurado',
    () async {
      configRepository = FakeSyncConfigRepository(
        settings: SyncSettings(
          baseUrl: '',
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
      expect(bootstrap.isOnline, isFalse);
      expect(bootstrap.isCloudInitialized, isFalse);
      expect((await configRepository.loadSettings()).normalizedBaseUrl, '');
    },
  );

  test(
    'login usa credenciales locales aunque la nube este inicializada',
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

      final result = await authService.signIn(
        email: 'admin@test.local',
        password: 'PasswordLocal123',
      );

      expect(result.email, 'admin@test.local');
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
