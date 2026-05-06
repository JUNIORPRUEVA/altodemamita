import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

class _FakeSyncConfigRepository extends SyncConfigRepository {
  _FakeSyncConfigRepository({
    required this.settings,
    required this.persistedState,
  });

  final SyncSettings settings;
  DeviceWriteState persistedState;
  DeviceWriteState? savedState;

  @override
  Future<SyncSettings> loadSettings() async => settings;

  @override
  Future<DeviceWriteState> loadDeviceWriteState() async => persistedState;

  @override
  Future<void> saveDeviceWriteState(DeviceWriteState state) async {
    savedState = state;
    persistedState = state;
  }
}

void main() {
  test(
    'refresh recovers desktop write access even if system config fails first',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        final path = request.uri.path;

        if (path == '/api/system/config') {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('{"success":false}');
          await request.response.close();
          return;
        }

        if (path == '/api/devices/current') {
          expect(request.headers.value('x-device-id'), 'pc-actual');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer jwt-test',
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'success': true,
              'data': {
                'deviceId': 'pc-actual',
                'isPrimary': true,
                'canWrite': true,
                'reason': 'authorized',
              },
            }),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final repository = _FakeSyncConfigRepository(
        settings: SyncSettings(
          baseUrl: 'http://${server.address.host}:${server.port}/api',
          jwtToken: 'jwt-test',
          queueRetryInterval: const Duration(seconds: 10),
          realtimePollingInterval: const Duration(seconds: 5),
          conflictStrategy: SyncConflictStrategy.manual,
          deviceId: 'pc-actual',
        ),
        persistedState: const DeviceWriteState(
          isPrimary: false,
          canWrite: false,
          lastValidatedAt: null,
          reason: 'Este equipo aun no esta registrado para escribir.',
        ),
      );

      final service = SystemConfigService.test(
        syncConfigRepository: repository,
        httpClient: HttpClient(),
      );

      await service.initialize();

      expect(service.canWrite, isTrue);
      expect(service.isPrimaryDevice, isTrue);
      expect(service.deviceWriteReason, isEmpty);
      expect(repository.savedState?.canWrite, isTrue);
      expect(repository.savedState?.isPrimary, isTrue);
    },
  );
}