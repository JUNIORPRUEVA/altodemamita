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
    tempDirectory = await Directory.systemTemp.createTemp('technician_modules_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'tecnico@test.local'
      ..adminPassword = 'Tecnico123'
      ..adminFullName = 'Tecnico Campo'
      ..authRoles = const ['SALES_AGENT']
      ..authPermissions = const [
        'clients.read',
        'products.read',
        'sellers.read',
        'sales.read',
        'payments.read',
        'installments.read',
        'reports.read',
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

  test('tecnico ve modulos permitidos y no recibe acceso indebido', () async {
    final result = await authService.signInHybrid(
      email: 'tecnico@test.local',
      password: 'Tecnico123',
    );

    expect(result.user.allows(PermissionCatalog.sales, PermissionAction.read), isTrue);
    expect(result.user.allows(PermissionCatalog.clients, PermissionAction.read), isTrue);
    expect(result.user.allows(PermissionCatalog.lots, PermissionAction.read), isTrue);
    expect(result.user.allows(PermissionCatalog.sellers, PermissionAction.read), isTrue);
    expect(result.user.allows(PermissionCatalog.dashboard, PermissionAction.read), isTrue);
    expect(result.user.allows(PermissionCatalog.settings, PermissionAction.read), isFalse);
    expect(result.user.allows(PermissionCatalog.settings, PermissionAction.update), isFalse);
  });
}