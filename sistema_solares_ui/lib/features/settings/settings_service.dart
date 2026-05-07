import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/features/users/users_service.dart';

class SettingsOverview {
  SettingsOverview({
    required this.initialized,
    required this.roles,
    required this.permissions,
    required this.devices,
  });

  final bool initialized;
  final List<RoleRecord> roles;
  final List<String> permissions;
  final List<AuthorizedDeviceRecord> devices;
}

class AuthorizedDeviceRecord {
  AuthorizedDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.isPrimary,
    required this.canWrite,
    required this.revokedAt,
    required this.lastSeenAt,
    required this.updatedAt,
  });

  final String deviceId;
  final String? deviceName;
  final String? platform;
  final bool isPrimary;
  final bool canWrite;
  final DateTime? revokedAt;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  bool get isActive => revokedAt == null && isPrimary && canWrite;

  factory AuthorizedDeviceRecord.fromMap(Map<String, dynamic> map) {
    return AuthorizedDeviceRecord(
      deviceId: map['deviceId']?.toString().trim() ?? '',
      deviceName: map['deviceName']?.toString().trim(),
      platform: map['platform']?.toString().trim(),
      isPrimary: map['isPrimary'] == true,
      canWrite: map['canWrite'] == true,
      revokedAt: DateTime.tryParse(map['revokedAt']?.toString() ?? ''),
      lastSeenAt: DateTime.tryParse(map['lastSeenAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? ''),
    );
  }
}

class SettingsService {
  SettingsService(this._apiClient);

  final ApiClient _apiClient;

  Future<SettingsOverview> fetchOverview() async {
    final systemStatus =
        await _apiClient.get('/system/status', authorized: false)
            as Map<String, dynamic>;
    final rolesResponse = await _apiClient.get('/auth/roles') as List<dynamic>;
    final permissionsResponse =
        await _apiClient.get('/auth/permissions') as List<dynamic>;
    final devicesResponse = await _apiClient.get('/devices') as List<dynamic>;

    final roles = rolesResponse
        .map(
          (item) => RoleRecord.fromMap(
            (item as Map<dynamic, dynamic>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();
    final permissions = permissionsResponse
        .map(
          (item) => (item as Map<dynamic, dynamic>)['code']?.toString() ?? '',
        )
        .where((value) => value.isNotEmpty)
        .toList();
    final devices = devicesResponse
        .map(
          (item) => AuthorizedDeviceRecord.fromMap(
            (item as Map<dynamic, dynamic>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .where((device) => device.deviceId.isNotEmpty)
        .toList();

    return SettingsOverview(
      initialized: systemStatus['initialized'] == true,
      roles: roles,
      permissions: permissions,
      devices: devices,
    );
  }

  Future<void> activateDeviceById({
    required String deviceId,
    String? deviceName,
  }) async {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      throw ApiException('Debes pegar un ID de dispositivo valido.');
    }

    await _apiClient.post(
      '/devices/activate',
      body: {
        'device_id': normalizedDeviceId,
        if (deviceName != null && deviceName.trim().isNotEmpty)
          'device_name': deviceName.trim(),
      },
    );
  }
}
