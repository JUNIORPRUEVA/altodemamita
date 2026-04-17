import 'dart:convert';
import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/sensitive_storage.dart';
import '../../../core/system/system_config_service.dart';
import '../../../features/clients/data/client_repository.dart';
import '../../../features/settings/data/company_repository.dart';
import '../../../features/settings/data/settings_repository.dart';
import '../../../features/settings/domain/company_info.dart';
import '../../../repositories/installments_sync_repository.dart';
import '../../../repositories/payments_sync_repository.dart';
import '../../../repositories/products_sync_repository.dart';
import '../../../repositories/sales_sync_repository.dart';
import '../../../services/sync/sync_config_repository.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../../../services/sync/sync_service.dart';
import '../domain/permission_model.dart';
import '../domain/user_model.dart';

class AuthBootstrapResult {
  const AuthBootstrapResult({
    required this.requiresInitialSetup,
    required this.isOnline,
    required this.isCloudInitialized,
    required this.backendStatus,
    this.backendStatusMessage,
    this.currentUser,
  });

  final bool requiresInitialSetup;
  final bool isOnline;
  final bool isCloudInitialized;
  final BackendConnectionStatus backendStatus;
  final String? backendStatusMessage;
  final UserModel? currentUser;
}

enum BackendConnectionStatus { unconfigured, connected, unreachable, error }

enum AuthSignInMode { online, offline }

class AuthSignInResult {
  const AuthSignInResult({
    required this.user,
    required this.mode,
    this.syncTriggered = false,
  });

  final UserModel user;
  final AuthSignInMode mode;
  final bool syncTriggered;
}

class _RemoteSystemStatus {
  const _RemoteSystemStatus({
    required this.isReachable,
    required this.initialized,
    required this.statusAvailable,
    required this.connectionStatus,
    this.message,
  });

  final bool isReachable;
  final bool initialized;
  final bool statusAvailable;
  final BackendConnectionStatus connectionStatus;
  final String? message;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminRecoveryCredentials {
  const AdminRecoveryCredentials({
    required this.nombre,
    required this.email,
    required this.password,
    this.updatedAt,
  });

  final String nombre;
  final String email;
  final String password;
  final DateTime? updatedAt;
}

class AuthService {
  AuthService({
    AppDatabase? appDatabase,
    SyncConfigRepository? syncConfigRepository,
    Future<SharedPreferences> Function()? preferencesFactory,
    SensitiveStorage? sensitiveStorage,
    HttpClient? httpClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository(),
       _httpClient = httpClient ?? HttpClient(),
       _sensitiveStorage =
           sensitiveStorage ??
           SensitiveStorage(preferencesFactory: preferencesFactory),
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  static const String _sessionSelectorKey = 'auth.session.selector';
  static const String _sessionTokenKey = 'auth.session.token';
  static const Duration _sessionLifetime = Duration(days: 7);
  static const String _adminRecoveryCodeKey = 'admin_recovery_code';
  static const String _adminRecoveryCodeGeneratedAtKey =
      'admin_recovery_code_generated_at';
  static const String _adminRecoverySnapshotKey =
      'admin_recovery_credentials_snapshot';
  static const String adminRecoverySnapshotUnavailableMessage =
      'Los datos visibles del administrador aun no estan disponibles en esta instalacion.';

  final AppDatabase _appDatabase;
  final SyncConfigRepository _syncConfigRepository;
  final HttpClient _httpClient;
  final SensitiveStorage _sensitiveStorage;
  final Future<SharedPreferences> Function() _preferencesFactory;

  Future<AuthBootstrapResult> bootstrap() async {
    final remoteStatus = await _fetchRemoteSystemStatus();
    final localRequiresInitialSetup = await requiresInitialSetup();

    if (remoteStatus.isReachable && !remoteStatus.initialized) {
      if (!remoteStatus.statusAvailable) {
        return AuthBootstrapResult(
          requiresInitialSetup: false,
          isOnline: true,
          isCloudInitialized: !localRequiresInitialSetup,
          backendStatus: remoteStatus.connectionStatus,
          backendStatusMessage: remoteStatus.message,
        );
      }
      await clearSession();
      return AuthBootstrapResult(
        requiresInitialSetup: true,
        isOnline: true,
        isCloudInitialized: false,
        backendStatus: remoteStatus.connectionStatus,
        backendStatusMessage: remoteStatus.message,
      );
    }

    UserModel? currentUser;
    if (!localRequiresInitialSetup) {
      currentUser = await restoreSession();
      if (currentUser != null && remoteStatus.isReachable) {
        await _runFullSyncIfPossible();
      }
    }

    return AuthBootstrapResult(
      requiresInitialSetup:
          remoteStatus.isReachable &&
          remoteStatus.statusAvailable &&
          !remoteStatus.initialized,
      isOnline: remoteStatus.isReachable,
      isCloudInitialized: remoteStatus.isReachable && remoteStatus.statusAvailable
          ? remoteStatus.initialized
          : !localRequiresInitialSetup,
      backendStatus: remoteStatus.connectionStatus,
      backendStatusMessage: remoteStatus.message,
      currentUser: currentUser,
    );
  }

  Future<AuthSignInResult> signInHybrid({
    required String email,
    required String password,
  }) async {
    final settings = await _syncConfigRepository.loadSettings();
    final remoteStatus = await _fetchRemoteSystemStatus();
    if (remoteStatus.isReachable) {
      if (remoteStatus.statusAvailable && !remoteStatus.initialized) {
        throw const AuthException(
          'El sistema central aun no ha sido inicializado.',
        );
      }

      final user = await loginOnline(email: email, password: password);
      final syncTriggered = await _runFullSyncIfPossible();
      return AuthSignInResult(
        user: user,
        mode: AuthSignInMode.online,
        syncTriggered: syncTriggered,
      );
    }

    if (settings.baseUrl.trim().isEmpty) {
      throw const AuthException(
        'Configura la URL del backend para iniciar sesion contra el sistema central.',
      );
    }

    return AuthSignInResult(
      user: await loginOffline(email: email, password: password),
      mode: AuthSignInMode.offline,
    );
  }

  Future<String> loadBackendBaseUrl() async {
    final settings = await _syncConfigRepository.loadSettings();
    return settings.baseUrl.trim();
  }

  Future<void> saveBackendBaseUrl(String baseUrl) {
    return _syncConfigRepository.saveBaseUrl(baseUrl.trim());
  }

  Future<UserModel> loginOnline({
    required String email,
    required String password,
  }) async {
    final settings = await _syncConfigRepository.loadSettings();
    if (settings.baseUrl.trim().isEmpty) {
      throw const AuthException(
        'Configura la URL del backend antes de iniciar sesion en linea.',
      );
    }

    final normalizedIdentifier = email.trim();
    final normalizedPassword = password.trim();
    if (normalizedIdentifier.isEmpty || normalizedPassword.isEmpty) {
      throw const AuthException('Ingresa tu correo o usuario y la contrasena.');
    }

    final response = await _sendJsonRequest(
      method: 'POST',
      uri: Uri.parse('${settings.normalizedBaseUrl}/auth/login'),
      payload: {
        'identifier': normalizedIdentifier,
        'password': normalizedPassword,
      },
    );

    final accessToken = response['accessToken']?.toString().trim() ?? '';
    final rawUser = response['user'];
    if (accessToken.isEmpty || rawUser is! Map) {
      throw const AuthException(
        'La respuesta del backend no incluye una sesion valida.',
      );
    }

    final user = await _cacheCloudUser(
      rawUser.map((key, value) => MapEntry(key.toString(), value)),
      normalizedPassword,
    );
    await _syncConfigRepository.saveJwtToken(accessToken);
    return user;
  }

  Future<UserModel> loginOffline({
    required String email,
    required String password,
  }) async {
    final normalizedIdentifier = email.trim().toLowerCase();
    final db = await _appDatabase.database;
    final user = await _findUserByIdentifier(db, normalizedIdentifier);

    if (user == null) {
      throw const AuthException(
        'No existe un usuario local para iniciar sesion sin conexion.',
      );
    }

    if (user.authSource == AuthSource.cloud && user.lastOnlineLoginAt == null) {
      throw const AuthException(
        'Este usuario todavia no tiene un login online previo para habilitar el modo offline.',
      );
    }

    return signIn(email: email, password: password);
  }

  Future<bool> requiresInitialSetup() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['id'],
      where:
          'activo = 1 AND password_reset_required = 0 '
          "AND TRIM(COALESCE(password_hash, '')) != ''",
      limit: 1,
    );
    return rows.isEmpty;
  }

  Future<String> completeInitialSetup({
    String companyName = 'Sistema de Solares',
    required String nombre,
    required String email,
    required String password,
    required String recoveryCode,
  }) async {
    final normalizedCompanyName = companyName.trim();
    final normalizedName = nombre.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPassword = password.trim();
    final normalizedRecoveryCode = _normalizeRecoveryCode(recoveryCode);

    if (normalizedCompanyName.isEmpty) {
      throw const AuthException('El nombre de la empresa es obligatorio.');
    }
    if (normalizedName.isEmpty) {
      throw const AuthException('El nombre es obligatorio.');
    }
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthException('Ingresa un correo valido.');
    }
    if (normalizedPassword.length < 6) {
      throw const AuthException(
        'La contrasena inicial debe tener al menos 6 caracteres.',
      );
    }
    if (normalizedRecoveryCode.length < 8) {
      throw const AuthException('La clave de recuperacion no es valida.');
    }

    final settings = await _syncConfigRepository.loadSettings();
    if (settings.baseUrl.trim().isEmpty) {
      throw const AuthException(
        'Configura la URL del backend antes de completar la configuración inicial.',
      );
    }

    final remoteStatus = await _fetchRemoteSystemStatus();
    if (!remoteStatus.isReachable) {
      throw const AuthException(
        'Se requiere conexión con el backend para completar la configuración inicial.',
      );
    }
    if (remoteStatus.initialized) {
      throw const AuthException('El sistema central ya fue inicializado.');
    }

    await _sendJsonRequest(
      method: 'POST',
      uri: Uri.parse('${settings.normalizedBaseUrl}/system/setup'),
      payload: {
        'company': {'name': normalizedCompanyName},
        'admin': {
          'fullName': normalizedName,
          'email': normalizedEmail,
          'password': normalizedPassword,
        },
      },
    );

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await _upsertSetting(
        txn,
        _adminRecoveryCodeKey,
        normalizedRecoveryCode,
        now,
      );
      await _upsertSetting(txn, _adminRecoveryCodeGeneratedAtKey, now, now);
      await _storeAdminRecoverySnapshot(
        txn,
        recoveryCode: normalizedRecoveryCode,
        nombre: normalizedName,
        email: normalizedEmail,
        password: '',
        updatedAt: now,
      );
    });
    await _persistLocalCompanyProfile(normalizedCompanyName);
    await loginOnline(email: normalizedEmail, password: normalizedPassword);

    await clearSession();
    return normalizedRecoveryCode;
  }

  Future<String> getOrCreateAdminRecoveryCode() async {
    final db = await _appDatabase.database;
    final currentCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (currentCode != null && currentCode.isNotEmpty) {
      return currentCode;
    }
    return _writeNewAdminRecoveryCode(db);
  }

  Future<String> regenerateAdminRecoveryCode() async {
    final db = await _appDatabase.database;
    return _writeNewAdminRecoveryCode(db);
  }

  Future<String?> getAdminRecoveryCodeGeneratedAt() async {
    final db = await _appDatabase.database;
    return _getSettingValue(db, _adminRecoveryCodeGeneratedAtKey);
  }

  Future<AdminRecoveryCredentials?> getDebugAdminPrefillCredentials() async {
    final db = await _appDatabase.database;

    if (await requiresInitialSetup()) {
      return const AdminRecoveryCredentials(
        nombre: 'Administrador principal',
        email: PasswordHasher.defaultAdminEmail,
        password: PasswordHasher.legacyDefaultAdminPassword,
      );
    }

    final adminUser = await getUserById(1);
    if (adminUser == null) {
      return null;
    }

    final recoveryCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (recoveryCode != null && recoveryCode.isNotEmpty) {
      final snapshot = await _readAdminRecoverySnapshot(db, recoveryCode);
      if (snapshot != null) {
        return snapshot;
      }
    }

    return AdminRecoveryCredentials(
      nombre: adminUser.nombre,
      email: adminUser.email,
      password: '',
    );
  }

  Future<AdminRecoveryCredentials> revealAdminCredentials({
    required String recoveryCode,
  }) async {
    final normalizedRecoveryCode = _normalizeRecoveryCode(recoveryCode);
    if (normalizedRecoveryCode.isEmpty) {
      throw const AuthException('Ingresa la clave de recuperacion.');
    }

    final db = await _appDatabase.database;
    final storedCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (storedCode == null || storedCode.isEmpty) {
      throw const AuthException(
        'Este sistema todavia no tiene una clave de recuperacion configurada.',
      );
    }
    if (_normalizeRecoveryCode(storedCode) != normalizedRecoveryCode) {
      throw const AuthException('La clave de recuperacion no coincide.');
    }

    final credentials = await _readAdminRecoverySnapshot(
      db,
      normalizedRecoveryCode,
    );
    if (credentials == null) {
      throw const AuthException(adminRecoverySnapshotUnavailableMessage);
    }

    return credentials;
  }

  Future<UserModel> recoverAdminAccess({
    required String recoveryCode,
    required String nombre,
    required String email,
    required String newPassword,
  }) async {
    final normalizedRecoveryCode = _normalizeRecoveryCode(recoveryCode);
    final normalizedName = nombre.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPassword = newPassword.trim();

    if (normalizedRecoveryCode.isEmpty) {
      throw const AuthException('Ingresa la clave de recuperacion.');
    }
    if (normalizedName.isEmpty) {
      throw const AuthException('El nombre es obligatorio.');
    }
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthException('Ingresa un correo valido.');
    }
    if (normalizedPassword.length < 8) {
      throw const AuthException(
        'La nueva contrasena debe tener al menos 8 caracteres.',
      );
    }

    final db = await _appDatabase.database;
    final storedCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (storedCode == null || storedCode.isEmpty) {
      throw const AuthException(
        'Este sistema todavia no tiene una clave de recuperacion configurada.',
      );
    }
    if (_normalizeRecoveryCode(storedCode) != normalizedRecoveryCode) {
      throw const AuthException('La clave de recuperacion no coincide.');
    }

    await _ensureEmailAvailable(db, normalizedEmail, excludeUserId: 1);
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(DatabaseSchema.usersTable, {
        'nombre': normalizedName,
        'email': normalizedEmail,
        'password_hash': PasswordHasher.hashPassword(normalizedPassword),
        'password_reset_required': 0,
        'password_updated_at': now,
        'rol': UserRole.admin.storageValue,
        'activo': 1,
        'fecha_actualizacion': now,
      }, where: 'id = 1');
      await txn.delete(
        DatabaseSchema.authSessionsTable,
        where: 'usuario_id = ?',
        whereArgs: [1],
      );
      await _replacePermissions(txn, 1, _fullPermissions());
      await _storeAdminRecoverySnapshot(
        txn,
        recoveryCode: normalizedRecoveryCode,
        nombre: normalizedName,
        email: normalizedEmail,
        password: normalizedPassword,
        updatedAt: now,
      );
    });

    await clearSession();
    return signIn(email: normalizedEmail, password: normalizedPassword);
  }

  Future<UserModel?> restoreSession() async {
    final selector = await _sensitiveStorage.read(_sessionSelectorKey);
    final token = await _sensitiveStorage.read(_sessionTokenKey);
    if (selector == null ||
        token == null ||
        selector.isEmpty ||
        token.isEmpty) {
      return null;
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.authSessionsTable,
      columns: ['usuario_id', 'token_hash', 'expires_at', 'revoked_at'],
      where: 'selector = ?',
      whereArgs: [selector],
      limit: 1,
    );
    if (rows.isEmpty) {
      await clearSession();
      return null;
    }

    final row = rows.first;
    final revokedAt = (row['revoked_at'] as String?)?.trim();
    final expiresAtRaw = (row['expires_at'] as String? ?? '').trim();
    final tokenHash = (row['token_hash'] as String? ?? '').trim();
    final expiresAt = expiresAtRaw.isEmpty
        ? null
        : DateTime.tryParse(expiresAtRaw);

    if (revokedAt != null && revokedAt.isNotEmpty) {
      await clearSession();
      return null;
    }
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) {
      await _revokeSessionBySelector(db, selector);
      await clearSession();
      return null;
    }
    if (PasswordHasher.hashToken(token) != tokenHash) {
      await _revokeSessionBySelector(db, selector);
      await clearSession();
      return null;
    }

    final userId = row['usuario_id'] as int?;
    if (userId == null) {
      await clearSession();
      return null;
    }

    final user = await getUserById(userId);
    if (user == null || !user.activo || user.passwordResetRequired) {
      await _revokeSessionBySelector(db, selector);
      await clearSession();
      return null;
    }

    await db.update(
      DatabaseSchema.authSessionsTable,
      {
        'last_used_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(_sessionLifetime).toIso8601String(),
      },
      where: 'selector = ?',
      whereArgs: [selector],
    );
    return user;
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedIdentifier = email.trim().toLowerCase();
    final normalizedPassword = password.trim();
    final db = await _appDatabase.database;
    var rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'LOWER(email) = ?',
      whereArgs: [normalizedIdentifier],
      limit: 1,
    );

    if (rows.isEmpty) {
      rows = await db.query(
        DatabaseSchema.usersTable,
        where: 'LOWER(nombre) = ?',
        whereArgs: [normalizedIdentifier],
        limit: 1,
      );
    }

    if (rows.isEmpty) {
      throw const AuthException('Correo, usuario o contrasena incorrectos.');
    }

    final user = await _mapUser(db, rows.first);
    if (!user.activo) {
      throw const AuthException(
        'Tu cuenta esta inactiva. Contacta al administrador.',
      );
    }
    if (user.passwordResetRequired) {
      throw AuthException(
        user.id == 1
            ? 'Debes completar la configuracion inicial del administrador.'
            : 'Tu cuenta requiere restablecer la contrasena con un administrador.',
      );
    }
    if (!_verifyStoredPassword(normalizedPassword, user.passwordHash)) {
      throw const AuthException('Correo, usuario o contrasena incorrectos.');
    }

    if (_shouldRefreshLocalPasswordHash(user.passwordHash)) {
      final now = DateTime.now().toIso8601String();
      await db.update(
        DatabaseSchema.usersTable,
        {
          'password_hash': PasswordHasher.hashPassword(normalizedPassword),
          'password_updated_at': now,
          'fecha_actualizacion': now,
        },
        where: 'id = ?',
        whereArgs: [user.id],
      );
    }

    final recoveryCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (user.id == 1 && recoveryCode != null && recoveryCode.isNotEmpty) {
      await _storeAdminRecoverySnapshot(
        db,
        recoveryCode: recoveryCode,
        nombre: user.nombre,
        email: user.email,
        password: normalizedPassword,
        updatedAt: DateTime.now().toIso8601String(),
      );
    }

    await _persistSession(db, user.id!);
    return (await getUserById(user.id!))!;
  }

  Future<void> signOut() async {
    final db = await _appDatabase.database;
    final selector = await _sensitiveStorage.read(_sessionSelectorKey);
    if (selector != null && selector.isNotEmpty) {
      await _revokeSessionBySelector(db, selector);
    }
    await _syncConfigRepository.clearJwtToken();
    await clearSession();
  }

  Future<void> clearSession() async {
    await _sensitiveStorage.delete(_sessionSelectorKey);
    await _sensitiveStorage.delete(_sessionTokenKey);
  }

  Future<bool> verifyAdminPassword({required String password}) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      return false;
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['id', 'password_hash', 'password_reset_required', 'activo'],
      where: 'LOWER(rol) = ?',
      whereArgs: [UserRole.admin.storageValue],
      orderBy: 'id ASC',
    );

    for (final row in rows) {
      final isActive = (row['activo'] as int? ?? 0) == 1;
      final requiresReset = (row['password_reset_required'] as int? ?? 0) == 1;
      final passwordHash = (row['password_hash'] as String? ?? '').trim();
      final userId = row['id'] as int?;

      if (!isActive ||
          requiresReset ||
          passwordHash.isEmpty ||
          userId == null) {
        continue;
      }

      if (!PasswordHasher.verifyPassword(normalizedPassword, passwordHash)) {
        continue;
      }

      if (PasswordHasher.needsRehash(passwordHash)) {
        final now = DateTime.now().toIso8601String();
        await db.update(
          DatabaseSchema.usersTable,
          {
            'password_hash': PasswordHasher.hashPassword(normalizedPassword),
            'password_updated_at': now,
            'fecha_actualizacion': now,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );
      }

      return true;
    }

    return false;
  }

  Future<List<UserModel>> fetchUsers() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      orderBy: 'nombre COLLATE NOCASE ASC',
    );

    final users = <UserModel>[];
    for (final row in rows) {
      users.add(await _mapUser(db, row));
    }
    return users;
  }

  Future<UserModel?> getUserById(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapUser(db, rows.first);
  }

  Future<UserModel> createUser({
    required String nombre,
    required String email,
    required String password,
    required UserRole role,
    required List<PermissionModel> permissions,
    bool active = true,
  }) async {
    SystemConfigService.instance.ensureWritable();

    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = nombre.trim();
    if (normalizedName.isEmpty) {
      throw const AuthException('El nombre es obligatorio.');
    }
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthException('Ingresa un correo valido.');
    }
    if (password.trim().length < 8) {
      throw const AuthException(
        'La contrasena debe tener al menos 8 caracteres.',
      );
    }

    final db = await _appDatabase.database;
    await _ensureEmailAvailable(db, normalizedEmail);
    final now = DateTime.now();

    final userId = await db.transaction((txn) async {
      final id = await txn.insert(DatabaseSchema.usersTable, {
        'nombre': normalizedName,
        'email': normalizedEmail,
        'password_hash': PasswordHasher.hashPassword(password.trim()),
        'password_reset_required': 0,
        'rol': role.storageValue,
        'activo': active ? 1 : 0,
        'telefono': null,
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'password_updated_at': now.toIso8601String(),
      });
      await _replacePermissions(
        txn,
        id,
        role == UserRole.admin ? _fullPermissions() : permissions,
      );
      return id;
    });

    return (await getUserById(userId))!;
  }

  Future<UserModel> updateUser({
    required UserModel user,
    required String nombre,
    required String email,
    required UserRole role,
    required bool active,
    required List<PermissionModel> permissions,
    String? newPassword,
  }) async {
    SystemConfigService.instance.ensureWritable();

    final userId = user.id;
    if (userId == null) {
      throw const AuthException('No se pudo identificar el usuario.');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = nombre.trim();
    if (normalizedName.isEmpty) {
      throw const AuthException('El nombre es obligatorio.');
    }
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthException('Ingresa un correo valido.');
    }
    if (newPassword != null &&
        newPassword.trim().isNotEmpty &&
        newPassword.trim().length < 8) {
      throw const AuthException(
        'La contrasena debe tener al menos 8 caracteres.',
      );
    }

    final db = await _appDatabase.database;
    await _ensureEmailAvailable(db, normalizedEmail, excludeUserId: userId);
    final passwordHash = (newPassword != null && newPassword.trim().isNotEmpty)
        ? PasswordHasher.hashPassword(newPassword.trim())
        : user.passwordHash;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await _ensureActiveAdminInvariant(
        txn,
        user: user,
        nextRole: role,
        nextActive: active,
      );
      await txn.update(
        DatabaseSchema.usersTable,
        {
          'nombre': normalizedName,
          'email': normalizedEmail,
          'password_hash': passwordHash,
          'password_reset_required':
              (newPassword != null && newPassword.trim().isNotEmpty)
              ? 0
              : (user.passwordResetRequired ? 1 : 0),
          'rol': role.storageValue,
          'activo': active ? 1 : 0,
          'fecha_actualizacion': now,
          'password_updated_at':
              (newPassword != null && newPassword.trim().isNotEmpty)
              ? now
              : user.passwordUpdatedAt?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      await _replacePermissions(
        txn,
        userId,
        role == UserRole.admin ? _fullPermissions() : permissions,
      );
      await _syncAdminRecoverySnapshot(
        txn,
        userId: userId,
        nombre: normalizedName,
        email: normalizedEmail,
        updatedAt: now,
        plainPassword: newPassword?.trim(),
      );
    });

    return (await getUserById(userId))!;
  }

  Future<void> deleteUser(int userId) async {
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    final user = await getUserById(userId);
    if (user == null) {
      return;
    }

    await db.transaction((txn) async {
      await _ensureActiveAdminInvariant(txn, user: user, deleting: true);
      await txn.delete(
        DatabaseSchema.usersTable,
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
  }

  Future<UserModel> setUserActive({
    required UserModel user,
    required bool active,
  }) async {
    SystemConfigService.instance.ensureWritable();

    final userId = user.id;
    if (userId == null) {
      throw const AuthException('No se pudo identificar el usuario.');
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await _ensureActiveAdminInvariant(txn, user: user, nextActive: active);
      await txn.update(
        DatabaseSchema.usersTable,
        {
          'activo': active ? 1 : 0,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
    return (await getUserById(userId))!;
  }

  Future<UserModel> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final normalizedCurrentPassword = currentPassword.trim();
    final normalizedNewPassword = newPassword.trim();

    if (normalizedCurrentPassword.isEmpty) {
      throw const AuthException('Ingresa tu contraseña actual.');
    }
    if (normalizedNewPassword.length < 8) {
      throw const AuthException(
        'La nueva contraseña debe tener al menos 8 caracteres.',
      );
    }
    if (normalizedCurrentPassword == normalizedNewPassword) {
      throw const AuthException(
        'La nueva contraseña debe ser diferente a la actual.',
      );
    }

    final db = await _appDatabase.database;
    final user = await getUserById(userId);
    if (user == null || !user.activo) {
      throw const AuthException('No se pudo validar la cuenta actual.');
    }
    if (!PasswordHasher.verifyPassword(
      normalizedCurrentPassword,
      user.passwordHash,
    )) {
      throw const AuthException('La contraseña actual no es correcta.');
    }

    final now = DateTime.now().toIso8601String();
    await db.update(
      DatabaseSchema.usersTable,
      {
        'password_hash': PasswordHasher.hashPassword(normalizedNewPassword),
        'password_reset_required': 0,
        'password_updated_at': now,
        'fecha_actualizacion': now,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );

    final recoveryCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (userId == 1 && recoveryCode != null && recoveryCode.isNotEmpty) {
      await _storeAdminRecoverySnapshot(
        db,
        recoveryCode: recoveryCode,
        nombre: user.nombre,
        email: user.email,
        password: normalizedNewPassword,
        updatedAt: now,
      );
    }

    return (await getUserById(userId))!;
  }

  Future<void> _persistSession(DatabaseExecutor db, int userId) async {
    final now = DateTime.now();
    final selector = PasswordHasher.generateRandomToken(18);
    final token = PasswordHasher.generateRandomToken(32);
    await db.insert(DatabaseSchema.authSessionsTable, {
      'usuario_id': userId,
      'selector': selector,
      'token_hash': PasswordHasher.hashToken(token),
      'created_at': now.toIso8601String(),
      'last_used_at': now.toIso8601String(),
      'expires_at': now.add(_sessionLifetime).toIso8601String(),
      'revoked_at': null,
    });

    await _sensitiveStorage.write(_sessionSelectorKey, selector);
    await _sensitiveStorage.write(_sessionTokenKey, token);
  }

  Future<void> _ensureEmailAvailable(
    Database db,
    String email, {
    int? excludeUserId,
  }) async {
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['id'],
      where: excludeUserId == null
          ? 'LOWER(email) = ?'
          : 'LOWER(email) = ? AND id != ?',
      whereArgs: excludeUserId == null ? [email] : [email, excludeUserId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const AuthException('Ese correo ya esta registrado.');
    }
  }

  Future<String?> _getSettingValue(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      DatabaseSchema.settingsTable,
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return (rows.first['valor'] as String?)?.trim();
  }

  Future<void> _upsertSetting(
    DatabaseExecutor db,
    String key,
    String value,
    String updatedAt,
  ) async {
    await db.insert(DatabaseSchema.settingsTable, {
      'clave': key,
      'valor': value,
      'fecha_actualizacion': updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> _writeNewAdminRecoveryCode(Database db) async {
    final currentRecoveryCode = await _getSettingValue(
      db,
      _adminRecoveryCodeKey,
    );
    AdminRecoveryCredentials? currentSnapshot;
    if (currentRecoveryCode != null && currentRecoveryCode.isNotEmpty) {
      try {
        currentSnapshot = await _readAdminRecoverySnapshot(
          db,
          currentRecoveryCode,
        );
      } on AuthException {
        currentSnapshot = null;
      }
    }

    final recoveryCode = PasswordHasher.generateRecoveryCode();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await _upsertSetting(txn, _adminRecoveryCodeKey, recoveryCode, now);
      await _upsertSetting(txn, _adminRecoveryCodeGeneratedAtKey, now, now);
      if (currentSnapshot != null) {
        await _storeAdminRecoverySnapshot(
          txn,
          recoveryCode: recoveryCode,
          nombre: currentSnapshot.nombre,
          email: currentSnapshot.email,
          password: currentSnapshot.password,
          updatedAt: currentSnapshot.updatedAt?.toIso8601String() ?? now,
        );
      }
    });
    return recoveryCode;
  }

  Future<void> _storeAdminRecoverySnapshot(
    DatabaseExecutor db, {
    required String recoveryCode,
    required String nombre,
    required String email,
    required String password,
    required String updatedAt,
  }) async {
    final payload = jsonEncode({
      'nombre': nombre.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      'updated_at': updatedAt,
    });
    final protectedValue = PasswordHasher.encryptRecoveryPayload(
      plaintext: payload,
      secret: recoveryCode,
    );

    await _upsertSetting(
      db,
      _adminRecoverySnapshotKey,
      protectedValue,
      updatedAt,
    );
  }

  Future<AdminRecoveryCredentials?> _readAdminRecoverySnapshot(
    DatabaseExecutor db,
    String recoveryCode,
  ) async {
    final protectedValue = await _getSettingValue(
      db,
      _adminRecoverySnapshotKey,
    );
    if (protectedValue == null || protectedValue.isEmpty) {
      return null;
    }

    try {
      final payload = PasswordHasher.decryptRecoveryPayload(
        protectedValue: protectedValue,
        secret: recoveryCode,
      );
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Formato invalido.');
      }

      final nombre = (data['nombre'] as String? ?? '').trim();
      final email = (data['email'] as String? ?? '').trim().toLowerCase();
      final password = (data['password'] as String? ?? '');
      final updatedAtRaw = (data['updated_at'] as String?)?.trim();

      if (nombre.isEmpty || email.isEmpty || password.isEmpty) {
        throw const FormatException('Datos incompletos.');
      }

      return AdminRecoveryCredentials(
        nombre: nombre,
        email: email,
        password: password,
        updatedAt: updatedAtRaw == null || updatedAtRaw.isEmpty
            ? null
            : DateTime.tryParse(updatedAtRaw),
      );
    } on FormatException {
      throw const AuthException(
        'No se pudieron leer los datos de acceso protegidos.',
      );
    }
  }

  Future<void> _syncAdminRecoverySnapshot(
    DatabaseExecutor db, {
    required int userId,
    required String nombre,
    required String email,
    required String updatedAt,
    String? plainPassword,
  }) async {
    if (userId != 1) {
      return;
    }

    final recoveryCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (recoveryCode == null || recoveryCode.isEmpty) {
      return;
    }

    var resolvedPassword = plainPassword?.trim();
    if (resolvedPassword == null || resolvedPassword.isEmpty) {
      final currentSnapshot = await _readAdminRecoverySnapshot(
        db,
        recoveryCode,
      );
      resolvedPassword = currentSnapshot?.password;
    }
    if (resolvedPassword == null || resolvedPassword.isEmpty) {
      return;
    }

    await _storeAdminRecoverySnapshot(
      db,
      recoveryCode: recoveryCode,
      nombre: nombre,
      email: email,
      password: resolvedPassword,
      updatedAt: updatedAt,
    );
  }

  Future<_RemoteSystemStatus> _fetchRemoteSystemStatus() async {
    try {
      final settings = await _syncConfigRepository.loadSettings();
      if (settings.baseUrl.trim().isEmpty) {
        return const _RemoteSystemStatus(
          isReachable: false,
          initialized: false,
          statusAvailable: false,
          connectionStatus: BackendConnectionStatus.unconfigured,
          message: 'Configura la URL del backend.',
        );
      }

      final uri = Uri.parse('${settings.normalizedBaseUrl}/system/status');
      if (uri.host.trim().isEmpty) {
        return const _RemoteSystemStatus(
          isReachable: false,
          initialized: false,
          statusAvailable: false,
          connectionStatus: BackendConnectionStatus.unconfigured,
          message: 'La URL del backend no es valida.',
        );
      }

      final lookup = await InternetAddress.lookup(uri.host);
      if (lookup.isEmpty) {
        return const _RemoteSystemStatus(
          isReachable: false,
          initialized: false,
          statusAvailable: false,
          connectionStatus: BackendConnectionStatus.unreachable,
          message: 'No se pudo resolver el backend.',
        );
      }

      try {
        final body = await _sendJsonRequest(method: 'GET', uri: uri);
        return _RemoteSystemStatus(
          isReachable: true,
          initialized: body['initialized'] == true,
          statusAvailable: true,
          connectionStatus: BackendConnectionStatus.connected,
        );
      } on AuthException catch (error) {
        final healthUri = Uri.parse('${settings.normalizedBaseUrl}/system/config');
        try {
          await _sendJsonRequest(method: 'GET', uri: healthUri);
          return _RemoteSystemStatus(
            isReachable: true,
            initialized: false,
            statusAvailable: false,
            connectionStatus: BackendConnectionStatus.error,
            message: error.message,
          );
        } catch (_) {
          return _RemoteSystemStatus(
            isReachable: false,
            initialized: false,
            statusAvailable: false,
            connectionStatus: BackendConnectionStatus.unreachable,
            message: 'No se pudo consultar el backend.',
          );
        }
      }
    } on SocketException {
      return const _RemoteSystemStatus(
        isReachable: false,
        initialized: false,
        statusAvailable: false,
        connectionStatus: BackendConnectionStatus.unreachable,
        message: 'No hay comunicacion con el backend.',
      );
    } catch (_) {
      return const _RemoteSystemStatus(
        isReachable: false,
        initialized: false,
        statusAvailable: false,
        connectionStatus: BackendConnectionStatus.unreachable,
      );
    }
  }

  Future<Map<String, dynamic>> _sendJsonRequest({
    required String method,
    required Uri uri,
    Map<String, Object?>? payload,
  }) async {
    final request = await _openRequest(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (payload != null) {
      request.write(jsonEncode(payload));
    }

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final decoded = body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(body);
    final responsePayload = decoded is Map<String, dynamic>
        ? _unwrapResponseEnvelope(decoded)
        : (decoded is Map
              ? _unwrapResponseEnvelope(
                  decoded.map((key, value) => MapEntry(key.toString(), value)),
                )
              : const <String, dynamic>{});
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const AuthException('Credenciales invalidas.');
    }
    if (response.statusCode == HttpStatus.forbidden &&
        responsePayload['message']?.toString() == 'READ_ONLY_MODE') {
      throw const AuthException('Sistema en modo solo lectura');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        responsePayload['message']?.toString() ??
            (body.trim().isEmpty
                ? 'El backend respondio con ${response.statusCode}.'
                : body),
      );
    }
    if (decoded is! Map && decoded is! Map<String, dynamic>) {
      throw const AuthException('La respuesta del backend no es valida.');
    }
    return responsePayload;
  }

  Future<HttpClientRequest> _openRequest(String method, Uri uri) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _httpClient.getUrl(uri);
      case 'POST':
        return _httpClient.postUrl(uri);
      default:
        throw UnsupportedError('Metodo HTTP no soportado: $method');
    }
  }

  Future<UserModel> _cacheCloudUser(
    Map<String, dynamic> payload,
    String plaintextPassword,
  ) async {
    final db = await _appDatabase.database;
    final remoteAuthId = payload['sub']?.toString().trim();
    final email = payload['email']?.toString().trim().toLowerCase() ?? '';
    final fullName = payload['fullName']?.toString().trim();
    final username = payload['username']?.toString().trim();
    if (remoteAuthId == null || remoteAuthId.isEmpty || email.isEmpty) {
      throw const AuthException(
        'El usuario remoto no incluye los datos minimos requeridos.',
      );
    }

    final role = _mapRemoteRole(payload['roles']);
    final permissions = role == UserRole.admin
        ? _fullPermissions()
        : _mapRemotePermissions(payload['permissions']);
    final now = DateTime.now();
    final passwordHash = BCrypt.hashpw(plaintextPassword, BCrypt.gensalt());

    final localUserId = await db.transaction((txn) async {
      final existingByRemoteId = await txn.query(
        DatabaseSchema.usersTable,
        columns: ['id', 'fecha_creacion'],
        where: 'remote_auth_id = ?',
        whereArgs: [remoteAuthId],
        limit: 1,
      );
      final existingByEmail = existingByRemoteId.isEmpty
          ? await txn.query(
              DatabaseSchema.usersTable,
              columns: ['id', 'fecha_creacion'],
              where: 'LOWER(email) = ?',
              whereArgs: [email],
              limit: 1,
            )
          : const <Map<String, Object?>>[];
      final existing = existingByRemoteId.isNotEmpty
          ? existingByRemoteId.first
          : (existingByEmail.isNotEmpty ? existingByEmail.first : null);
      final createdAt = existing == null
          ? now.toIso8601String()
          : (existing['fecha_creacion'] as String? ?? now.toIso8601String());

      final values = {
        'remote_auth_id': remoteAuthId,
        'nombre': (fullName?.isNotEmpty == true ? fullName : username) ?? email,
        'email': email,
        'password_hash': passwordHash,
        'password_reset_required': 0,
        'rol': role.storageValue,
        'activo': payload['isActive'] == false ? 0 : 1,
        'auth_source': AuthSource.cloud.storageValue,
        'last_online_login_at': now.toIso8601String(),
        'telefono': null,
        'fecha_creacion': createdAt,
        'fecha_actualizacion': now.toIso8601String(),
        'password_updated_at': now.toIso8601String(),
      };

      late final int userId;
      if (existing == null) {
        userId = await txn.insert(DatabaseSchema.usersTable, values);
      } else {
        userId = existing['id'] as int;
        await txn.update(
          DatabaseSchema.usersTable,
          values,
          where: 'id = ?',
          whereArgs: [userId],
        );
      }

      await _replacePermissions(txn, userId, permissions);
      await txn.delete(
        DatabaseSchema.authSessionsTable,
        where: 'usuario_id = ?',
        whereArgs: [userId],
      );
      await _persistSession(txn, userId);
      return userId;
    });

    return (await getUserById(localUserId))!;
  }

  Map<String, dynamic> _unwrapResponseEnvelope(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Future<void> _persistLocalCompanyProfile(String companyName) async {
    final db = await _appDatabase.database;
    final now = DateTime.now();
    await CompanyRepository(db).saveCompanyInfo(
      CompanyInfo(
        nombre: companyName,
        fechaCreacion: now,
        fechaActualizacion: now,
      ),
    );
    await SettingsRepository(appDatabase: _appDatabase).upsert(
      SettingsRepository.businessNameKey,
      companyName,
    );
  }

  UserRole _mapRemoteRole(Object? rawRoles) {
    if (rawRoles is! List) {
      return UserRole.user;
    }

    final roles = rawRoles
        .map((item) => item.toString().trim().toUpperCase())
        .toSet();
    if (roles.contains('SUPER_ADMIN') || roles.contains('ADMIN')) {
      return UserRole.admin;
    }
    return UserRole.user;
  }

  List<PermissionModel> _mapRemotePermissions(Object? rawPermissions) {
    if (rawPermissions is! List) {
      return PermissionCatalog.modules
          .map((module) => PermissionModel.empty(module.key))
          .toList(growable: false);
    }

    final buckets = <String, Set<PermissionAction>>{};
    void grant(String module, Iterable<PermissionAction> actions) {
      buckets.putIfAbsent(module, () => <PermissionAction>{}).addAll(actions);
    }

    for (final rawPermission in rawPermissions) {
      final code = rawPermission.toString().trim().toLowerCase();
      switch (code) {
        case 'clients.read':
          grant(PermissionCatalog.clients, [PermissionAction.read]);
          break;
        case 'clients.write':
          grant(PermissionCatalog.clients, [
            PermissionAction.create,
            PermissionAction.update,
            PermissionAction.delete,
          ]);
          break;
        case 'products.read':
          grant(PermissionCatalog.lots, [PermissionAction.read]);
          break;
        case 'products.write':
          grant(PermissionCatalog.lots, [
            PermissionAction.create,
            PermissionAction.update,
            PermissionAction.delete,
          ]);
          break;
        case 'sales.read':
          grant(PermissionCatalog.sales, [PermissionAction.read]);
          break;
        case 'sales.write':
          grant(PermissionCatalog.sales, [
            PermissionAction.create,
            PermissionAction.update,
            PermissionAction.delete,
          ]);
          break;
        case 'payments.read':
          grant(PermissionCatalog.payments, [PermissionAction.read]);
          break;
        case 'payments.write':
          grant(PermissionCatalog.payments, [
            PermissionAction.create,
            PermissionAction.update,
            PermissionAction.delete,
          ]);
          break;
        case 'installments.read':
          grant(PermissionCatalog.installments, [PermissionAction.read]);
          break;
        case 'installments.write':
          grant(PermissionCatalog.installments, [
            PermissionAction.create,
            PermissionAction.update,
            PermissionAction.delete,
          ]);
          break;
        case 'users.read':
        case 'auth.manage':
          grant(PermissionCatalog.settings, [PermissionAction.read]);
          break;
        case 'users.write':
          grant(PermissionCatalog.settings, [
            PermissionAction.create,
            PermissionAction.update,
            PermissionAction.delete,
          ]);
          break;
        case 'reports.read':
          grant(PermissionCatalog.dashboard, [PermissionAction.read]);
          grant(PermissionCatalog.search, [PermissionAction.read]);
          break;
      }
    }

    return PermissionCatalog.modules
        .map((definition) {
          final actions = buckets[definition.key] ?? const <PermissionAction>{};
          return PermissionModel(
            module: definition.key,
            read: actions.contains(PermissionAction.read),
            create: actions.contains(PermissionAction.create),
            update: actions.contains(PermissionAction.update),
            delete: actions.contains(PermissionAction.delete),
          );
        })
        .toList(growable: false);
  }

  Future<UserModel?> _findUserByIdentifier(
    Database db,
    String identifier,
  ) async {
    var rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'LOWER(email) = ?',
      whereArgs: [identifier],
      limit: 1,
    );

    if (rows.isEmpty) {
      rows = await db.query(
        DatabaseSchema.usersTable,
        where: 'LOWER(nombre) = ?',
        whereArgs: [identifier],
        limit: 1,
      );
    }

    if (rows.isEmpty) {
      return null;
    }
    return _mapUser(db, rows.first);
  }

  bool _verifyStoredPassword(String password, String storedHash) {
    if (storedHash.startsWith(r'$2')) {
      return BCrypt.checkpw(password, storedHash);
    }
    return PasswordHasher.verifyPassword(password, storedHash);
  }

  bool _shouldRefreshLocalPasswordHash(String storedHash) {
    if (storedHash.startsWith(r'$2')) {
      return false;
    }
    return PasswordHasher.needsRehash(storedHash);
  }

  Future<bool> _runFullSyncIfPossible() async {
    final settings = await _syncConfigRepository.loadSettings();
    if (!settings.isConfigured) {
      return false;
    }

    final syncQueueService = SyncQueueService.instance;
    final syncService = SyncService(
      repositories: [
        ClientRepository(syncQueueService: syncQueueService),
        ProductsSyncRepository(),
        SalesSyncRepository(),
        InstallmentsSyncRepository(),
        PaymentsSyncRepository(),
      ],
      syncQueueService: syncQueueService,
    );
    final report = await syncService.syncNow();
    return !report.wasSkipped;
  }

  String _normalizeRecoveryCode(String value) {
    return value.trim().toUpperCase().replaceAll(' ', '');
  }

  Future<UserModel> _mapUser(Database db, Map<String, Object?> row) async {
    final userId = row['id'] as int?;
    final permissions = userId == null
        ? const <PermissionModel>[]
        : await _fetchPermissionsForUser(db, userId);
    return UserModel.fromMap(row, permissions: permissions);
  }

  Future<void> _ensureActiveAdminInvariant(
    DatabaseExecutor db, {
    required UserModel user,
    UserRole? nextRole,
    bool? nextActive,
    bool deleting = false,
  }) async {
    if (!user.isAdmin || !user.activo) {
      return;
    }

    final willRemainActiveAdmin =
        !deleting &&
        (nextRole ?? user.role) == UserRole.admin &&
        (nextActive ?? user.activo);
    if (willRemainActiveAdmin) {
      return;
    }

    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DatabaseSchema.usersTable} '
      'WHERE rol = ? AND activo = 1 AND id != ?',
      ['admin', user.id],
    );
    final total = rows.isEmpty ? 0 : (rows.first['total'] as int? ?? 0);
    if (total <= 0) {
      throw const AuthException(
        'Debe existir al menos un administrador activo en el sistema.',
      );
    }
  }

  Future<void> _revokeSessionBySelector(Database db, String selector) async {
    await db.update(
      DatabaseSchema.authSessionsTable,
      {'revoked_at': DateTime.now().toIso8601String()},
      where: 'selector = ? AND revoked_at IS NULL',
      whereArgs: [selector],
    );
  }

  Future<List<PermissionModel>> _fetchPermissionsForUser(
    Database db,
    int userId,
  ) async {
    final rows = await db.query(
      DatabaseSchema.permissionsTable,
      where: 'usuario_id = ?',
      whereArgs: [userId],
      orderBy: 'modulo ASC',
    );

    final permissions = <PermissionModel>[];
    for (final row in rows) {
      final rawActions = row['acciones'] as String? ?? '[]';
      final decoded = jsonDecode(rawActions);
      final actions = decoded is List
          ? decoded.whereType<String>().toList(growable: false)
          : const <String>[];
      permissions.add(
        PermissionModel.fromLegacy(
          module: row['modulo'] as String? ?? '',
          actions: actions,
        ),
      );
    }

    final byModule = {
      for (final permission in permissions) permission.module: permission,
    };
    return PermissionCatalog.modules
        .map(
          (module) => byModule[module.key] ?? PermissionModel.empty(module.key),
        )
        .toList(growable: false);
  }

  Future<void> _replacePermissions(
    DatabaseExecutor db,
    int userId,
    List<PermissionModel> permissions,
  ) async {
    await db.delete(
      DatabaseSchema.permissionsTable,
      where: 'usuario_id = ?',
      whereArgs: [userId],
    );

    final now = DateTime.now().toIso8601String();
    for (final permission in permissions) {
      await db.insert(DatabaseSchema.permissionsTable, {
        'usuario_id': userId,
        'modulo': permission.module,
        'acciones': jsonEncode(permission.toLegacyActions()),
        'fecha_creacion': now,
      });
    }
  }

  List<PermissionModel> _fullPermissions() {
    return PermissionCatalog.modules
        .map((module) => PermissionModel.full(module.key))
        .toList(growable: false);
  }
}
