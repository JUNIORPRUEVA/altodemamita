import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync upload se bloquea si el device no esta autorizado para escribir', () async {
    final backendState = FakeBackendState()
      ..initialized = true
      ..seedAuthorizedDevice(deviceId: 'pc-principal', isPrimary: true, canWrite: true);
    final client = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    await expectLater(
      client.uploadQueuedRecords(
        settings: const SyncSettings(
          baseUrl: 'http://127.0.0.1:9999/api',
          jwtToken: 'jwt-test-token',
          queueRetryInterval: Duration(seconds: 10),
          realtimePollingInterval: Duration(seconds: 5),
          conflictStrategy: SyncConflictStrategy.manual,
          deviceId: 'pc-secundaria',
        ),
        recordsByScope: {
          'clients': [
            {'sync_id': 'client-1', 'name': 'Cliente Demo'},
          ],
        },
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('DEVICE_NOT_AUTHORIZED'),
        ),
      ),
    );
  });
}