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
import 'package:sistema_solares/features/auth/domain/user_model.dart';
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
}
