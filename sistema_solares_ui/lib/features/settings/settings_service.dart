import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/features/users/users_service.dart';

class SettingsOverview {
  SettingsOverview({
    required this.initialized,
    required this.roles,
    required this.permissions,
  });

  final bool initialized;
  final List<RoleRecord> roles;
  final List<String> permissions;
}

class SettingsService {
  SettingsService(this._apiClient);

  final ApiClient _apiClient;

  Future<SettingsOverview> fetchOverview() async {
    final systemStatus = await _apiClient.get('/system/status', authorized: false)
        as Map<String, dynamic>;
    final rolesResponse = await _apiClient.get('/auth/roles') as List<dynamic>;
    final permissionsResponse = await _apiClient.get('/auth/permissions') as List<dynamic>;

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

    return SettingsOverview(
      initialized: systemStatus['initialized'] == true,
      roles: roles,
      permissions: permissions,
    );
  }
}