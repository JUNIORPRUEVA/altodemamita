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
    tempDirectory = await Directory.systemTemp.createTemp('admin_modules_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@test.local'
      ..adminPassword = 'AdminSegura123'
      ..adminFullName = 'Admin Remoto'
      ..authRoles = const ['SUPER_ADMIN']
      ..authPermissions = const [
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

  test('admin conserva acceso de lectura a todos los modulos offline', () async {
    final result = await authService.signInHybrid(
      email: 'admin@test.local',
      password: 'AdminSegura123',
    );

    for (final module in PermissionCatalog.modules) {
      expect(
        result.user.allows(module.key, PermissionAction.read),
        isTrue,
        reason: 'Expected read access for ${module.key}',
      );
    }
  });
}