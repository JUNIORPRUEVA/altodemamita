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
    tempDirectory = await Directory.systemTemp.createTemp('online_hash_non_empty_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()
      ..initialized = true
      ..adminEmail = 'admin@gmail.com'
      ..adminPassword = 'Ayleen10'
      ..adminFullName = 'Admin Real';

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

  test('online login stores non-empty local password hash', () async {
    await authService.signInHybrid(
      email: 'Admin@gmail.com',
      password: 'Ayleen10',
    );

    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['email', 'password_hash', 'last_online_login_at'],
      where: 'LOWER(email) = ?',
      whereArgs: ['admin@gmail.com'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect((rows.first['password_hash'] as String? ?? '').trim(), isNotEmpty);
    expect((rows.first['last_online_login_at'] as String? ?? '').trim(), isNotEmpty);
  });
}
