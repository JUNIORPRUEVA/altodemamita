import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/settings/data/payment_reminder_settings_repository.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads notification config from cloud admin endpoint', () async {
    final client = BackendApiClient(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://example.test/api/payment-reminders/admin');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        return _adminResponse(enabled: true);
      }),
      syncConfigRepository: _FakeSyncConfigRepository(),
    );

    final repository = PaymentReminderSettingsRepository(apiClient: client);

    final state = await repository.load();

    expect(state.config.notificationsEnabled, isTrue);
    expect(state.config.effectiveEnabled, isFalse);
  });

  test('successful cloud load stores cache and overrides older cached value', () async {
    SharedPreferences.setMockInitialValues({
      'payment_reminders.admin_state.cache': jsonEncode(
        _adminPayload(enabled: false),
      ),
    });
    final client = BackendApiClient(
      client: MockClient((request) async => _adminResponse(enabled: true)),
      syncConfigRepository: _FakeSyncConfigRepository(),
    );
    final repository = PaymentReminderSettingsRepository(apiClient: client);

    expect((await repository.loadCached())?.config.notificationsEnabled, isFalse);

    final cloud = await repository.load();
    final cachedAfterCloud = await repository.loadCached();

    expect(cloud.config.notificationsEnabled, isTrue);
    expect(cachedAfterCloud?.config.notificationsEnabled, isTrue);
  });

  test('toggle update requires server readback to match requested value', () async {
    final methods = <String>[];
    final client = BackendApiClient(
      client: MockClient((request) async {
        methods.add(request.method);
        if (request.method == 'PATCH') {
          expect(jsonDecode(request.body), {'notificationsEnabled': true});
          return _adminResponse(enabled: true);
        }
        return _adminResponse(enabled: true);
      }),
      syncConfigRepository: _FakeSyncConfigRepository(),
    );

    final repository = PaymentReminderSettingsRepository(apiClient: client);

    final state = await repository.setNotificationsEnabled(true);

    expect(state.config.notificationsEnabled, isTrue);
    expect(methods, ['PATCH', 'GET']);
  });

  test('toggle update rejects false success when readback differs', () async {
    var calls = 0;
    final client = BackendApiClient(
      client: MockClient((request) async {
        calls += 1;
        return _adminResponse(enabled: calls == 1);
      }),
      syncConfigRepository: _FakeSyncConfigRepository(),
    );

    final repository = PaymentReminderSettingsRepository(apiClient: client);

    await expectLater(
      repository.setNotificationsEnabled(true),
      throwsA(isA<BackendApiException>()),
    );
  });
}

http.Response _adminResponse({required bool enabled}) {
  return http.Response(
    jsonEncode({
      'data': _adminPayload(enabled: enabled),
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _adminPayload({required bool enabled}) {
  return {
    'config': {
      'notificationsEnabled': enabled,
      'effectiveEnabled': false,
      'senderWhatsAppNumber': '',
      'editableMessageFragment':
          'Te recordamos que tienes cuotas vencidas pendientes de pago.',
      'maxMessageFragmentLength': 250,
      'templateLocked': true,
      'activeTemplateName': 'recordatorio_cuotas_vencidas_profesional5',
      'testTemplateName': 'recordatorio_cuotas_vencidas_profesional5',
      'templateLanguage': 'es',
    },
    'system': {
      'deliveryGateEnabled': false,
      'emergencyStop': true,
      'dryRun': true,
      'testMode': true,
      'allowRealRecipients': false,
      'whatsappConfigured': false,
      'displayWhatsappConfigured': false,
      'whatsappPhoneNumberId': '',
      'whatsappBusinessAccountId': '',
      'schedule': {
        'timezone': 'America/Santo_Domingo',
        'allowedDays': '1,2,3,4,5,6',
        'startHour': 9,
        'endHour': 17,
      },
      'runFrequency': 'Corre una vez al dia.',
      'retryPolicy': 'Reintenta sin duplicar.',
      'recipientPolicy': 'Modo prueba activo.',
      'duplicatePolicy': 'Evita duplicados.',
      'templatePolicy': 'Plantillas aprobadas.',
    },
    'template': {
      'locked': true,
      'editableFields': [],
      'preview': 'Hola Cliente.',
    },
    'candidates': {
      'totalSales': 0,
      'activeSales': 0,
      'overdueSales': 0,
      'withValidPhone': 0,
      'blockedWithoutPhone': 0,
      'totalOverdueInstallments': 0,
      'totalDue': '0.00',
      'preview': [],
    },
    'stats': {
      'sent': 0,
      'delivered': 0,
      'read': 0,
      'failed': 0,
      'pending': 0,
      'dryRun': 0,
    },
    'history': [],
  };
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
