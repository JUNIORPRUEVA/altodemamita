import 'package:flutter/foundation.dart';
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
    return AuthUser(
      id: json['sub']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
        type: json['type']?.toString() == 'panel' ? 'panel' : 'desktop',
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
    _apiClient.setUnauthorizedHandler(_handleUnauthorized);
  }

  static const _jwtStorageKey = 'panel.jwt';

  final ApiClient _apiClient;
  final RealtimeController _realtimeController;
  final SystemConfigController _systemConfigController;
  final SecureTokenStorage _tokenStorage;

  bool _initialized = false;
  bool _busy = false;
  bool _processingUnauthorized = false;
  String? _jwtToken;
  AuthUser? _user;
  String? _errorMessage;

  bool get initialized => _initialized;
  bool get isBusy => _busy;
  bool get isAuthenticated =>
      _jwtToken?.isNotEmpty == true && _user != null && _user!.type == 'panel';
  AuthUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get canManageUsers => isPanelAdmin;
  bool get canAccessSettings => isPanelAdmin;
  bool get canAccessSales => hasPermission('sales.read') || isPanelAdmin;
  bool get isPanelAdmin =>
      _user != null && _user!.type == 'panel' && _user!.panelRole == PanelRole.admin;

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
      await _systemConfigController.refresh();
      final profile = await _apiClient.get('/auth/me');
      _user = AuthUser.fromMap(profile as Map<String, dynamic>);
      if (_user!.type != 'panel') {
        throw ApiException('El token no corresponde a un cliente panel.');
      }
      await _realtimeController.connect(storedToken);
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
  }) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.post(
        '/auth/login',
        authorized: false,
        body: {
          'identifier': identifier.trim(),
          'password': password,
          'clientType': 'panel',
        },
      ) as Map<String, dynamic>;

      final token = response['accessToken']?.toString() ?? '';
      final userMap = response['user'] as Map<String, dynamic>? ?? const {};
      if (token.isEmpty) {
        throw ApiException('El backend no devolvio un JWT valido.');
      }

      _jwtToken = token;
      _user = AuthUser.fromMap(userMap);
      if (_user!.type != 'panel') {
        throw ApiException('El backend no emitio un token de panel valido.');
      }
      _apiClient.setJwtToken(token);

      await _tokenStorage.writeToken(_jwtStorageKey, token);
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

  Future<void> signOut({bool notify = true}) async {
    _jwtToken = null;
    _user = null;
    _errorMessage = null;
    _apiClient.setJwtToken(null);
    _realtimeController.disconnect();
    await _tokenStorage.clearToken(_jwtStorageKey);
    if (notify) {
      notifyListeners();
    }
  }

  bool hasPermission(String code) {
    return _user?.permissions.contains(code) ?? false;
  }

  Future<void> _handleUnauthorized() async {
    if (_processingUnauthorized) {
      return;
    }

    _processingUnauthorized = true;
    try {
      developer.log(
        'Received 401 from backend. Clearing session and returning to login.',
        name: 'SistemaSolares.Auth',
      );
      await signOut();
    } finally {
      _processingUnauthorized = false;
    }
  }
}