import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync download sigue permitido aunque el device no tenga permiso de escritura', () async {
    final backendState = FakeBackendState()
      ..initialized = true
      ..seedAuthorizedDevice(deviceId: 'pc-principal', isPrimary: true, canWrite: true)
      ..seedAuthorizedDevice(deviceId: 'pc-secundaria', isPrimary: false, canWrite: false);
    final client = SyncApiClient(
      httpClient: FakeBackendHttpClient(state: backendState),
    );

    final response = await client.downloadChanges(
      settings: const SyncSettings(
        baseUrl: 'http://127.0.0.1:9999/api',
        jwtToken: 'jwt-test-token',
        queueRetryInterval: Duration(seconds: 10),
        realtimePollingInterval: Duration(seconds: 5),
        conflictStrategy: SyncConflictStrategy.manual,
        deviceId: 'pc-secundaria',
      ),
    );

    expect(response.supportsScope('users'), isTrue);
    expect(response.supportsScope('clients'), isTrue);
  });
}