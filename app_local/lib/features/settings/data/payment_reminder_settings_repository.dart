import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/backend_api_client.dart';

class PaymentReminderSettingsRepository {
  PaymentReminderSettingsRepository({
    BackendApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesFactory,
  }) : _apiClient = apiClient ?? BackendApiClient(),
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  final BackendApiClient _apiClient;
  final Future<SharedPreferences> Function() _preferencesFactory;
  static const _cacheKey = 'payment_reminders.admin_state.cache';

  Future<PaymentReminderAdminState> load() async {
    final response = await _apiClient.get('/payment-reminders/admin');
    final data = _unwrapData(response);
    await _saveCache(data);
    return PaymentReminderAdminState.fromApi(data);
  }

  Future<PaymentReminderAdminState?> loadCached() async {
    try {
      final preferences = await _preferencesFactory();
      final cached = preferences.getString(_cacheKey);
      if (cached == null || cached.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(cached);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return PaymentReminderAdminState.fromApi(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<PaymentReminderAdminState> save({
    bool? notificationsEnabled,
    String? senderWhatsAppNumber,
    String? editableMessageFragment,
  }) async {
    final body = <String, dynamic>{};
    if (notificationsEnabled != null) {
      body['notificationsEnabled'] = notificationsEnabled;
    }
    if (senderWhatsAppNumber != null) {
      body['senderWhatsAppNumber'] = senderWhatsAppNumber;
    }
    if (editableMessageFragment != null) {
      body['editableMessageFragment'] = editableMessageFragment;
    }
    final response = await _apiClient.patch(
      '/payment-reminders/admin',
      body: body,
    );
    final data = _unwrapData(response);
    await _saveCache(data);
    return PaymentReminderAdminState.fromApi(data);
  }

  Future<PaymentReminderAdminState> setNotificationsEnabled(
    bool requestedEnabled,
  ) async {
    final saved = await save(notificationsEnabled: requestedEnabled);
    if (saved.config.notificationsEnabled != requestedEnabled) {
      throw const BackendApiException(
        'No pudimos guardar el cambio. Intenta nuevamente.',
      );
    }

    final readBack = await load();
    if (readBack.config.notificationsEnabled != requestedEnabled) {
      throw const BackendApiException(
        'No pudimos guardar el cambio. Intenta nuevamente.',
      );
    }
    return readBack;
  }

  Future<void> _saveCache(Map<String, dynamic> data) async {
    try {
      final preferences = await _preferencesFactory();
      await preferences.setString(_cacheKey, jsonEncode(data));
    } catch (_) {
      // Cache is secondary only; cloud remains authoritative.
    }
  }

  Map<String, dynamic> _unwrapData(dynamic response) {
    if (response is Map<String, dynamic>) {
      final data = response['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return response;
    }
    throw const BackendApiException('Respuesta de recordatorios invalida.');
  }
}

class PaymentReminderAdminState {
  const PaymentReminderAdminState({
    required this.config,
    required this.system,
    required this.template,
    required this.candidates,
    required this.stats,
    required this.history,
    this.lastRun,
  });

  final PaymentReminderConfig config;
  final PaymentReminderSystemState system;
  final PaymentReminderTemplateState template;
  final PaymentReminderCandidateSummary candidates;
  final PaymentReminderStats stats;
  final PaymentReminderLastRun? lastRun;
  final List<PaymentReminderHistoryItem> history;

  factory PaymentReminderAdminState.fromApi(Map<String, dynamic> map) {
    return PaymentReminderAdminState(
      config: PaymentReminderConfig.fromApi(_map(map['config'])),
      system: PaymentReminderSystemState.fromApi(_map(map['system'])),
      template: PaymentReminderTemplateState.fromApi(_map(map['template'])),
      candidates: PaymentReminderCandidateSummary.fromApi(
        _map(map['candidates']),
      ),
      stats: PaymentReminderStats.fromApi(_map(map['stats'])),
      lastRun: map['lastRun'] is Map
          ? PaymentReminderLastRun.fromApi(_map(map['lastRun']))
          : null,
      history: _list(map['history'])
          .map((item) => PaymentReminderHistoryItem.fromApi(_map(item)))
          .toList(growable: false),
    );
  }

  factory PaymentReminderAdminState.fallback() {
    const message =
        'Te recordamos que tienes cuotas vencidas pendientes de pago.';
    return PaymentReminderAdminState(
      config: const PaymentReminderConfig(
        notificationsEnabled: false,
        effectiveEnabled: false,
        senderWhatsAppNumber: '',
        editableMessageFragment: message,
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
        whatsappPhoneNumberId: 'No cargado',
        whatsappBusinessAccountId: 'No cargado',
        schedule: PaymentReminderSchedule(
          timezone: 'America/Santo_Domingo',
          allowedDays: '1,2,3,4,5,6',
          startHour: 9,
          endHour: 17,
        ),
        runFrequency:
            'Corre una vez al dia cuando el backend de recordatorios esta activo.',
        retryPolicy:
            'Si falla la carga, reintenta con el boton actualizar. Los envios fallidos quedan registrados en el servidor cuando el backend responde.',
        recipientPolicy:
            'El sistema envia solo a clientes con venta activa, cuotas vencidas y telefono WhatsApp valido. En modo prueba redirige a numeros autorizados.',
        duplicatePolicy:
            'El backend evita duplicar el mismo recordatorio para la misma venta, periodo y ultima cuota vencida.',
        templatePolicy:
            'WhatsApp solo permite plantillas aprobadas en Meta. Desde aqui se editan los valores administrables; cambiar el cuerpo fijo requiere aprobar otra plantilla.',
      ),
      template: PaymentReminderTemplateState(
        locked: true,
        editableFields: const [
          PaymentReminderTemplateField(
            key: 'editableMessageFragment',
            label: 'Mensaje administrativo',
            value: message,
            editable: true,
          ),
          PaymentReminderTemplateField(
            key: 'lotLabel',
            label: 'Solar vendido',
            value: 'Se calcula desde la venta',
            editable: false,
          ),
          PaymentReminderTemplateField(
            key: 'installmentDetails',
            label: 'Cuotas vencidas, capital y mora',
            value: 'Se calcula desde cuotas y pagos',
            editable: false,
          ),
          PaymentReminderTemplateField(
            key: 'totalDue',
            label: 'Total pendiente',
            value: 'Se calcula con la mora configurada en el backend',
            editable: false,
          ),
        ],
        preview:
            'Hola Cliente.\n\n$message\n\nSolar: M8-S24\nCuotas vencidas: 2\nDetalle: cuota mayo 2026 RD\$8,415.14 + mora RD\$2,524.54\nTotal vencido: RD\$21,879.36',
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
}

class PaymentReminderConfig {
  const PaymentReminderConfig({
    required this.notificationsEnabled,
    required this.effectiveEnabled,
    required this.senderWhatsAppNumber,
    required this.editableMessageFragment,
    required this.maxMessageFragmentLength,
    required this.templateLocked,
    required this.activeTemplateName,
    required this.testTemplateName,
    required this.templateLanguage,
  });

  final bool notificationsEnabled;
  final bool effectiveEnabled;
  final String senderWhatsAppNumber;
  final String editableMessageFragment;
  final int maxMessageFragmentLength;
  final bool templateLocked;
  final String activeTemplateName;
  final String testTemplateName;
  final String templateLanguage;

  factory PaymentReminderConfig.fromApi(Map<String, dynamic> map) {
    return PaymentReminderConfig(
      notificationsEnabled: map['notificationsEnabled'] == true,
      effectiveEnabled: map['effectiveEnabled'] == true,
      senderWhatsAppNumber: _text(map['senderWhatsAppNumber']),
      editableMessageFragment: _text(map['editableMessageFragment']),
      maxMessageFragmentLength:
          int.tryParse('${map['maxMessageFragmentLength'] ?? ''}') ?? 250,
      templateLocked: map['templateLocked'] != false,
      activeTemplateName: _text(map['activeTemplateName']),
      testTemplateName: _text(map['testTemplateName']),
      templateLanguage: _text(map['templateLanguage']),
    );
  }
}

class PaymentReminderSystemState {
  const PaymentReminderSystemState({
    required this.deliveryGateEnabled,
    required this.emergencyStop,
    required this.dryRun,
    required this.testMode,
    required this.allowRealRecipients,
    required this.whatsappConfigured,
    required this.displayWhatsappConfigured,
    required this.whatsappPhoneNumberId,
    required this.whatsappBusinessAccountId,
    required this.schedule,
    required this.runFrequency,
    required this.retryPolicy,
    required this.recipientPolicy,
    required this.duplicatePolicy,
    required this.templatePolicy,
  });

  final bool deliveryGateEnabled;
  final bool emergencyStop;
  final bool dryRun;
  final bool testMode;
  final bool allowRealRecipients;
  final bool whatsappConfigured;
  final bool displayWhatsappConfigured;
  final String whatsappPhoneNumberId;
  final String whatsappBusinessAccountId;
  final PaymentReminderSchedule schedule;
  final String runFrequency;
  final String retryPolicy;
  final String recipientPolicy;
  final String duplicatePolicy;
  final String templatePolicy;

  factory PaymentReminderSystemState.fromApi(Map<String, dynamic> map) {
    return PaymentReminderSystemState(
      deliveryGateEnabled: map['deliveryGateEnabled'] == true,
      emergencyStop: map['emergencyStop'] == true,
      dryRun: map['dryRun'] == true,
      testMode: map['testMode'] == true,
      allowRealRecipients: map['allowRealRecipients'] == true,
      whatsappConfigured: map['whatsappConfigured'] == true,
      displayWhatsappConfigured: map['displayWhatsappConfigured'] == true,
      whatsappPhoneNumberId: _text(map['whatsappPhoneNumberId']),
      whatsappBusinessAccountId: _text(map['whatsappBusinessAccountId']),
      schedule: PaymentReminderSchedule.fromApi(_map(map['schedule'])),
      runFrequency: _text(map['runFrequency']),
      retryPolicy: _text(map['retryPolicy']),
      recipientPolicy: _text(map['recipientPolicy']),
      duplicatePolicy: _text(map['duplicatePolicy']),
      templatePolicy: _text(map['templatePolicy']),
    );
  }
}

class PaymentReminderSchedule {
  const PaymentReminderSchedule({
    required this.timezone,
    required this.allowedDays,
    required this.startHour,
    required this.endHour,
    this.startDate,
  });

  final String timezone;
  final String allowedDays;
  final int startHour;
  final int endHour;
  final String? startDate;

  String get windowLabel {
    final start = startHour.toString().padLeft(2, '0');
    final end = endHour.toString().padLeft(2, '0');
    return '$start:00 a $end:00';
  }

  String get allowedDaysLabel {
    final labels = <String>[];
    for (final part in allowedDays.split(',')) {
      switch (part.trim()) {
        case '0':
          labels.add('domingo');
          break;
        case '1':
          labels.add('lunes');
          break;
        case '2':
          labels.add('martes');
          break;
        case '3':
          labels.add('miercoles');
          break;
        case '4':
          labels.add('jueves');
          break;
        case '5':
          labels.add('viernes');
          break;
        case '6':
          labels.add('sabado');
          break;
      }
    }
    return labels.isEmpty ? 'sin dias configurados' : labels.join(', ');
  }

  factory PaymentReminderSchedule.fromApi(Map<String, dynamic> map) {
    return PaymentReminderSchedule(
      timezone: _text(map['timezone']),
      allowedDays: _text(map['allowedDays']),
      startHour: _int(map['startHour']),
      endHour: _int(map['endHour']),
      startDate: _nullableText(map['startDate']),
    );
  }
}

class PaymentReminderTemplateState {
  const PaymentReminderTemplateState({
    required this.locked,
    required this.editableFields,
    required this.preview,
  });

  final bool locked;
  final List<PaymentReminderTemplateField> editableFields;
  final String preview;

  factory PaymentReminderTemplateState.fromApi(Map<String, dynamic> map) {
    return PaymentReminderTemplateState(
      locked: map['locked'] != false,
      editableFields: _list(map['editableFields'])
          .map((item) => PaymentReminderTemplateField.fromApi(_map(item)))
          .toList(growable: false),
      preview: _text(map['preview']),
    );
  }
}

class PaymentReminderTemplateField {
  const PaymentReminderTemplateField({
    required this.key,
    required this.label,
    required this.value,
    required this.editable,
  });

  final String key;
  final String label;
  final String value;
  final bool editable;

  factory PaymentReminderTemplateField.fromApi(Map<String, dynamic> map) {
    return PaymentReminderTemplateField(
      key: _text(map['key']),
      label: _text(map['label']),
      value: _text(map['value']),
      editable: map['editable'] == true,
    );
  }
}

class PaymentReminderCandidateSummary {
  const PaymentReminderCandidateSummary({
    required this.totalSales,
    required this.activeSales,
    required this.overdueSales,
    required this.withValidPhone,
    required this.blockedWithoutPhone,
    required this.totalOverdueInstallments,
    required this.totalDue,
    required this.preview,
  });

  final int totalSales;
  final int activeSales;
  final int overdueSales;
  final int withValidPhone;
  final int blockedWithoutPhone;
  final int totalOverdueInstallments;
  final String totalDue;
  final List<PaymentReminderCandidateItem> preview;

  factory PaymentReminderCandidateSummary.fromApi(Map<String, dynamic> map) {
    return PaymentReminderCandidateSummary(
      totalSales: _int(map['totalSales']),
      activeSales: _int(map['activeSales']),
      overdueSales: _int(map['overdueSales']),
      withValidPhone: _int(map['withValidPhone']),
      blockedWithoutPhone: _int(map['blockedWithoutPhone']),
      totalOverdueInstallments: _int(map['totalOverdueInstallments']),
      totalDue: _text(map['totalDue']),
      preview: _list(map['preview'])
          .map((item) => PaymentReminderCandidateItem.fromApi(_map(item)))
          .toList(growable: false),
    );
  }
}

class PaymentReminderCandidateItem {
  const PaymentReminderCandidateItem({
    required this.saleSyncId,
    required this.clientName,
    required this.phoneMasked,
    required this.lotLabel,
    required this.overdueInstallments,
    required this.totalDue,
    required this.status,
  });

  final String saleSyncId;
  final String clientName;
  final String phoneMasked;
  final String lotLabel;
  final int overdueInstallments;
  final String totalDue;
  final String status;

  factory PaymentReminderCandidateItem.fromApi(Map<String, dynamic> map) {
    return PaymentReminderCandidateItem(
      saleSyncId: _text(map['saleSyncId']),
      clientName: _text(map['clientName']),
      phoneMasked: _text(map['phoneMasked']),
      lotLabel: _text(map['lotLabel']),
      overdueInstallments: _int(map['overdueInstallments']),
      totalDue: _text(map['totalDue']),
      status: _text(map['status']),
    );
  }
}

class PaymentReminderStats {
  const PaymentReminderStats({
    required this.sent,
    required this.delivered,
    required this.read,
    required this.failed,
    required this.pending,
    required this.dryRun,
  });

  final int sent;
  final int delivered;
  final int read;
  final int failed;
  final int pending;
  final int dryRun;

  factory PaymentReminderStats.fromApi(Map<String, dynamic> map) {
    return PaymentReminderStats(
      sent: _int(map['sent']),
      delivered: _int(map['delivered']),
      read: _int(map['read']),
      failed: _int(map['failed']),
      pending: _int(map['pending']),
      dryRun: _int(map['dryRun']),
    );
  }
}

class PaymentReminderLastRun {
  const PaymentReminderLastRun({
    required this.status,
    required this.processedCount,
    required this.createdAt,
    this.sentAt,
  });

  final String status;
  final int processedCount;
  final DateTime createdAt;
  final DateTime? sentAt;

  factory PaymentReminderLastRun.fromApi(Map<String, dynamic> map) {
    return PaymentReminderLastRun(
      status: _text(map['status']),
      processedCount: _int(map['processedCount']),
      createdAt: DateTime.tryParse(_text(map['createdAt'])) ?? DateTime(1970),
      sentAt: DateTime.tryParse(_text(map['sentAt'])),
    );
  }
}

class PaymentReminderHistoryItem {
  const PaymentReminderHistoryItem({
    required this.id,
    required this.clientName,
    required this.phoneMasked,
    required this.status,
    required this.installmentCount,
    required this.createdAt,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
  });

  final String id;
  final String clientName;
  final String phoneMasked;
  final String status;
  final int installmentCount;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  DateTime get displayDate => readAt ?? deliveredAt ?? sentAt ?? createdAt;

  factory PaymentReminderHistoryItem.fromApi(Map<String, dynamic> map) {
    return PaymentReminderHistoryItem(
      id: _text(map['id']),
      clientName: _text(map['clientName']),
      phoneMasked: _text(map['phoneMasked']),
      status: _text(map['status']),
      installmentCount: _int(map['installmentCount']),
      createdAt: DateTime.tryParse(_text(map['createdAt'])) ?? DateTime(1970),
      sentAt: DateTime.tryParse(_text(map['sentAt'])),
      deliveredAt: DateTime.tryParse(_text(map['deliveredAt'])),
      readAt: DateTime.tryParse(_text(map['readAt'])),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

List<Object?> _list(Object? value) => value is List ? value : const [];

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullableText(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

int _int(Object? value) => int.tryParse('${value ?? ''}') ?? 0;
