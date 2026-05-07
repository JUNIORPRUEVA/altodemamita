import 'package:flutter/foundation.dart';

import '../../../app/navigation/app_module.dart';
import '../../../core/system/system_config_service.dart';
import '../data/auth_service.dart';
import '../domain/permission_model.dart';
import '../domain/user_model.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService})
    : _authService = authService ?? AuthService();

  static const Duration _adminOverrideLifetime = Duration(minutes: 10);
  static const Set<String> _localFirstModules = {
    PermissionCatalog.clients,
    PermissionCatalog.lots,
    PermissionCatalog.sales,
    PermissionCatalog.payments,
    PermissionCatalog.installments,
    PermissionCatalog.sellers,
  };

  final AuthService _authService;
  final Map<String, DateTime> _adminOverrideExpirations = {};

  bool _isInitializing = true;
  bool _isSigningIn = false;
  bool _requiresInitialSetup = false;
  bool _isOnline = false;
  bool _isCloudInitialized = true;
  bool _isCloudSessionExpired = false;
  BackendConnectionStatus _backendStatus = BackendConnectionStatus.unreachable;
  String? _backendStatusMessage;
  UserModel? _currentUser;
  String? _errorMessage;
  String? _lastGeneratedRecoveryCode;

  bool get isInitializing => _isInitializing;
  bool get isSigningIn => _isSigningIn;
  bool get requiresInitialSetup => _requiresInitialSetup;
  bool get isOnline => _isOnline;
  bool get isCloudInitialized => _isCloudInitialized;

  /// Verdadero cuando el JWT venció o fue rechazado por el backend.
  /// El usuario sigue autenticado localmente; solo la sync en la nube está bloqueada.
  bool get isCloudSessionExpired => _isCloudSessionExpired;
  BackendConnectionStatus get backendStatus => _backendStatus;
  String? get backendStatusMessage => _backendStatusMessage;
  bool get isAuthenticated => _currentUser != null;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isReadOnly => SystemConfigService.instance.isReadOnly;
  AuthService get authService => _authService;
  String? get lastGeneratedRecoveryCode => _lastGeneratedRecoveryCode;

  /// Marca la sesión en la nube como expirada sin cerrar la sesión local.
  /// Lllamado cuando el backend responde 401 durante una sincronización.
  void markCloudSessionExpired() {
    if (_isCloudSessionExpired) return;
    _isCloudSessionExpired = true;
    _isOnline = false;
    _backendStatus = BackendConnectionStatus.unreachable;
    notifyListeners();
  }

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();
    try {
      final bootstrap = await _authService.bootstrap();
      await SystemConfigService.instance.refresh();
      _requiresInitialSetup = bootstrap.requiresInitialSetup;
      _isOnline = bootstrap.isOnline;
      _isCloudInitialized = bootstrap.isCloudInitialized;
      _isCloudSessionExpired = false;
      _backendStatus = bootstrap.backendStatus;
      _backendStatusMessage = bootstrap.backendStatusMessage;
      _clearAdminOverrides(notify: false);
      if (_requiresInitialSetup) {
        await _authService.clearSession();
        _currentUser = null;
      } else {
        _currentUser = bootstrap.currentUser;
      }
      _errorMessage = null;
    } catch (_) {
      _currentUser = null;
      _requiresInitialSetup = false;
      _isOnline = false;
      _isCloudInitialized = true;
      _backendStatus = BackendConnectionStatus.unreachable;
      _backendStatusMessage = 'No se pudo verificar el backend.';
      _errorMessage = 'No se pudo restaurar la sesion.';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    if (_requiresInitialSetup) {
      _errorMessage = 'Completa la configuracion inicial del administrador.';
      notifyListeners();
      return false;
    }

    _isSigningIn = true;
    _errorMessage = null;
    final previousUser = _currentUser;
    notifyListeners();

    try {
      _clearAdminOverrides(notify: false);
      final result = await _authService.signInHybrid(
        email: email,
        password: password,
      );
      await SystemConfigService.instance.refresh();
      _currentUser = result.user;
      _requiresInitialSetup = false;
      _isCloudInitialized = true;
      _isCloudSessionExpired = false;
      _isOnline = result.mode == AuthSignInMode.online;
      if (_isOnline) {
        _backendStatus = BackendConnectionStatus.connected;
        _backendStatusMessage = null;
      } else {
        _backendStatus = BackendConnectionStatus.unreachable;
        _backendStatusMessage = null;
      }
      return true;
    } on AuthException catch (error) {
      _currentUser = previousUser;
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _currentUser = previousUser;
      _errorMessage = 'No se pudo iniciar sesion en este momento.';
      return false;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<bool> completeInitialSetup({
    required String companyName,
    required String nombre,
    required String email,
    required String password,
    required String recoveryCode,
  }) async {
    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _clearAdminOverrides(notify: false);
      _lastGeneratedRecoveryCode = await _authService.completeInitialSetup(
        companyName: companyName,
        nombre: nombre,
        email: email,
        password: password,
        recoveryCode: recoveryCode,
      );
      _requiresInitialSetup = false;
      final result = await _authService.signInHybrid(
        email: email,
        password: password,
      );
      await SystemConfigService.instance.refresh();
      _currentUser = result.user;
      _isOnline = result.mode == AuthSignInMode.online;
      _isCloudInitialized = true;
      if (_isOnline) {
        _backendStatus = BackendConnectionStatus.connected;
        _backendStatusMessage = null;
      } else {
        _backendStatus = BackendConnectionStatus.unreachable;
        _backendStatusMessage = null;
      }
      return true;
    } on AuthException catch (error) {
      _currentUser = null;
      // Si la nube ya estaba inicializada, la PC nueva debe ir al login.
      final msg = error.message.toLowerCase();
      if (msg.contains('ya fue inicializado') ||
          msg.contains('ya fue configurado') ||
          msg.contains('already initialized')) {
        _requiresInitialSetup = false;
        _errorMessage = null;
      } else {
        _errorMessage = error.message;
      }
      return false;
    } catch (_) {
      _currentUser = null;
      _errorMessage = 'No se pudo completar la configuracion inicial.';
      return false;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  /// Descarta la pantalla de setup y va al login.
  /// Útil cuando la PC es nueva pero la nube ya está inicializada.
  void skipSetupToLogin() {
    _requiresInitialSetup = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Re-ejecuta la inicialización para volver a verificar el backend.
  Future<void> retryInitialize() => initialize();

  Future<bool> recoverAdminAccess({
    required String recoveryCode,
    required String nombre,
    required String email,
    required String password,
  }) async {
    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _clearAdminOverrides(notify: false);
      _currentUser = await _authService.recoverAdminAccess(
        recoveryCode: recoveryCode,
        nombre: nombre,
        email: email,
        newPassword: password,
      );
      _requiresInitialSetup = false;
      return true;
    } on AuthException catch (error) {
      _currentUser = null;
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _currentUser = null;
      _errorMessage = 'No se pudo recuperar el acceso en este momento.';
      return false;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  /// Obtiene un JWT de sync desde la nube SIN cambiar la sesión local activa.
  /// Útil cuando el usuario local no tiene credenciales en la nube
  /// (configuración inicial realizada sin conexión a internet).
  /// Retorna null en caso de éxito o un mensaje de error.
  Future<String?> connectToCloud({
    required String email,
    required String password,
  }) async {
    try {
      final linkedUser = await _authService.connectToCloudForSync(
        email: email,
        password: password,
      );
      _currentUser = linkedUser;
      _isOnline = true;
      _isCloudSessionExpired = false;
      _backendStatus = BackendConnectionStatus.connected;
      _backendStatusMessage = null;
      notifyListeners();
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'No se pudo conectar con la nube. Verifica las credenciales.';
    }
  }

  Future<AdminRecoveryCredentials?> revealAdminCredentials({
    required String recoveryCode,
  }) async {
    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await _authService.revealAdminCredentials(
        recoveryCode: recoveryCode,
      );
    } on AuthException catch (error) {
      _errorMessage = error.message;
      return null;
    } catch (_) {
      _errorMessage = 'No se pudieron consultar los datos de acceso.';
      return null;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _clearAdminOverrides(notify: false);
    _currentUser = null;
    _isCloudSessionExpired = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw const AuthException('No hay una sesión activa.');
    }

    _currentUser = await _authService.changeOwnPassword(
      userId: userId,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      return;
    }

    _currentUser = await _authService.getUserById(userId);
    if (_currentUser == null ||
        !_currentUser!.activo ||
        _currentUser!.passwordResetRequired) {
      _clearAdminOverrides(notify: false);
      _currentUser = null;
      await _authService.clearSession();
    }
    notifyListeners();
  }

  bool hasAdminOverride(String scope) {
    final user = _currentUser;
    if (user == null) {
      return false;
    }
    if (user.isAdmin) {
      return true;
    }

    final expiration = _adminOverrideExpirations[scope];
    if (expiration == null) {
      return false;
    }
    return expiration.isAfter(DateTime.now());
  }

  bool hasScopedAccess({
    required String scope,
    required String module,
    required PermissionAction action,
  }) {
    if (_blocksWriteByDevice(action: action)) {
      return false;
    }

    if (_blocksActionInReadOnly(module: module, action: action)) {
      return false;
    }

    final user = _currentUser;
    if (user == null) {
      return false;
    }
    if (user.allows(module, action)) {
      return true;
    }
    return hasAdminOverride(scope);
  }

  Future<bool> authorizeAdminOverride({
    required String scope,
    required String password,
  }) async {
    if (!SystemConfigService.instance.canWrite) {
      return false;
    }

    if (isReadOnly && !_localFirstModules.contains(scope)) {
      return false;
    }

    final user = _currentUser;
    if (user == null) {
      return false;
    }
    if (user.isAdmin || hasAdminOverride(scope)) {
      return true;
    }

    final isValid = await _authService.verifyAdminPassword(password: password);
    if (!isValid) {
      return false;
    }

    _adminOverrideExpirations[scope] = DateTime.now().add(
      _adminOverrideLifetime,
    );
    notifyListeners();
    return true;
  }

  void clearAdminOverrides() {
    _clearAdminOverrides();
  }

  void _clearAdminOverrides({bool notify = true}) {
    if (_adminOverrideExpirations.isEmpty) {
      return;
    }
    _adminOverrideExpirations.clear();
    if (notify) {
      notifyListeners();
    }
  }

  bool canAccess(String module, PermissionAction action) {
    if (_blocksWriteByDevice(action: action)) {
      return false;
    }

    if (_blocksActionInReadOnly(module: module, action: action)) {
      return false;
    }

    final user = _currentUser;
    if (user == null) {
      return false;
    }
    return user.allows(module, action);
  }

  bool canReadModule(String module) {
    return canAccess(module, PermissionAction.read);
  }

  bool canAccessModule(AppModule module, PermissionAction action) {
    return canAccess(module.permissionKey, action);
  }

  bool _blocksActionInReadOnly({
    required String module,
    required PermissionAction action,
  }) {
    if (!isReadOnly || action == PermissionAction.read) {
      return false;
    }

    return !_localFirstModules.contains(module);
  }

  bool _blocksWriteByDevice({required PermissionAction action}) {
    return action != PermissionAction.read &&
        !SystemConfigService.instance.canWrite;
  }
}
