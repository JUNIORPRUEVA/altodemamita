import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('incluye users en el payload de upload y procesa el ack', () async {
    final backendState = FakeBackendState()..initialized = true;
    backendState.seedAuthorizedDevice(
      deviceId: 'test-device',
      isPrimary: true,
      canWrite: true,
    );
    final client = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    final response = await client.uploadQueuedRecords(
      settings: const SyncSettings(
        baseUrl: 'http://127.0.0.1:9999/api',
        jwtToken: 'jwt-test-token',
        queueRetryInterval: Duration(seconds: 10),
        realtimePollingInterval: Duration(seconds: 5),
        conflictStrategy: SyncConflictStrategy.manual,
        deviceId: 'test-device',
      ),
      recordsByScope: {
        'users': [
          {
            'sync_id': 'user-1',
            'email': 'admin@local.test',
            'full_name': 'Admin General',
            'role': 'admin',
          },
        ],
      },
    );

    final uploadedRecords =
        backendState.lastSyncUploadPayload['records'] as Map<String, dynamic>;

    expect(uploadedRecords['users'], isA<List>());
    expect((uploadedRecords['users'] as List).length, 1);
    expect(response.recordsForScope('users'), hasLength(1));
    expect(response.recordsForScope('users').first['sync_id'], 'user-1');
  });

  test(
    'desempaqueta el envelope error en 409 y expone detalles del conflicto',
    () async {
      final backendState = FakeBackendState()
        ..initialized = true
        ..forceSyncUploadConflict = true
        ..wrapUploadConflictInErrorEnvelope = true;
      backendState.seedAuthorizedDevice(
        deviceId: 'test-device',
        isPrimary: true,
        canWrite: true,
      );
      final client = SyncApiClient(
        httpClient: FakeBackendHttpClient(state: backendState),
      );

      final settings = const SyncSettings(
        baseUrl: 'http://127.0.0.1:9999/api',
        jwtToken: 'jwt-test-token',
        queueRetryInterval: Duration(seconds: 10),
        realtimePollingInterval: Duration(seconds: 5),
        conflictStrategy: SyncConflictStrategy.manual,
        deviceId: 'test-device',
      );

      try {
        await client.uploadQueuedRecords(
          settings: settings,
          recordsByScope: {
            'installments': [
              {'sync_id': 'installment-1', 'version': 1},
            ],
          },
        );
        fail('Expected SyncConflictException');
      } on SyncConflictException catch (error) {
        expect(error.scope, 'installments');
        expect(error.message, 'Conflicto de version detectado.');
        expect(error.conflicts, hasLength(1));
        expect(error.conflicts.first.recordSyncId, 'installment-1');
        expect(error.conflicts.first.serverVersion, 2);
        expect(error.returnedRecords, hasLength(1));
        expect(error.returnedRecords.first['sync_id'], 'installment-1');
      }
    },
  );

  test('401 de sync no se reporta como cloud no configurado', () async {
    final backendState = FakeBackendState()
      ..initialized = true
      ..rejectSyncDownloadUnauthorized = true;
    final client = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    await expectLater(
      client.downloadChanges(
        settings: _settings(),
        updatedSinceByScope: const <String, DateTime?>{},
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          'Correo o contrasena incorrectos.',
        ),
      ),
    );
  });

  test('403 de sync no se reporta como cloud no configurado', () async {
    final backendState = FakeBackendState()
      ..initialized = true
      ..rejectSyncDownloadForbidden = true;
    final client = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    await expectLater(
      client.downloadChanges(
        settings: _settings(),
        updatedSinceByScope: const <String, DateTime?>{},
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          'No tienes permiso para acceder.',
        ),
      ),
    );
  });

  test('5xx de sync no se reporta como cloud no configurado', () async {
    final backendState = FakeBackendState()
      ..initialized = true
      ..rejectSyncDownloadServerError = true;
    final client = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    await expectLater(
      client.downloadChanges(
        settings: _settings(),
        updatedSinceByScope: const <String, DateTime?>{},
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          'El servicio no esta disponible temporalmente.',
        ),
      ),
    );
  });
}

SyncSettings _settings() {
  return const SyncSettings(
    baseUrl: 'http://127.0.0.1:9999/api',
    jwtToken: 'jwt-test-token',
    queueRetryInterval: Duration(seconds: 10),
    realtimePollingInterval: Duration(seconds: 5),
    conflictStrategy: SyncConflictStrategy.manual,
    deviceId: 'test-device',
  );
}
