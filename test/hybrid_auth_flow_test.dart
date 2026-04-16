import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recoveryCode = 'ABCD-EFGH-JKLM-NPQR';

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late HttpServer server;
  late _FakeBackendState backendState;
  late _FakeSyncConfigRepository configRepository;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_hybrid_auth_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();

    backendState = _FakeBackendState();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _startFakeBackend(server, backendState);

    configRepository = _FakeSyncConfigRepository(
      settings: SyncSettings(
        baseUrl: 'http://127.0.0.1:${server.port}',
        jwtToken: '',
        queueRetryInterval: const Duration(seconds: 10),
        realtimePollingInterval: const Duration(seconds: 5),
        conflictStrategy: SyncConflictStrategy.manual,
        deviceId: 'test-device',
      ),
    );

    authService = AuthService(
      appDatabase: appDatabase,
      syncConfigRepository: configRepository,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'configura remoto, inicia online y luego permite login offline',
    () async {
      final bootstrap = await authService.bootstrap();

      expect(bootstrap.requiresInitialSetup, isTrue);
      expect(bootstrap.isOnline, isTrue);
      expect(bootstrap.isCloudInitialized, isFalse);

      await authService.completeInitialSetup(
        companyName: 'Sistema Test',
        nombre: 'Admin General',
        email: 'admin@test.local',
        password: 'AdminSegura123',
        recoveryCode: recoveryCode,
      );

      expect(backendState.initialized, isTrue);
      expect(configRepository.savedJwtToken, isNotEmpty);
      expect(await authService.requiresInitialSetup(), isFalse);

      final onlineResult = await authService.signInHybrid(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );

      expect(onlineResult.mode, AuthSignInMode.online);
      expect(onlineResult.user.email, 'admin@test.local');

      await server.close(force: true);

      final offlineUser = await authService.loginOffline(
        email: 'admin@test.local',
        password: 'AdminSegura123',
      );

      expect(offlineUser.email, 'admin@test.local');
    },
  );
}

class _FakeBackendState {
  bool initialized = false;
  String companyName = '';
  String adminEmail = '';
  String adminPassword = '';
  String adminFullName = '';
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  _FakeSyncConfigRepository({required SyncSettings settings})
    : _settings = settings;

  SyncSettings _settings;
  String savedJwtToken = '';

  @override
  Future<SyncSettings> loadSettings() async => _settings;

  @override
  Future<void> saveJwtToken(String jwtToken) async {
    savedJwtToken = jwtToken;
    _settings = SyncSettings(
      baseUrl: _settings.baseUrl,
      jwtToken: jwtToken,
      queueRetryInterval: _settings.queueRetryInterval,
      realtimePollingInterval: _settings.realtimePollingInterval,
      conflictStrategy: _settings.conflictStrategy,
      deviceId: _settings.deviceId,
    );
  }

  @override
  Future<void> clearJwtToken() async {
    savedJwtToken = '';
    _settings = SyncSettings(
      baseUrl: _settings.baseUrl,
      jwtToken: '',
      queueRetryInterval: _settings.queueRetryInterval,
      realtimePollingInterval: _settings.realtimePollingInterval,
      conflictStrategy: _settings.conflictStrategy,
      deviceId: _settings.deviceId,
    );
  }
}

void _startFakeBackend(HttpServer server, _FakeBackendState state) {
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    final body = await utf8.decoder.bind(request).join();
    final payload = body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;

    if (request.method == 'GET' && request.uri.path == '/system/status') {
      request.response.write(
        jsonEncode({
          'success': true,
          'data': {'initialized': state.initialized},
        }),
      );
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/system/setup') {
      final company = payload['company'] as Map<String, dynamic>? ?? const {};
      final admin = payload['admin'] as Map<String, dynamic>? ?? const {};
      state.initialized = true;
      state.companyName = company['name']?.toString() ?? '';
      state.adminEmail = admin['email']?.toString() ?? '';
      state.adminPassword = admin['password']?.toString() ?? '';
      state.adminFullName = admin['fullName']?.toString() ?? '';

      request.response.write(
        jsonEncode({
          'success': true,
          'data': {
            'initialized': true,
            'company': {'name': state.companyName},
          },
        }),
      );
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/auth/login') {
      final identifier = payload['identifier']?.toString().trim().toLowerCase();
      final password = payload['password']?.toString() ?? '';
      if (!state.initialized ||
          identifier != state.adminEmail.toLowerCase() ||
          password != state.adminPassword) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode({
            'success': false,
            'message': 'Credenciales inválidas.',
          }),
        );
        await request.response.close();
        return;
      }

      request.response.write(
        jsonEncode({
          'success': true,
          'data': {
            'accessToken': 'jwt-test-token',
            'user': {
              'sub': 'remote-admin-1',
              'email': state.adminEmail,
              'username': 'admin.general',
              'fullName': state.adminFullName,
              'isActive': true,
              'roles': ['SUPER_ADMIN'],
              'permissions': ['sync.manage', 'users.write', 'users.read'],
            },
          },
        }),
      );
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write(jsonEncode({'success': false, 'message': 'Not found'}));
    await request.response.close();
  });
}