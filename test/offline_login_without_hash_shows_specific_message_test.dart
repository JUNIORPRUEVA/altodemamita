import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('offline_without_hash_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();
    authService = AuthService(appDatabase: appDatabase);

    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.usersTable, {
      'sync_id': 'user-no-hash',
      'nombre': 'Admin Sin Hash',
      'email': 'admin@gmail.com',
      'password_hash': '',
      'password_reset_required': 0,
      'rol': 'admin',
      'activo': 1,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('offline login with empty hash shows specific message', () async {
    await expectLater(
      authService.signInHybrid(
        email: 'Admin@gmail.com',
        password: 'Ayleen10',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          AuthService.localCredentialsMissingMessage,
        ),
      ),
    );
  });
}
