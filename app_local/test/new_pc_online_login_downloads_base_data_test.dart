import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late FakeBackendState backendState;
  late FakeSyncConfigRepository configRepository;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('new_pc_online_base_data_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@test.local'
      ..adminPassword = 'AdminSegura123'
      ..adminFullName = 'Admin Remoto';
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

  test('PC nueva con internet guarda sesion base y usuario local tras login nube', () async {
    final result = await authService.signInHybrid(
      email: 'admin@test.local',
      password: 'AdminSegura123',
    );

    expect(result.mode, AuthSignInMode.online);
    expect(result.syncTriggered, isTrue);
    expect(configRepository.savedJwtToken, 'jwt-test-token');

    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['email', 'password_hash', 'remote_auth_id'],
      where: 'LOWER(email) = ?',
      whereArgs: ['admin@test.local'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect((rows.first['password_hash'] as String? ?? '').trim(), isNotEmpty);
    expect(rows.first['remote_auth_id'], 'remote-admin-1');
  });
}