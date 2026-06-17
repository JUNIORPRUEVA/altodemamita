import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
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
    tempDirectory = await Directory.systemTemp.createTemp('offline_login_clean_msg_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = FakeBackendState()..offline = true;

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

  test('offline first login without local user shows clean non-technical message', () async {
    await expectLater(
      authService.signInHybrid(
        email: ' Admin@gmail.com ',
        password: 'Ayleen10',
      ),
      throwsA(
        isA<AuthException>()
            .having(
              (error) => error.message,
              'message',
              AuthService.firstConnectionRequiredMessage,
            )
            .having(
              (error) => error.message.toLowerCase(),
              'notWrongPasswordMessage',
              isNot(contains('contrasena incorrecta')),
            ),
      ),
    );
  });
}
