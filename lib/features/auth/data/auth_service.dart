import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/sensitive_storage.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/utils/sync_id_generator.dart';
import '../../../features/clients/data/client_repository.dart';
import '../../../features/settings/data/company_repository.dart';
import '../../../features/settings/data/settings_repository.dart';
import '../../../features/settings/domain/company_info.dart';
import '../../../features/sales/data/seller_repository.dart';
import '../../../repositories/installments_sync_repository.dart';
import '../../../repositories/payments_sync_repository.dart';
import '../../../repositories/products_sync_repository.dart';
import '../../../repositories/sales_sync_repository.dart';
import '../../../repositories/users_sync_repository.dart';
import '../../../services/sync/sync_config_repository.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../../../services/sync/sync_api_client.dart';
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
    SyncQueueService? syncQueueService,
    Future<SharedPreferences> Function()? preferencesFactory,
    SensitiveStorage? sensitiveStorage,
    HttpClient? httpClient,
    BackendApiClient? apiClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository(),
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _httpClient = httpClient ?? HttpClient(),
       _apiClient = apiClient ?? BackendApiClient(),
       _sensitiveStorage =
           sensitiveStorage ??
           SensitiveStorage(preferencesFactory: preferencesFactory) {
    _usersSyncRepository = UsersSyncRepository(appDatabase: _appDatabase);
    _syncQueueService.registerRepository(_usersSyncRepository);
  }

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
  final SyncQueueService _syncQueueService;
  final HttpClient _httpClient;
  final BackendApiClient _apiClient;
  final SensitiveStorage _sensitiveStorage;
  final BackendEntityIdRegistry _idRegistry = BackendEntityIdRegistry.instance;
  late final UsersSyncRepository _usersSyncRepository;

  bool get _shouldRunBackgroundSync =>
      identical(_appDatabase, AppDatabase.instance);
  bool get _useBackendMode => identical(_appDatabase, AppDatabase.instance);

  Future<AuthBootstrapResult> bootstrap() async {
    debugPrint('[Bootstrap] Iniciando arranque de la app...');
    final remoteStatus = await _fetchRemoteSystemStatus();
    debugPrint(
      '[Bootstrap] Backend: alcanzable=${remoteStatus.isReachable}, '
      'inicializado=${remoteStatus.initialized}',
    );

    final localRequiresInitialSetup = await requiresInitialSetup();

    // Si la nube ya está inicializada, una PC nueva debe ir a login,
    // no al asistente de configuración inicial.
    final cloudIsReady =
        remoteStatus.isReachable &&
        remoteStatus.statusAvailable &&
        remoteStatus.initialized;
    // En este proyecto la nube es la fuente de verdad. Si el backend no
    // responde en una PC nueva, no se crea un admin local falso: se muestra
    // login con error claro y se reintenta cuando haya conexión.
    final effectiveRequiresInitialSetup =
        localRequiresInitialSetup &&
        remoteStatus.statusAvailable &&
        !remoteStatus.initialized;
    debugPrint(
      '[Bootstrap] cloudIsReady=$cloudIsReady, '
      'localRequiresInitialSetup=$localRequiresInitialSetup, '
      'effectiveRequiresInitialSetup=$effectiveRequiresInitialSetup',
    );

    UserModel? currentUser;
    if (effectiveRequiresInitialSetup) {
      debugPrint(
        '[Bootstrap] Instalacion nueva detectada. Limpiando sesion...',
      );
      await clearSession();
    } else {
      // Paso 1: intentar restaurar sesion local (token SQLite).
      debugPrint('[Bootstrap] Intentando restaurar sesion local...');
      currentUser = await restoreSession();

      if (currentUser != null) {
        debugPrint(
          '[Bootstrap] Sesion local restaurada para ${currentUser.email}.',
        );
      } else {
        // Paso 2: no hay sesion local — intentar JWT guardado contra /auth/me.
        debugPrint(
          '[Bootstrap] Sin sesion local. Intentando validar JWT con backend...',
        );
        if (remoteStatus.isReachable && remoteStatus.initialized) {
          currentUser = await _restoreSessionFromJwt();
          if (currentUser != null) {
            debugPrint(
              '[Bootstrap] Sesion restaurada via JWT para ${currentUser.email}.',
            );
          } else {
            debugPrint(
              '[Bootstrap] JWT invalido o inexistente. Se requiere login.',
            );
          }
        } else {
          debugPrint('[Bootstrap] Backend no disponible. Se requiere login.');
        }
      }
    }

    return AuthBootstrapResult(
      requiresInitialSetup: effectiveRequiresInitialSetup,
      isOnline: remoteStatus.isReachable,
      isCloudInitialized:
          remoteStatus.isReachable && remoteStatus.statusAvailable
          ? remoteStatus.initialized
          : false,
      backendStatus: remoteStatus.connectionStatus,
      backendStatusMessage: remoteStatus.message,
      currentUser: currentUser,
    );
  }

  Future<AuthSignInResult> signInHybrid({
    required String email,
    required String password,
  }) async {
    debugPrint('[SignIn] Intento de login para $email...');
    final remoteStatus = await _fetchRemoteSystemStatus();
    debugPrint(
      '[SignIn] Backend: alcanzable=${remoteStatus.isReachable}, '
      'inicializado=${remoteStatus.initialized}',
    );
    final cloudIsReady =
        remoteStatus.isReachable &&
        remoteStatus.statusAvailable &&
        remoteStatus.initialized;

    if (cloudIsReady) {
      debugPrint('[SignIn] login online attempt para $email.');
      try {
        final user = await loginOnline(email: email, password: password);
        debugPrint('[SignIn] login online success para ${user.email}.');
        final syncTriggered = await _runFullSyncIfPossible();
        return AuthSignInResult(
          user: user,
          mode: AuthSignInMode.online,
          syncTriggered: syncTriggered,
        );
      } on AuthException catch (error) {
        debugPrint(
          '[SignIn] login online failure para $email: ${error.message}',
        );
        UserModel? localUser;
        try {
          localUser = await signIn(email: email, password: password);
        } on AuthException {
          localUser = null;
        }

        if (localUser != null &&
            localUser.authSource == AuthSource.cloud &&
            (localUser.remoteAuthId?.trim().isNotEmpty ?? false) &&
            await _isStoredJwtStillValid()) {
          debugPrint(
            '[SignIn] login online fallo, pero usuario local esta vinculado '
            'y JWT guardado sigue valido. Manteniendo modo online.',
          );
          final syncTriggered = await _runFullSyncIfPossible();
          return AuthSignInResult(
            user: localUser,
            mode: AuthSignInMode.online,
            syncTriggered: syncTriggered,
          );
        }

        throw AuthException(
          'No se pudo iniciar sesion en la nube. Verifica el usuario y la '
          'contrasena. Si este usuario fue creado solo en esta PC, debe '
          'vincularse con una cuenta existente de la nube.',
        );
      }
    }

    debugPrint('[SignIn] Backend no disponible para login online.');
    final restoredUser = await restoreSession();
    final normalizedEmail = email.trim().toLowerCase();
    final hasMatchingLocalSession =
        restoredUser != null &&
        (restoredUser.email.trim().toLowerCase() == normalizedEmail ||
            restoredUser.nombre.trim().toLowerCase() == normalizedEmail);
    if (!hasMatchingLocalSession) {
      final localRequiresInitialSetup = await requiresInitialSetup();
      if (localRequiresInitialSetup) {
        throw const AuthException(
          'No se puede iniciar sin conexion en una PC nueva. Conecta la PC a '
          'internet para validar la nube.',
        );
      }
      throw const AuthException(
        'No se puede iniciar sin conexion sin una sesion local previa. '
        'Conecta la PC a internet e intenta nuevamente.',
      );
    }

    final localUser = await signIn(email: email, password: password);
    debugPrint(
      '[SignIn] Autenticacion local permitida por sesion previa. '
      'Sync bloqueado hasta recuperar JWT de nube.',
    );
    return AuthSignInResult(user: localUser, mode: AuthSignInMode.offline);
  }

  Future<UserModel> loginOnline({
    required String email,
    required String password,
  }) async {
    debugPrint('[LoginOnline] Autenticando con backend para $email...');
    final settings = await _syncConfigRepository.loadSettings();

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
    final savedSettings = await _syncConfigRepository.loadSettings();
    if (savedSettings.jwtToken.trim().isEmpty) {
      debugPrint('[LoginOnline] jwt missing despues de saveJwtToken.');
      throw const AuthException(
        'No se pudo guardar la sesion de nube para sincronizar.',
      );
    }
    debugPrint(
      '[LoginOnline] jwt saved. Usuario: ${user.email}, '
      'rol: ${user.role.storageValue}',
    );
    return user;
  }

  /// Autentica SOLO con la nube para obtener un JWT de sincronización,
  /// sin cambiar la sesión local activa. Útil cuando el usuario local no
  /// tiene credenciales en la nube (PC nueva configurada sin internet).
  Future<UserModel> connectToCloudForSync({
    required String email,
    required String password,
  }) async {
    debugPrint('[ConnectCloud] cloud link attempt para $email.');
    try {
      final user = await loginOnline(email: email, password: password);
      debugPrint('[ConnectCloud] cloud link success para ${user.email}.');
      return user;
    } on AuthException catch (error) {
      debugPrint(
        '[ConnectCloud] cloud link failure para $email: ${error.message}',
      );
      rethrow;
    } catch (error) {
      debugPrint('[ConnectCloud] cloud link failure para $email: $error');
      rethrow;
    }
  }

  /// Retorna true si el JWT guardado en el repositorio de sync sigue
  /// siendo válido contra el backend (sin cambiar nada).
  Future<bool> _isStoredJwtStillValid() async {
    final settings = await _syncConfigRepository.loadSettings();
    final jwt = settings.jwtToken.trim();
    if (jwt.isEmpty) return false;
    try {
      await _sendJsonRequest(
        method: 'GET',
        uri: Uri.parse('${settings.normalizedBaseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $jwt'},
      );
      return true;
    } catch (_) {
      return false;
    }
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

    final db = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(DatabaseSchema.usersTable, {
        'nombre': normalizedName,
        'sync_id': _resolveUserSyncId(1),
        'email': normalizedEmail,
        'password_hash': PasswordHasher.hashPassword(normalizedPassword),
        'password_reset_required': 0,
        'password_updated_at': now,
        'rol': UserRole.admin.storageValue,
        'activo': 1,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPending,
        'fecha_actualizacion': now,
      }, where: 'id = 1');
      await txn.delete(
        DatabaseSchema.authSessionsTable,
        where: 'usuario_id = ?',
        whereArgs: [1],
      );
      await _replacePermissions(txn, 1, _fullPermissions());
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
        password: normalizedPassword,
        updatedAt: now,
      );
    });
    await _persistLocalCompanyProfile(normalizedCompanyName);
    await _bootstrapRemoteSystemIfNeeded(
      companyName: normalizedCompanyName,
      nombre: normalizedName,
      email: normalizedEmail,
      password: normalizedPassword,
    );
    try {
      await loginOnline(email: normalizedEmail, password: normalizedPassword);
    } on AuthException {
      // Local-first setup stays usable even if the backend session cannot start.
    } on SocketException {
      // The user can continue locally and reauthenticate online later.
    }
    await clearSession();
    await signIn(email: normalizedEmail, password: normalizedPassword);
    _scheduleUserSync('bootstrap-admin');
    return normalizedRecoveryCode;
  }

  Future<String> getOrCreateAdminRecoveryCode() async {
    final db = await _appDatabase.database;
    final currentCode = await _getSettingValue(db, _adminRecoveryCodeKey);
    if (currentCode != null && currentCode.isNotEmpty) {
      return currentCode;
    }

    SystemConfigService.instance.ensureWritable();
    return _writeNewAdminRecoveryCode(db);
  }

  Future<String> regenerateAdminRecoveryCode() async {
    SystemConfigService.instance.ensureWritable();

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
      final snapshot = await _tryReadAdminRecoverySnapshot(db, recoveryCode);
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

      if (!_verifyStoredPassword(normalizedPassword, passwordHash)) {
        continue;
      }

      if (_shouldRefreshLocalPasswordHash(passwordHash)) {
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
    if (_useBackendMode) {
      return _fetchUsersFromBackend();
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'deleted_at IS NULL',
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
      where: 'id = ? AND deleted_at IS NULL',
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

    if (_useBackendMode) {
      return _createUserInBackend(
        nombre: normalizedName,
        email: normalizedEmail,
        password: password.trim(),
        role: role,
        permissions: permissions,
        active: active,
      );
    }

    final db = await _appDatabase.database;
    await _ensureEmailAvailable(db, normalizedEmail);
    final now = DateTime.now();

    final userId = await db.transaction((txn) async {
      final id = await txn.insert(DatabaseSchema.usersTable, {
        'sync_id': _nextUserSyncId(),
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
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPending,
      });
      await _replacePermissions(
        txn,
        id,
        role == UserRole.admin ? _fullPermissions() : permissions,
      );
      return id;
    });

    _scheduleUserSync('create-user:$userId');

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

    if (_useBackendMode) {
      return _updateUserInBackend(
        user: user,
        nombre: normalizedName,
        email: normalizedEmail,
        role: role,
        active: active,
        permissions: permissions,
        newPassword: newPassword?.trim(),
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
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusPending,
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

    _scheduleUserSync('update-user:$userId');

    return (await getUserById(userId))!;
  }

  Future<void> deleteUser(int userId) async {
    SystemConfigService.instance.ensureWritable();

    if (_useBackendMode) {
      await _deleteUserInBackend(userId);
      return;
    }

    final db = await _appDatabase.database;
    final user = await getUserById(userId);
    if (user == null) {
      return;
    }

    await db.transaction((txn) async {
      await _ensureActiveAdminInvariant(txn, user: user, deleting: true);
      final now = DateTime.now().toIso8601String();
      await txn.update(
        DatabaseSchema.usersTable,
        {
          'activo': 0,
          'deleted_at': now,
          'sync_status': DatabaseSchema.syncStatusPending,
          'fecha_actualizacion': now,
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [userId],
      );
    });

    _scheduleUserSync('delete-user:$userId');
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

    if (_useBackendMode) {
      return _setUserActiveInBackend(user: user, active: active);
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await _ensureActiveAdminInvariant(txn, user: user, nextActive: active);
      await txn.update(
        DatabaseSchema.usersTable,
        {
          'activo': active ? 1 : 0,
          'sync_status': DatabaseSchema.syncStatusPending,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
    _scheduleUserSync('set-user-active:$userId');
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
    if (!_verifyStoredPassword(normalizedCurrentPassword, user.passwordHash)) {
      throw const AuthException('La contraseña actual no es correcta.');
    }

    final now = DateTime.now().toIso8601String();
    await db.update(
      DatabaseSchema.usersTable,
      {
        'password_hash': PasswordHasher.hashPassword(normalizedNewPassword),
        'password_reset_required': 0,
        'sync_status': DatabaseSchema.syncStatusPending,
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

    _scheduleUserSync('change-password:$userId');

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
          ? 'LOWER(email) = ? AND deleted_at IS NULL'
          : 'LOWER(email) = ? AND id != ? AND deleted_at IS NULL',
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

  Future<AdminRecoveryCredentials?> _tryReadAdminRecoverySnapshot(
    DatabaseExecutor db,
    String recoveryCode,
  ) async {
    try {
      return await _readAdminRecoverySnapshot(db, recoveryCode);
    } on AuthException {
      return null;
    } on FormatException {
      return null;
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
      final currentSnapshot = await _tryReadAdminRecoverySnapshot(
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

  // ---------------------------------------------------------------------------
  // JWT-based session restore
  // ---------------------------------------------------------------------------

  /// Validates the stored JWT against [/auth/me] and, if successful, refreshes
  /// the local user cache and creates a new local session — without requiring
  /// the plaintext password.  Returns [null] when the token is absent, expired,
  /// or the user has no prior cached record on this device.
  Future<UserModel?> _restoreSessionFromJwt() async {
    final settings = await _syncConfigRepository.loadSettings();
    final jwt = settings.jwtToken.trim();
    if (jwt.isEmpty) {
      debugPrint('[JWT] No hay token almacenado.');
      return null;
    }

    debugPrint('[JWT] Token encontrado. Validando con /auth/me...');
    try {
      final payload = await _sendJsonRequest(
        method: 'GET',
        uri: Uri.parse('${settings.normalizedBaseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $jwt'},
      );
      debugPrint('[JWT] /auth/me exitoso para ${payload["email"]}.');
      return await _refreshLocalUserFromJwtPayload(payload);
    } on AuthException catch (e) {
      debugPrint(
        '[JWT] Token invalido (${e.message}). Eliminando JWT guardado.',
      );
      await _syncConfigRepository.clearJwtToken();
      return null;
    } catch (e) {
      debugPrint('[JWT] Error al validar token: $e');
      return null;
    }
  }

  /// Refreshes or creates the local user from a [/auth/me] payload, without
  /// touching the stored password hash.  Returns [null] when no prior local user
  /// record can be found for this device (first-ever login is still required).
  Future<UserModel?> _refreshLocalUserFromJwtPayload(
    Map<String, dynamic> payload,
  ) async {
    final remoteAuthId = payload['sub']?.toString().trim();
    final email = payload['email']?.toString().trim().toLowerCase() ?? '';
    if (remoteAuthId == null || remoteAuthId.isEmpty || email.isEmpty) {
      debugPrint('[JWT] Payload de /auth/me incompleto.');
      return null;
    }

    final db = await _appDatabase.database;
    final role = _mapRemoteRole(payload['roles']);
    final permissions = role == UserRole.admin
        ? _fullPermissions()
        : _mapRemotePermissions(payload['permissions']);
    final fullName = payload['fullName']?.toString().trim();
    final username = payload['username']?.toString().trim();
    final now = DateTime.now();

    final localUserId = await db.transaction<int?>((txn) async {
      final byRemoteId = await txn.query(
        DatabaseSchema.usersTable,
        columns: ['id', 'fecha_creacion'],
        where: 'remote_auth_id = ?',
        whereArgs: [remoteAuthId],
        limit: 1,
      );
      final byEmail = byRemoteId.isEmpty
          ? await txn.query(
              DatabaseSchema.usersTable,
              columns: ['id', 'fecha_creacion'],
              where: 'LOWER(email) = ?',
              whereArgs: [email],
              limit: 1,
            )
          : const <Map<String, Object?>>[];

      final existing = byRemoteId.isNotEmpty
          ? byRemoteId.first
          : (byEmail.isNotEmpty ? byEmail.first : null);

      if (existing == null) {
        // Usuario nunca ha iniciado sesión en esta PC — login manual requerido.
        debugPrint(
          '[JWT] Usuario $email no encontrado localmente. '
          'Se requiere login manual.',
        );
        return null;
      }

      final userId = existing['id'] as int;
      await txn.update(
        DatabaseSchema.usersTable,
        {
          'remote_auth_id': remoteAuthId,
          'nombre':
              (fullName?.isNotEmpty == true ? fullName : username) ?? email,
          'email': email,
          'password_reset_required': 0,
          'rol': role.storageValue,
          'activo': payload['isActive'] == false ? 0 : 1,
          'auth_source': AuthSource.cloud.storageValue,
          'last_online_login_at': now.toIso8601String(),
          'sync_status': DatabaseSchema.syncStatusSynced,
          'fecha_actualizacion': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      await _replacePermissions(txn, userId, permissions);

      // Crear nueva sesion local ligada a este usuario.
      await txn.delete(
        DatabaseSchema.authSessionsTable,
        where: 'usuario_id = ?',
        whereArgs: [userId],
      );
      await _persistSession(txn, userId);
      return userId;
    });

    if (localUserId == null) return null;
    return getUserById(localUserId);
  }

  // ---------------------------------------------------------------------------

  Future<_RemoteSystemStatus> _fetchRemoteSystemStatus() async {
    try {
      final settings = await _syncConfigRepository.loadSettings();
      final uri = Uri.parse('${settings.normalizedBaseUrl}/system/status');
      if (uri.host.trim().isEmpty) {
        return const _RemoteSystemStatus(
          isReachable: false,
          initialized: false,
          statusAvailable: false,
          connectionStatus: BackendConnectionStatus.unreachable,
          message: serverConnectionErrorMessage,
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
        final healthUri = Uri.parse(
          '${settings.normalizedBaseUrl}/system/config',
        );
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
            message: serverConnectionErrorMessage,
          );
        }
      }
    } on SocketException {
      return const _RemoteSystemStatus(
        isReachable: false,
        initialized: false,
        statusAvailable: false,
        connectionStatus: BackendConnectionStatus.unreachable,
        message: serverConnectionErrorMessage,
      );
    } catch (_) {
      return const _RemoteSystemStatus(
        isReachable: false,
        initialized: false,
        statusAvailable: false,
        connectionStatus: BackendConnectionStatus.unreachable,
        message: serverConnectionErrorMessage,
      );
    }
  }

  Future<Map<String, dynamic>> _sendJsonRequest({
    required String method,
    required Uri uri,
    Map<String, Object?>? payload,
    Map<String, String>? headers,
  }) async {
    final request = await _openRequest(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (headers != null) {
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
    }
    if (payload != null) {
      request.write(jsonEncode(payload));
    }

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final decoded = body.trim().isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body);
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

  Future<void> _bootstrapRemoteSystemIfNeeded({
    required String companyName,
    required String nombre,
    required String email,
    required String password,
  }) async {
    final remoteStatus = await _fetchRemoteSystemStatus();
    if (!remoteStatus.isReachable ||
        !remoteStatus.statusAvailable ||
        remoteStatus.initialized) {
      return;
    }

    try {
      final settings = await _syncConfigRepository.loadSettings();
      await _sendJsonRequest(
        method: 'POST',
        uri: Uri.parse('${settings.normalizedBaseUrl}/system/setup'),
        payload: {
          'company': {'name': companyName},
          'admin': {
            'fullName': nombre,
            'email': email,
            'username': email.split('@').first,
            'password': password,
          },
        },
      );
    } on AuthException {
      // Local-first setup must stay available even if remote bootstrap fails.
    } on SocketException {
      // The user can continue locally and reauthenticate online later.
    }
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
        'sync_id': existing == null ? _nextUserSyncId() : null,
        'nombre': (fullName?.isNotEmpty == true ? fullName : username) ?? email,
        'email': email,
        'password_hash': passwordHash,
        'password_reset_required': 0,
        'rol': role.storageValue,
        'activo': payload['isActive'] == false ? 0 : 1,
        'auth_source': AuthSource.cloud.storageValue,
        'last_online_login_at': now.toIso8601String(),
        'sync_status': DatabaseSchema.syncStatusSynced,
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
        DatabaseSchema.syncQueueTable,
        where: 'scope = ? AND record_sync_id = ?',
        whereArgs: [
          'users',
          (existing == null
                      ? values['sync_id']
                      : await _readExistingUserSyncId(txn, userId))
                  ?.toString() ??
              '',
        ],
      );
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

  Future<String?> _readExistingUserSyncId(
    DatabaseExecutor db,
    int userId,
  ) async {
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return (rows.first['sync_id'] as String?)?.trim();
  }

  Future<List<UserModel>> _fetchUsersFromBackend() async {
    final response = await _apiClient.get('/users');
    final items = response is List
        ? response
        : ((response is Map<String, dynamic> ? response['items'] : null)
                  as List?) ??
              const [];
    return items
        .whereType<Map>()
        .map(
          (item) => _mapBackendUser(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<UserModel> _createUserInBackend({
    required String nombre,
    required String email,
    required String password,
    required UserRole role,
    required List<PermissionModel> permissions,
    required bool active,
  }) async {
    final response = await _apiClient.post(
      '/users',
      body: {
        'email': email,
        'username': _buildUsernameFromEmail(email),
        'fullName': nombre,
        'password': password,
        'isActive': active,
        'roleCode': _roleCodeFor(role, permissions),
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    return _mapBackendUser(payload, fallbackPassword: password);
  }

  Future<UserModel> _updateUserInBackend({
    required UserModel user,
    required String nombre,
    required String email,
    required UserRole role,
    required bool active,
    required List<PermissionModel> permissions,
    String? newPassword,
  }) async {
    final remoteUserId = await _resolveRemoteUserId(user.id);
    if (remoteUserId == null || remoteUserId.isEmpty) {
      throw const AuthException('No se pudo identificar el usuario remoto.');
    }
    final response = await _apiClient.patch(
      '/users/$remoteUserId',
      body: {
        'email': email,
        'username': _buildUsernameFromEmail(email),
        'fullName': nombre,
        if (newPassword != null && newPassword.isNotEmpty)
          'password': newPassword,
        'isActive': active,
        'roleCode': _roleCodeFor(role, permissions),
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    return _mapBackendUser(
      payload,
      fallbackPassword: (newPassword != null && newPassword.isNotEmpty)
          ? newPassword
          : user.passwordHash,
      passwordIsPlaintext: newPassword != null && newPassword.isNotEmpty,
    );
  }

  Future<void> _deleteUserInBackend(int userId) async {
    final remoteUserId = await _resolveRemoteUserId(userId);
    if (remoteUserId == null || remoteUserId.isEmpty) {
      return;
    }
    await _apiClient.delete('/users/$remoteUserId');
  }

  Future<UserModel> _setUserActiveInBackend({
    required UserModel user,
    required bool active,
  }) async {
    final remoteUserId = await _resolveRemoteUserId(user.id);
    if (remoteUserId == null || remoteUserId.isEmpty) {
      throw const AuthException('No se pudo identificar el usuario remoto.');
    }
    final response = await _apiClient.patch(
      '/users/$remoteUserId',
      body: {'isActive': active},
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    return _mapBackendUser(payload, fallbackPassword: user.passwordHash);
  }

  Future<String?> _resolveRemoteUserId(int? userId) async {
    if (userId == null) {
      return null;
    }
    final fromRegistry = _idRegistry.resolveRemoteId('users', userId);
    if (fromRegistry != null && fromRegistry.isNotEmpty) {
      return fromRegistry;
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['remote_auth_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final remoteId = (rows.first['remote_auth_id'] as String?)?.trim();
    if (remoteId == null || remoteId.isEmpty) {
      return null;
    }
    _idRegistry.register('users', remoteId);
    return remoteId;
  }

  UserModel _mapBackendUser(
    Map<String, dynamic> payload, {
    String? fallbackPassword,
    bool passwordIsPlaintext = true,
  }) {
    final remoteId =
        payload['id']?.toString().trim() ??
        payload['sub']?.toString().trim() ??
        payload['remote_auth_id']?.toString().trim() ??
        '';
    if (remoteId.isEmpty) {
      throw const AuthException('La API no devolvio un id de usuario valido.');
    }
    final role = _mapRemoteRole(payload['roleCodes'] ?? payload['roles']);
    final permissions = role == UserRole.admin
        ? _fullPermissions()
        : _mapRemotePermissions(payload['permissions']);
    final createdAt =
        DateTime.tryParse(payload['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final updatedAt =
        DateTime.tryParse(payload['updatedAt']?.toString() ?? '') ?? createdAt;
    final resolvedPassword = fallbackPassword == null
        ? ''
        : (passwordIsPlaintext
              ? PasswordHasher.hashPassword(fallbackPassword)
              : fallbackPassword);
    return UserModel(
      id: _idRegistry.register('users', remoteId),
      remoteAuthId: remoteId,
      nombre:
          payload['fullName']?.toString() ??
          payload['username']?.toString() ??
          '',
      email: payload['email']?.toString() ?? '',
      passwordHash: resolvedPassword,
      passwordResetRequired: false,
      role: role,
      permissions: permissions,
      activo: payload['isActive'] != false,
      fechaCreacion: createdAt,
      fechaActualizacion: updatedAt,
      authSource: AuthSource.cloud,
      telefono: payload['phone']?.toString(),
    );
  }

  String _buildUsernameFromEmail(String email) {
    final localPart = email.split('@').first.trim().toLowerCase();
    return localPart.isEmpty ? 'usuario' : localPart;
  }

  String _roleCodeFor(UserRole role, List<PermissionModel> permissions) {
    if (role == UserRole.admin) {
      return 'ADMIN';
    }
    final canManageSales = permissions.any(
      (permission) =>
          permission.module == PermissionCatalog.sales &&
          (permission.create || permission.update || permission.delete),
    );
    return canManageSales ? 'SALES_AGENT' : 'PANEL_VIEWER';
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
    await SettingsRepository(
      appDatabase: _appDatabase,
    ).upsert(SettingsRepository.businessNameKey, companyName);
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
      where: 'LOWER(email) = ? AND deleted_at IS NULL',
      whereArgs: [identifier],
      limit: 1,
    );

    if (rows.isEmpty) {
      rows = await db.query(
        DatabaseSchema.usersTable,
        where: 'LOWER(nombre) = ? AND deleted_at IS NULL',
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

    final syncService = SyncService(
      repositories: [
        UsersSyncRepository(appDatabase: _appDatabase),
        ClientRepository(
          appDatabase: _appDatabase,
          syncQueueService: _syncQueueService,
        ),
        ProductsSyncRepository(appDatabase: _appDatabase),
        SellerRepository(
          database: _appDatabase,
          syncQueueService: _syncQueueService,
        ),
        SalesSyncRepository(appDatabase: _appDatabase),
        InstallmentsSyncRepository(appDatabase: _appDatabase),
        PaymentsSyncRepository(appDatabase: _appDatabase),
      ],
      configRepository: _syncConfigRepository,
      apiClient: SyncApiClient(httpClient: _httpClient),
      syncQueueService: _syncQueueService,
    );
    final report = await syncService.syncNow(forceFullDownload: true);
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
      'WHERE rol = ? AND activo = 1 AND deleted_at IS NULL AND id != ?',
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

  void _scheduleUserSync(String operationLabel) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    unawaited(_runUserSync(operationLabel));
  }

  Future<void> _runUserSync(String operationLabel) async {
    try {
      await _syncQueueService.refreshScope(_usersSyncRepository.scope);
      await _syncQueueService.processQueue(includeDeferred: true);
    } catch (_) {
      // The retry queue handles later attempts when the backend is unavailable.
    }
  }

  String _nextUserSyncId() => SyncIdGenerator.next('user');

  String _resolveUserSyncId(int userId) => 'user-$userId';
}
