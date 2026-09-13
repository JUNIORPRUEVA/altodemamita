import '../../../core/network/backend_api_client.dart';

class PaymentReminderSettingsRepository {
  PaymentReminderSettingsRepository({BackendApiClient? apiClient})
    : _apiClient = apiClient ?? BackendApiClient();

  final BackendApiClient _apiClient;

  Future<PaymentReminderAdminState> load() async {
    final response = await _apiClient.get('/payment-reminders/admin');
    return PaymentReminderAdminState.fromApi(_unwrapData(response));
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
    return PaymentReminderAdminState.fromApi(_unwrapData(response));
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
    required this.stats,
    required this.history,
    this.lastRun,
  });

  final PaymentReminderConfig config;
  final PaymentReminderSystemState system;
  final PaymentReminderStats stats;
  final PaymentReminderLastRun? lastRun;
  final List<PaymentReminderHistoryItem> history;

  factory PaymentReminderAdminState.fromApi(Map<String, dynamic> map) {
    return PaymentReminderAdminState(
      config: PaymentReminderConfig.fromApi(_map(map['config'])),
      system: PaymentReminderSystemState.fromApi(_map(map['system'])),
      stats: PaymentReminderStats.fromApi(_map(map['stats'])),
      lastRun: map['lastRun'] is Map
          ? PaymentReminderLastRun.fromApi(_map(map['lastRun']))
          : null,
      history: _list(map['history'])
          .map((item) => PaymentReminderHistoryItem.fromApi(_map(item)))
          .toList(growable: false),
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
  });

  final bool notificationsEnabled;
  final bool effectiveEnabled;
  final String senderWhatsAppNumber;
  final String editableMessageFragment;
  final int maxMessageFragmentLength;
  final bool templateLocked;

  factory PaymentReminderConfig.fromApi(Map<String, dynamic> map) {
    return PaymentReminderConfig(
      notificationsEnabled: map['notificationsEnabled'] == true,
      effectiveEnabled: map['effectiveEnabled'] == true,
      senderWhatsAppNumber: _text(map['senderWhatsAppNumber']),
      editableMessageFragment: _text(map['editableMessageFragment']),
      maxMessageFragmentLength:
          int.tryParse('${map['maxMessageFragmentLength'] ?? ''}') ?? 250,
      templateLocked: map['templateLocked'] != false,
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
  });

  final bool deliveryGateEnabled;
  final bool emergencyStop;
  final bool dryRun;
  final bool testMode;
  final bool allowRealRecipients;
  final bool whatsappConfigured;

  factory PaymentReminderSystemState.fromApi(Map<String, dynamic> map) {
    return PaymentReminderSystemState(
      deliveryGateEnabled: map['deliveryGateEnabled'] == true,
      emergencyStop: map['emergencyStop'] == true,
      dryRun: map['dryRun'] == true,
      testMode: map['testMode'] == true,
      allowRealRecipients: map['allowRealRecipients'] == true,
      whatsappConfigured: map['whatsappConfigured'] == true,
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

int _int(Object? value) => int.tryParse('${value ?? ''}') ?? 0;
