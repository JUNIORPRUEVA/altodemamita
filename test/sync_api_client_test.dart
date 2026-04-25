import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('incluye users en el payload de upload y procesa el ack', () async {
    final backendState = FakeBackendState()..initialized = true;
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

  test('desempaqueta el envelope error en 409 y expone detalles del conflicto', () async {
    final backendState = FakeBackendState()
      ..initialized = true
      ..forceSyncUploadConflict = true
      ..wrapUploadConflictInErrorEnvelope = true;
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
            {
              'sync_id': 'installment-1',
              'version': 1,
            },
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
  });
}
