import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/core/security/password_hasher.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'cloud_authoritative_local_state_guard_',
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

  test(
    'CLOUD_AUTHORITATIVE no siembra administrador local en DB nueva',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final db = await appDatabase.database;
      final count = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM ${DatabaseSchema.usersTable}',
      );

      expect(count.first['total'], 0);
    },
  );

  test(
    'CLOUD_AUTHORITATIVE rechaza login local legacy no vinculado a nube',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final db = await appDatabase.database;
      await db.delete(DatabaseSchema.usersTable);
      final now = DateTime.now().toIso8601String();
      await db.insert(DatabaseSchema.usersTable, {
        'sync_id': 'local-admin-old',
        'nombre': 'Admin Local',
        'email': 'admin@sistema.local',
        'password_hash': PasswordHasher.hashPassword('PasswordLocal123'),
        'password_reset_required': 0,
        'rol': 'admin',
        'activo': 1,
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'auth_source': 'local',
        'deleted_at': null,
      });

      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: SyncConfigRepository(
          settingsRepository: SettingsRepository(appDatabase: appDatabase),
          preferencesFactory: SharedPreferences.getInstance,
        ),
      );

      expect(
        () => authService.loginOffline(
          email: 'admin@sistema.local',
          password: 'PasswordLocal123',
        ),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'CLOUD_AUTHORITATIVE restaura identidad cloud antes que sesion local stale',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final backendState = FakeBackendState()
        ..initialized = true
        ..adminEmail = 'admin@sistema.local'
        ..adminPassword = 'CloudPassword123'
        ..adminFullName = 'Admin Cloud';
      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      final systemConfigService = SystemConfigService.test(
        syncConfigRepository: configRepository,
      );
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
        systemConfigService: systemConfigService,
      );

      await authService.loginOnline(
        email: 'admin@sistema.local',
        password: 'CloudPassword123',
      );
      final db = await appDatabase.database;
      await db.update(
        DatabaseSchema.usersTable,
        {'nombre': 'Admin Local'},
        where: 'email = ?',
        whereArgs: ['admin@sistema.local'],
      );

      final bootstrap = await authService.bootstrap();

      expect(bootstrap.currentUser?.nombre, 'Admin Cloud');
      expect(bootstrap.currentUser?.authSource, AuthSource.cloud);
    },
  );

  test('CLOUD_AUTHORITATIVE carga usuarios desde /business/users', () async {
    if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
      return;
    }

    final configRepository = FakeSyncConfigRepository(
      settings: buildFakeSettings(),
    );
    await configRepository.saveJwtToken('jwt-test-token');
    Uri? requestedUri;
    final backendClient = BackendApiClient(
      syncConfigRepository: configRepository,
      client: MockClient((request) async {
        requestedUri = request.url;
        expect(request.headers['authorization'], 'Bearer jwt-test-token');
        expect(request.url.path, '/api/business/users');
        return http.Response(
          '{"data":{"users":[{"id":"remote-user-1","email":"owner@test.local","name":"Owner Cloud","role":"OWNER","active":true,"companyId":"company-1"}]}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: configRepository,
      apiClient: backendClient,
      systemConfigService: SystemConfigService.test(
        syncConfigRepository: configRepository,
      ),
    );

    final users = await authService.fetchUsers();

    expect(requestedUri?.path, '/api/business/users');
    expect(users, hasLength(1));
    expect(users.single.nombre, 'Owner Cloud');
    expect(users.single.role, UserRole.admin);
    expect(users.single.authSource, AuthSource.cloud);
  });

  test(
    'CLOUD_AUTHORITATIVE creacion de usuario no depende del candado local de equipo',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      await configRepository.saveJwtToken('jwt-test-token');
      final systemConfigService =
          SystemConfigService.test(syncConfigRepository: configRepository)
            ..setDeviceWriteStateForTesting(
              canWrite: false,
              reason: 'device_not_registered',
            );
      Uri? requestedUri;
      String? requestedBody;
      final backendClient = BackendApiClient(
        syncConfigRepository: configRepository,
        client: MockClient((request) async {
          requestedUri = request.url;
          requestedBody = request.body;
          expect(request.method, 'POST');
          expect(request.headers['authorization'], 'Bearer jwt-test-token');
          expect(request.url.path, '/api/business/users');
          return http.Response(
            '{"data":{"user":{"id":"remote-user-created","email":"acceptance.user.001@sistema.local","name":"ACCEPTANCE-USER-001","role":"TECH","active":true,"companyId":"company-1","permissions":["clients.read","payments.create","payments.read","sales.read"]}}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        apiClient: backendClient,
        systemConfigService: systemConfigService,
      );

      final user = await authService.createUser(
        nombre: 'ACCEPTANCE-USER-001',
        email: 'acceptance.user.001@sistema.local',
        password: 'ValidPassword123',
        role: UserRole.user,
        permissions: const <PermissionModel>[
          PermissionModel(module: PermissionCatalog.clients, read: true),
          PermissionModel(module: PermissionCatalog.sales, read: true),
          PermissionModel(
            module: PermissionCatalog.payments,
            read: true,
            create: true,
          ),
        ],
      );

      expect(requestedUri?.path, '/api/business/users');
      expect(requestedBody, contains('"role":"TECH"'));
      expect(requestedBody, contains('"permissions"'));
      expect(requestedBody, contains('"clients.read"'));
      expect(requestedBody, contains('"sales.read"'));
      expect(requestedBody, contains('"payments.create"'));
      expect(user.email, 'acceptance.user.001@sistema.local');
      expect(user.role, UserRole.user);
      expect(user.activo, isTrue);
    },
  );

  test(
    'CLOUD_AUTHORITATIVE actualizacion de usuario envia permisos reemplazados',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      await configRepository.saveJwtToken('jwt-test-token');
      final systemConfigService = SystemConfigService.test(
        syncConfigRepository: configRepository,
      );
      var requestNumber = 0;
      String? updateBody;
      final backendClient = BackendApiClient(
        syncConfigRepository: configRepository,
        client: MockClient((request) async {
          requestNumber += 1;
          expect(request.headers['authorization'], 'Bearer jwt-test-token');
          if (requestNumber == 1) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/business/users');
            return http.Response(
              '{"data":{"user":{"id":"remote-user-edit","email":"qa.permissions@sistema.local","name":"QA-PERMISSIONS-USER","role":"TECH","active":true,"companyId":"company-1","permissions":["clients.read","sales.read","payments.create","payments.read"]}}}',
              201,
              headers: {'content-type': 'application/json'},
            );
          }

          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/business/users/remote-user-edit');
          updateBody = request.body;
          return http.Response(
            '{"data":{"user":{"id":"remote-user-edit","email":"qa.permissions@sistema.local","name":"QA-PERMISSIONS-USER","role":"TECH","active":true,"companyId":"company-1","permissions":["clients.read","lots.read","payments.read","sales.read","sales.update"]}}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        apiClient: backendClient,
        systemConfigService: systemConfigService,
      );

      final created = await authService.createUser(
        nombre: 'QA-PERMISSIONS-USER',
        email: 'qa.permissions@sistema.local',
        password: 'ValidPassword123',
        role: UserRole.user,
        permissions: const <PermissionModel>[
          PermissionModel(module: PermissionCatalog.clients, read: true),
          PermissionModel(module: PermissionCatalog.sales, read: true),
          PermissionModel(
            module: PermissionCatalog.payments,
            read: true,
            create: true,
          ),
        ],
      );
      final updated = await authService.updateUser(
        user: created,
        nombre: 'QA-PERMISSIONS-USER',
        email: 'qa.permissions@sistema.local',
        role: UserRole.user,
        active: true,
        permissions: const <PermissionModel>[
          PermissionModel(module: PermissionCatalog.clients, read: true),
          PermissionModel(module: PermissionCatalog.lots, read: true),
          PermissionModel(
            module: PermissionCatalog.sales,
            read: true,
            update: true,
          ),
          PermissionModel(module: PermissionCatalog.payments, read: true),
        ],
      );

      expect(updateBody, contains('"permissions"'));
      expect(updateBody, contains('"lots.read"'));
      expect(updateBody, contains('"sales.update"'));
      expect(updateBody, isNot(contains('"payments.create"')));
      expect(updated.permissionFor(PermissionCatalog.lots).read, isTrue);
      expect(updated.permissionFor(PermissionCatalog.sales).update, isTrue);
      expect(updated.permissionFor(PermissionCatalog.payments).create, isFalse);
    },
  );

  test(
    'CLOUD_AUTHORITATIVE no reporta exito si el backend ignora los permisos',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      await configRepository.saveJwtToken('jwt-test-token');
      final systemConfigService = SystemConfigService.test(
        syncConfigRepository: configRepository,
      );
      var requestNumber = 0;
      final backendClient = BackendApiClient(
        syncConfigRepository: configRepository,
        client: MockClient((request) async {
          requestNumber += 1;
          if (requestNumber == 1) {
            return http.Response(
              '{"data":{"user":{"id":"remote-user-skew","email":"qa.skew@sistema.local","name":"QA-SKEW","role":"TECH","active":true,"companyId":"company-1","permissions":["clients.read","payments.create","payments.read","sales.read"]}}}',
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"data":{"user":{"id":"remote-user-skew","email":"qa.skew@sistema.local","name":"QA-SKEW","role":"TECH","active":true,"companyId":"company-1"}}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        apiClient: backendClient,
        systemConfigService: systemConfigService,
      );

      final created = await authService.createUser(
        nombre: 'QA-SKEW',
        email: 'qa.skew@sistema.local',
        password: 'ValidPassword123',
        role: UserRole.user,
        permissions: const <PermissionModel>[
          PermissionModel(module: PermissionCatalog.clients, read: true),
          PermissionModel(module: PermissionCatalog.sales, read: true),
          PermissionModel(
            module: PermissionCatalog.payments,
            read: true,
            create: true,
          ),
        ],
      );

      await expectLater(
        authService.updateUser(
          user: created,
          nombre: 'QA-SKEW',
          email: 'qa.skew@sistema.local',
          role: UserRole.user,
          active: true,
          permissions: const <PermissionModel>[
            PermissionModel(module: PermissionCatalog.clients, read: true),
            PermissionModel(module: PermissionCatalog.lots, read: true),
          ],
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            'No se pudieron guardar todos los permisos. Intenta nuevamente.',
          ),
        ),
      );
    },
  );

  test(
    'CLOUD_AUTHORITATIVE no bloquea el guardado de OWNER sin filas directas',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      await configRepository.saveJwtToken('jwt-test-token');
      final systemConfigService = SystemConfigService.test(
        syncConfigRepository: configRepository,
      );
      final backendClient = BackendApiClient(
        syncConfigRepository: configRepository,
        client: MockClient((request) async {
          return http.Response(
            '{"data":{"user":{"id":"remote-owner-skew","email":"owner.skew@sistema.local","name":"OWNER-SKEW","role":"OWNER","active":true,"companyId":"company-1"}}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        apiClient: backendClient,
        systemConfigService: systemConfigService,
      );

      final owner = await authService.createUser(
        nombre: 'OWNER-SKEW',
        email: 'owner.skew@sistema.local',
        password: 'ValidPassword123',
        role: UserRole.admin,
        permissions: const <PermissionModel>[],
      );

      expect(owner.role, UserRole.admin);
      expect(
        owner.allows(PermissionCatalog.sales, PermissionAction.create),
        isTrue,
      );
    },
  );

  test(
    'CLOUD_AUTHORITATIVE no oculta acciones CRUD permitidas por candado local de equipo',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final backendState = FakeBackendState()
        ..initialized = true
        ..adminEmail = 'owner@sistema.local'
        ..adminPassword = 'CloudPassword123'
        ..adminFullName = 'Owner Cloud';
      final configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
      final systemConfigService = SystemConfigService.test(
        syncConfigRepository: configRepository,
      );
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
        systemConfigService: systemConfigService,
      );
      final authProvider = AuthProvider(
        authService: authService,
        systemConfigService: systemConfigService,
      );

      final signedIn = await authProvider.signIn(
        email: 'owner@sistema.local',
        password: 'CloudPassword123',
      );
      expect(signedIn, isTrue);

      systemConfigService.setDeviceWriteStateForTesting(
        canWrite: false,
        reason: 'device_not_registered',
      );

      expect(
        authProvider.canAccess(
          PermissionCatalog.clients,
          PermissionAction.create,
        ),
        isTrue,
      );
      expect(
        authProvider.canAccess(PermissionCatalog.lots, PermissionAction.update),
        isTrue,
      );
      expect(
        authProvider.canAccess(
          PermissionCatalog.sales,
          PermissionAction.delete,
        ),
        isTrue,
      );
      expect(
        authProvider.canAccess(
          PermissionCatalog.payments,
          PermissionAction.create,
        ),
        isTrue,
      );
    },
  );
}
