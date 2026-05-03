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
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('online_login_cache_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@gmail.com'
      ..adminPassword = 'Ayleen10'
      ..adminFullName = 'Admin Remoto';

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

  test('online login caches cloud user locally with remote identity', () async {
    final result = await authService.signInHybrid(
      email: 'Admin@gmail.com',
      password: 'Ayleen10',
    );

    expect(result.mode, AuthSignInMode.online);
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: [
        'email',
        'id_remote',
        'remote_auth_id',
        'auth_source',
        'sync_status',
        'password_hash',
      ],
      where: 'LOWER(email) = ?',
      whereArgs: ['admin@gmail.com'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['id_remote'], 'remote-admin-1');
    expect(rows.first['remote_auth_id'], 'remote-admin-1');
    expect(rows.first['auth_source'], 'cloud');
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusSynced);
    expect((rows.first['password_hash'] as String? ?? '').trim(), isNotEmpty);
  });
}
