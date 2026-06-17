import 'permission_model.dart';

enum AuthSource { local, cloud }

extension AuthSourceX on AuthSource {
  String get storageValue {
    switch (this) {
      case AuthSource.local:
        return 'local';
      case AuthSource.cloud:
        return 'cloud';
    }
  }

  static AuthSource fromStorage(String value) {
    switch (value.trim().toLowerCase()) {
      case 'cloud':
        return AuthSource.cloud;
      default:
        return AuthSource.local;
    }
  }
}

enum UserRole { admin, user }

extension UserRoleX on UserRole {
  String get storageValue {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.user:
        return 'vendedor';
    }
  }

  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.user:
        return 'Usuario';
    }
  }

  static UserRole fromStorage(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'admin') {
      return UserRole.admin;
    }
    return UserRole.user;
  }
}

class UserModel {
  const UserModel({
    this.id,
    this.remoteAuthId,
    required this.nombre,
    required this.email,
    required this.passwordHash,
    required this.passwordResetRequired,
    required this.role,
    required this.permissions,
    required this.activo,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    this.authSource = AuthSource.local,
    this.lastOnlineLoginAt,
    this.passwordUpdatedAt,
    this.telefono,
  });

  final int? id;
  final String? remoteAuthId;
  final String nombre;
  final String email;
  final String passwordHash;
  final bool passwordResetRequired;
  final UserRole role;
  final List<PermissionModel> permissions;
  final bool activo;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;
  final AuthSource authSource;
  final DateTime? lastOnlineLoginAt;
  final DateTime? passwordUpdatedAt;
  final String? telefono;

  bool get isAdmin => role == UserRole.admin;

  bool allows(String module, PermissionAction action) {
    if (isAdmin) {
      return true;
    }

    for (final permission in permissions) {
      if (permission.module == module) {
        return permission.allows(action);
      }
    }
    return false;
  }

  PermissionModel permissionFor(String module) {
    if (isAdmin) {
      return PermissionModel.full(module);
    }

    for (final permission in permissions) {
      if (permission.module == module) {
        return permission;
      }
    }
    return PermissionModel.empty(module);
  }

  factory UserModel.fromMap(
    Map<String, Object?> map, {
    required List<PermissionModel> permissions,
  }) {
    return UserModel(
      id: map['id'] as int?,
      remoteAuthId: (map['remote_auth_id'] as String?)?.trim(),
      nombre: map['nombre'] as String? ?? '',
      email: map['email'] as String? ?? '',
      passwordHash: map['password_hash'] as String? ?? '',
      passwordResetRequired: (map['password_reset_required'] as int? ?? 0) == 1,
      role: UserRoleX.fromStorage(map['rol'] as String? ?? 'user'),
      permissions: permissions,
      activo: (map['activo'] as int? ?? 0) == 1,
      authSource: AuthSourceX.fromStorage(
        map['auth_source'] as String? ?? 'local',
      ),
      telefono: map['telefono'] as String?,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaActualizacion: DateTime.parse(map['fecha_actualizacion'] as String),
      lastOnlineLoginAt:
          (map['last_online_login_at'] as String?)?.isNotEmpty == true
          ? DateTime.tryParse(map['last_online_login_at'] as String)
          : null,
      passwordUpdatedAt:
          (map['password_updated_at'] as String?)?.isNotEmpty == true
          ? DateTime.parse(map['password_updated_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'nombre': nombre.trim(),
      'email': email.trim().toLowerCase(),
      'remote_auth_id': remoteAuthId,
      'password_hash': passwordHash,
      'password_reset_required': passwordResetRequired ? 1 : 0,
      'rol': role.storageValue,
      'activo': activo ? 1 : 0,
      'auth_source': authSource.storageValue,
      'last_online_login_at': lastOnlineLoginAt?.toIso8601String(),
      'telefono': telefono,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_actualizacion': fechaActualizacion.toIso8601String(),
      'password_updated_at': passwordUpdatedAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    int? id,
    String? remoteAuthId,
    String? nombre,
    String? email,
    String? passwordHash,
    bool? passwordResetRequired,
    UserRole? role,
    List<PermissionModel>? permissions,
    bool? activo,
    DateTime? fechaCreacion,
    DateTime? fechaActualizacion,
    AuthSource? authSource,
    DateTime? lastOnlineLoginAt,
    DateTime? passwordUpdatedAt,
    String? telefono,
  }) {
    return UserModel(
      id: id ?? this.id,
      remoteAuthId: remoteAuthId ?? this.remoteAuthId,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordResetRequired:
          passwordResetRequired ?? this.passwordResetRequired,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      activo: activo ?? this.activo,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
      authSource: authSource ?? this.authSource,
      lastOnlineLoginAt: lastOnlineLoginAt ?? this.lastOnlineLoginAt,
      passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
      telefono: telefono ?? this.telefono,
    );
  }
}
