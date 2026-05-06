import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/core/security/secure_token_storage.dart';
import 'package:sistema_solares_ui/core/system/system_config_controller.dart';

enum PanelRole { admin, viewer }

class AuthUser {
  AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.type,
    required this.roles,
    required this.permissions,
    required this.isActive,
  });

  final String id;
  final String email;
  final String username;
  final String fullName;
  final String type;
  final List<String> roles;
  final List<String> permissions;
  final bool isActive;

  PanelRole get panelRole {
    if (roles.contains('PANEL_ADMIN') ||
        roles.contains('SUPER_ADMIN') ||
        roles.contains('ADMIN') ||
        permissions.contains('system.config') ||
        permissions.contains('users.write') ||
        permissions.contains('auth.manage')) {
      return PanelRole.admin;
    }
    return PanelRole.viewer;
  }

  factory AuthUser.fromMap(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    return AuthUser(
      id: json['sub']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
        type: rawType == 'panel'
          ? 'panel'
          : rawType == 'pwa'
          ? 'pwa'
          : 'desktop',
      roles: (json['roles'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      permissions: (json['permissions'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      isActive: json['isActive'] == true,
    );
  }
}

class AuthController extends ChangeNotifier {
  AuthController({
    required ApiClient apiClient,
    required RealtimeController realtimeController,
    required SystemConfigController systemConfigController,
    SecureTokenStorage? tokenStorage,
  }) : _apiClient = apiClient,
       _realtimeController = realtimeController,
       _systemConfigController = systemConfigController,
       _tokenStorage = tokenStorage ?? SecureTokenStorage() {
    _apiClient.setUnauthorizedHandlerV2(_handleUnauthorized);
    _apiClient.setEnsureValidTokenHandler(_ensureValidToken);
  }

  static const _jwtStorageKey = 'panel.jwt';
  static const _userStorageKey = 'panel.user.basic';
  static const _rememberMeStorageKey = 'panel.remember_me';
  static const Duration _refreshThreshold = Duration(hours: 6);

  final ApiClient _apiClient;
  final RealtimeController _realtimeController;
  final SystemConfigController _systemConfigController;
  final SecureTokenStorage _tokenStorage;

  bool _initialized = false;
  bool _busy = false;
  bool _processingUnauthorized = false;
  bool _refreshingToken = false;
  String? _jwtToken;
  AuthUser? _user;
  String? _errorMessage;

  bool get initialized => _initialized;
  bool get isBusy => _busy;
  bool get isAuthenticated =>
      _jwtToken?.isNotEmpty == true &&
      _user != null &&
      (_user!.type == 'panel' || _user!.type == 'pwa');
  AuthUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get canManageUsers => isPanelAdmin;
  bool get canAccessSettings => isPanelAdmin;
  bool get canAccessSales => hasPermission('sales.read') || isPanelAdmin;
  bool get canAccessPayments => hasPermission('payments.read') || isPanelAdmin;
  bool get canAccessSellers => hasPermission('sellers.read') || isPanelAdmin;
  bool get canAccessGlobalSearch =>
      hasPermission('clients.read') ||
      hasPermission('sales.read') ||
      hasPermission('products.read') ||
      canAccessPayments ||
      canAccessSellers ||
      isPanelAdmin;
  bool get isPanelAdmin =>
      _user != null &&
      (_user!.type == 'panel' || _user!.type == 'pwa') &&
      _user!.panelRole == PanelRole.admin;

  Future<void> initialize() async {
    try {
      final storedToken = await _tokenStorage.readToken(_jwtStorageKey);
      if (storedToken == null || storedToken.isEmpty) {
        developer.log(
          'No stored panel token found. Staying on login route.',
          name: 'SistemaSolares.Auth',
        );
        _initialized = true;
        notifyListeners();
        return;
      }

      _jwtToken = storedToken;
      _apiClient.setJwtToken(storedToken);

      await _ensureValidToken();
      await _systemConfigController.refresh();
      final profile = await _apiClient.get('/auth/me');
      _user = AuthUser.fromMap(profile as Map<String, dynamic>);
      if (_user!.type != 'panel' && _user!.type != 'pwa') {
        throw ApiException('El token no corresponde a un cliente panel.');
      }
      await _storeUserBasic(_user!);
      final currentToken = _jwtToken;
      if (currentToken != null && currentToken.isNotEmpty) {
        await _realtimeController.connect(currentToken);
      }
      developer.log(
        'Existing session restored for ${_user?.username ?? _user?.email ?? 'unknown-user'}.',
        name: 'SistemaSolares.Auth',
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to restore panel session. Signing out.',
        name: 'SistemaSolares.Auth',
        error: error,
        stackTrace: stackTrace,
      );
      await signOut(notify: false);
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
    bool rememberMe = true,
  }) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await setRememberMe(rememberMe);
      final response =
          await _apiClient.post(
                '/auth/login',
                authorized: false,
                body: {
                  'identifier': identifier.trim(),
                  'password': password,
                  'clientType': 'pwa',
                },
              )
              as Map<String, dynamic>;

      final token = response['accessToken']?.toString() ?? '';
      final userMap = response['user'] as Map<String, dynamic>? ?? const {};
      if (token.isEmpty) {
        throw ApiException('El backend no devolvio un JWT valido.');
      }

      _jwtToken = token;
      _user = AuthUser.fromMap(userMap);
      if (_user!.type != 'panel' && _user!.type != 'pwa') {
        throw ApiException('El backend no emitio un token de panel valido.');
      }
      _apiClient.setJwtToken(token);

      await _tokenStorage.writeToken(_jwtStorageKey, token);
      await _storeUserBasic(_user!);
      await _systemConfigController.refresh();
      await _realtimeController.connect(token);
      developer.log(
        'Panel sign-in completed for ${_user?.username ?? _user?.email ?? 'unknown-user'}.',
        name: 'SistemaSolares.Auth',
      );
    } on ApiException catch (error) {
      _errorMessage = error.message;
      developer.log(
        'Panel sign-in rejected: ${error.message}',
        name: 'SistemaSolares.Auth',
      );
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> getRememberMe() async {
    final raw = await _tokenStorage.readToken(_rememberMeStorageKey);
    if (raw == null) {
      return true;
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  Future<void> setRememberMe(bool enabled) {
    return _tokenStorage.writeToken(
      _rememberMeStorageKey,
      enabled ? '1' : '0',
    );
  }

  Future<void> signOut({bool notify = true}) async {
    _jwtToken = null;
    _user = null;
    _errorMessage = null;
    _apiClient.setJwtToken(null);
    _realtimeController.disconnect();
    await _tokenStorage.clearToken(_jwtStorageKey);
    await _tokenStorage.clearToken(_userStorageKey);
    if (notify) {
      notifyListeners();
    }
  }

  bool hasPermission(String code) {
    return _user?.permissions.contains(code) ?? false;
  }

  Future<void> _storeUserBasic(AuthUser user) async {
    final role = user.panelRole == PanelRole.admin ? 'admin' : 'viewer';
    final payload = jsonEncode({
      'id': user.id,
      'email': user.email,
      'role': role,
    });
    await _tokenStorage.writeToken(_userStorageKey, payload);
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      final bytes = base64Url.decode(normalized);
      final jsonText = utf8.decode(bytes);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isTokenExpiringSoon(String token, Duration threshold) {
    final payload = _decodeJwtPayload(token);
    if (payload == null) {
      return false;
    }
    final expRaw = payload['exp'];
    final expSeconds = expRaw is num ? expRaw.toInt() : int.tryParse('$expRaw');
    if (expSeconds == null) {
      return false;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000);
    return expiresAt.isBefore(DateTime.now().add(threshold));
  }

  Future<void> _ensureValidToken() async {
    final token = _jwtToken;
    if (token == null || token.isEmpty) {
      return;
    }
    if (_refreshingToken) {
      return;
    }
    if (!_isTokenExpiringSoon(token, _refreshThreshold)) {
      return;
    }

    await _refreshTokenInternal(reason: 'preflight');
  }

  Future<bool> _handleUnauthorized() async {
    if (_processingUnauthorized) {
      return false;
    }

    _processingUnauthorized = true;
    try {
      developer.log(
        'Received 401 from backend. Attempting token refresh.',
        name: 'SistemaSolares.Auth',
      );
      final refreshed = await _refreshTokenInternal(reason: '401');
      if (refreshed) {
        return true;
      }

      developer.log(
        'Token refresh failed. Clearing session and returning to login.',
        name: 'SistemaSolares.Auth',
      );
      await signOut();
      return false;
    } finally {
      _processingUnauthorized = false;
    }
  }

  Future<bool> _refreshTokenInternal({required String reason}) async {
    final currentToken = _jwtToken;
    if (currentToken == null || currentToken.isEmpty) {
      return false;
    }
    if (_refreshingToken) {
      return false;
    }

    _refreshingToken = true;
    try {
      final response =
          await _apiClient.post(
                '/auth/refresh',
                authorized: false,
                body: {'token': currentToken, 'clientType': 'pwa'},
              )
              as Map<String, dynamic>;

      final newToken = response['accessToken']?.toString() ?? '';
      final userMap = response['user'] as Map<String, dynamic>? ?? const {};
      if (newToken.isEmpty) {
        return false;
      }

      _jwtToken = newToken;
      _apiClient.setJwtToken(newToken);
      await _tokenStorage.writeToken(_jwtStorageKey, newToken);

      final newUser = AuthUser.fromMap(userMap);
      if (newUser.type == 'panel' || newUser.type == 'pwa') {
        _user = newUser;
        await _storeUserBasic(newUser);
      }

      if (_realtimeController.isConnected) {
        await _realtimeController.connect(newToken);
      }

      developer.log(
        'Token refreshed successfully ($reason).',
        name: 'SistemaSolares.Auth',
      );
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Token refresh failed ($reason).',
        name: 'SistemaSolares.Auth',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _refreshingToken = false;
    }
  }
}
