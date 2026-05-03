import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recoveryCode = 'ABCD-EFGH-JKLM-NPQR';

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late FakeBackendState backendState;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('auth_dedup_email_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'cloud.user@test.local'
      ..adminPassword = 'CloudPass123'
      ..adminFullName = 'Cloud User';

    authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: FakeSyncConfigRepository(settings: buildFakeSettings()),
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    await authService.completeInitialSetup(
      nombre: 'Admin Local',
      email: 'admin@local.test',
      password: 'AdminLocal123',
      recoveryCode: recoveryCode,
    );

    await authService.createUser(
      nombre: 'Usuario Local',
      email: 'cloud.user@test.local',
      password: 'LocalOnly123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(module: PermissionCatalog.clients, read: true),
      ],
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('cloud login links existing local user by email without duplicates', () async {
    final result = await authService.signInHybrid(
      email: 'cloud.user@test.local',
      password: 'CloudPass123',
    );

    expect(result.mode, AuthSignInMode.online);
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'LOWER(email) = ?',
      whereArgs: ['cloud.user@test.local'],
    );

    expect(rows, hasLength(1));
    expect(rows.first['id_remote'], 'remote-admin-1');
    expect(rows.first['remote_auth_id'], 'remote-admin-1');
  });
}
