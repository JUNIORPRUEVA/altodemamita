import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recoveryCode = 'ABCD-EFGH-JKLM-NPQR';

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late AuthService authService;
  late AuthProvider authProvider;
  late FakeBackendState backendState;
  late FakeSyncConfigRepository configRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_auth_provider_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState();
    configRepository = FakeSyncConfigRepository(
      settings: buildFakeSettings(),
    );

    authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: configRepository,
      httpClient: FakeBackendHttpClient(state: backendState),
    );
    authProvider = AuthProvider(authService: authService);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('cierra la sesion al refrescar un usuario desactivado', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final createdUser = await authService.createUser(
      nombre: 'Operador Caja',
      email: 'caja@local.test',
      password: 'CajaSegura123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(module: PermissionCatalog.payments, read: true),
      ],
    );

    await configRepository.saveBaseUrl('http://invalid.invalid/api');

    final signedIn = await authProvider.signIn(
      email: 'caja@local.test',
      password: 'CajaSegura123',
    );

    expect(signedIn, isTrue);
    expect(authProvider.currentUser?.id, createdUser.id);

    await authService.setUserActive(
      user: authProvider.currentUser!,
      active: false,
    );
    await authProvider.refreshCurrentUser();

    expect(authProvider.currentUser, isNull);
    expect(authProvider.isAuthenticated, isFalse);
  });

  test('consulta las credenciales del admin sin iniciar sesion', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final credentials = await authProvider.revealAdminCredentials(
      recoveryCode: recoveryCode,
    );

    expect(credentials, isNotNull);
    expect(credentials?.email, 'admin@local.test');
    expect(credentials?.password, 'AdminLocalSegura123');
    expect(authProvider.isAuthenticated, isFalse);
  });

  test('acepta iniciar sesion con nombre de usuario', () async {
    await authService.completeInitialSetup(
      nombre: 'Programador',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    await configRepository.saveBaseUrl('http://invalid.invalid/api');

    final signedIn = await authProvider.signIn(
      email: 'programador',
      password: ' AdminLocalSegura123 ',
    );

    expect(signedIn, isTrue);
    expect(authProvider.currentUser?.email, 'admin@local.test');
  });
}
