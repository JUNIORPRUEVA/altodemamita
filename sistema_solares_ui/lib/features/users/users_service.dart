import 'package:sistema_solares_ui/core/network/api_client.dart';

class RoleRecord {
  RoleRecord({
    required this.id,
    required this.name,
    required this.code,
  });

  final String id;
  final String name;
  final String code;

  factory RoleRecord.fromMap(Map<String, dynamic> json) {
    return RoleRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

class UserRecord {
  UserRecord({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.isActive,
    required this.roles,
  });

  final String id;
  final String email;
  final String username;
  final String fullName;
  final bool isActive;
  final List<RoleRecord> roles;

  factory UserRecord.fromMap(Map<String, dynamic> json) {
    final roles = (json['roles'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => RoleRecord.fromMap(
            (item as Map<dynamic, dynamic>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();
    return UserRecord(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      isActive: json['isActive'] == true,
      roles: roles,
    );
  }
}

class UsersSnapshot {
  UsersSnapshot({required this.users, required this.roles});

  final List<UserRecord> users;
  final List<RoleRecord> roles;
}

class UsersService {
  UsersService(this._apiClient);

  final ApiClient _apiClient;

  Future<UsersSnapshot> fetchSnapshot({String search = ''}) async {
    final usersResponse = await _apiClient.get(
      '/auth/users',
      queryParameters: {
        'page': '1',
        'limit': '50',
        'search': search,
      },
    ) as Map<String, dynamic>;
    final rolesResponse = await _apiClient.get('/auth/roles') as List<dynamic>;

    final users = (usersResponse['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => UserRecord.fromMap(
            (item as Map<dynamic, dynamic>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();
    final roles = rolesResponse
        .map(
          (item) => RoleRecord.fromMap(
            (item as Map<dynamic, dynamic>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();

    return UsersSnapshot(users: users, roles: roles);
  }
}