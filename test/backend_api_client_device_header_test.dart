import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authorized requests include x-device-id header', () async {
    final client = BackendApiClient(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        expect(request.headers['x-device-id'], 'device-123');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'ok': true},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      syncConfigRepository: _FakeSyncConfigRepository(),
    );

    final response = await client.get('/devices/current');

    expect(response, {'ok': true});
  });
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return const SyncSettings(
      baseUrl: 'https://example.test/api',
      jwtToken: 'jwt-token',
      queueRetryInterval: Duration(seconds: 10),
      realtimePollingInterval: Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.lastWriteWins,
      deviceId: 'device-123',
    );
  }
}
