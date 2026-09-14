import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/settings/data/payment_reminder_settings_repository.dart';
import 'package:sistema_solares/features/settings/presentation/payment_reminder_settings_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('slow cloud load longer than old timeout still replaces fallback', (
    tester,
  ) async {
    final repository = _FakePaymentReminderSettingsRepository(
      loadState: _state(enabled: true),
      loadDelay: const Duration(seconds: 9),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(seconds: 8));

    expect(
      find.text('No pudimos actualizar. Mostrando datos guardados.'),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 2));

    final reminderSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(reminderSwitch.value, isTrue);
    expect(find.text('Pausado por seguridad'), findsOneWidget);
  });

  testWidgets('401 load error shows expired session instead of offline cache', (
    tester,
  ) async {
    final repository = _FakePaymentReminderSettingsRepository(
      loadError: const BackendApiException('No autorizado.', statusCode: 401),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('La sesion expiro. Inicia sesion nuevamente.'), findsOneWidget);
    expect(
      find.text('No pudimos actualizar. Mostrando datos guardados.'),
      findsNothing,
    );
  });

  testWidgets('cached state is visible until cloud state replaces it', (
    tester,
  ) async {
    final repository = _FakePaymentReminderSettingsRepository(
      cachedState: _state(enabled: false),
      loadState: _state(enabled: true),
      loadDelay: const Duration(seconds: 1),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.pump(const Duration(seconds: 2));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('toggle disables switch while saving and uses readback state', (
    tester,
  ) async {
    final repository = _FakePaymentReminderSettingsRepository(
      loadState: _state(enabled: false),
      toggleState: _state(enabled: true),
      toggleDelay: const Duration(seconds: 2),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    final savingSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(savingSwitch.onChanged, isNull);

    await tester.pump(const Duration(seconds: 3));

    final savedSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(savedSwitch.value, isTrue);
    expect(repository.requestedEnabledValues, [true]);
  });
}

Widget _app(PaymentReminderSettingsRepository repository) {
  return MaterialApp(
    home: PaymentReminderSettingsMobilePage(repository: repository),
  );
}

PaymentReminderAdminState _state({required bool enabled}) {
  return PaymentReminderAdminState(
    config: PaymentReminderConfig(
      notificationsEnabled: enabled,
      effectiveEnabled: false,
      senderWhatsAppNumber: '',
      editableMessageFragment:
          'Te recordamos que tienes cuotas vencidas pendientes de pago.',
      maxMessageFragmentLength: 250,
      templateLocked: true,
      activeTemplateName: 'recordatorio_cuotas_vencidas_profesional5',
      testTemplateName: 'recordatorio_cuotas_vencidas_profesional5',
      templateLanguage: 'es',
    ),
    system: const PaymentReminderSystemState(
      deliveryGateEnabled: false,
      emergencyStop: true,
      dryRun: true,
      testMode: true,
      allowRealRecipients: false,
      whatsappConfigured: false,
      displayWhatsappConfigured: false,
      whatsappPhoneNumberId: '',
      whatsappBusinessAccountId: '',
      schedule: PaymentReminderSchedule(
        timezone: 'America/Santo_Domingo',
        allowedDays: '1,2,3,4,5,6',
        startHour: 9,
        endHour: 17,
      ),
      runFrequency: 'Corre una vez al dia.',
      retryPolicy: 'Reintenta sin duplicar.',
      recipientPolicy: 'Modo prueba activo.',
      duplicatePolicy: 'Evita duplicados.',
      templatePolicy: 'Plantillas aprobadas.',
    ),
    template: const PaymentReminderTemplateState(
      locked: true,
      editableFields: [],
      preview: 'Hola Cliente.',
    ),
    candidates: const PaymentReminderCandidateSummary(
      totalSales: 0,
      activeSales: 0,
      overdueSales: 0,
      withValidPhone: 0,
      blockedWithoutPhone: 0,
      totalOverdueInstallments: 0,
      totalDue: '0.00',
      preview: [],
    ),
    stats: const PaymentReminderStats(
      sent: 0,
      delivered: 0,
      read: 0,
      failed: 0,
      pending: 0,
      dryRun: 0,
    ),
    history: const [],
  );
}

class _FakePaymentReminderSettingsRepository
    extends PaymentReminderSettingsRepository {
  _FakePaymentReminderSettingsRepository({
    this.cachedState,
    PaymentReminderAdminState? loadState,
    PaymentReminderAdminState? toggleState,
    this.loadError,
    this.loadDelay = Duration.zero,
    this.toggleDelay = Duration.zero,
  }) : loadState = loadState ?? _state(enabled: false),
       toggleState = toggleState ?? loadState ?? _state(enabled: false);

  final PaymentReminderAdminState? cachedState;
  final PaymentReminderAdminState loadState;
  final PaymentReminderAdminState toggleState;
  final Object? loadError;
  final Duration loadDelay;
  final Duration toggleDelay;
  final requestedEnabledValues = <bool>[];

  @override
  Future<PaymentReminderAdminState?> loadCached() async {
    return cachedState;
  }

  @override
  Future<PaymentReminderAdminState> load() async {
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return loadState;
  }

  @override
  Future<PaymentReminderAdminState> setNotificationsEnabled(
    bool requestedEnabled,
  ) async {
    requestedEnabledValues.add(requestedEnabled);
    if (toggleDelay > Duration.zero) {
      await Future<void>.delayed(toggleDelay);
    }
    return toggleState;
  }
}
