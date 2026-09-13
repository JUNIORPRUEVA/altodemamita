import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/app_theme.dart';
import 'core/constants.dart';
import 'core/services/api_client.dart';
import 'core/services/customer_session_store.dart';
import 'core/services/owner_snapshot_cache.dart';
import 'widgets/error_view.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
        Zone.current.handleUncaughtError(
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
        return true;
      };

      ErrorWidget.builder = (_) => const AppErrorFallback();

      runApp(const OwnerApp());
    },
    (error, stack) {
      if (kDebugMode) {
        debugPrint('Unhandled app error: $error');
        debugPrintStack(stackTrace: stack);
      }
    },
  );
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema Solares Owner',
      theme: appTheme,
      home: const _AuthenticatedOwnerRoot(),
    );
  }
}

class _AuthenticatedOwnerRoot extends StatefulWidget {
  const _AuthenticatedOwnerRoot();

  @override
  State<_AuthenticatedOwnerRoot> createState() =>
      _AuthenticatedOwnerRootState();
}

class _AuthenticatedOwnerRootState extends State<_AuthenticatedOwnerRoot> {
  final CustomerSessionStore _sessionStore = const CustomerSessionStore();
  final OwnerSnapshotCache _snapshotCache = const OwnerSnapshotCache();
  AuthSession? _session;
  Object? _sessionError;
  bool _loadingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final stored = await _sessionStore.read();
    final configured = _configuredOwnerSession();
    final candidate = stored ?? configured;
    if (candidate == null) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _sessionError = const OwnerSessionConfigurationException();
        _loadingSession = false;
      });
      return;
    }

    try {
      final refreshed = await ApiClient(baseUrl).refresh(candidate.accessToken);
      await _sessionStore.write(refreshed);
      if (!mounted) return;
      setState(() {
        _session = refreshed;
        _sessionError = null;
        _loadingSession = false;
      });
    } catch (error) {
      Object authError = error;
      if (_isAuthenticationFailure(authError)) {
        await _sessionStore.clear();
        if (configured != null &&
            configured.accessToken != candidate.accessToken) {
          try {
            final refreshed = await ApiClient(
              baseUrl,
            ).refresh(configured.accessToken);
            await _sessionStore.write(refreshed);
            if (!mounted) return;
            setState(() {
              _session = refreshed;
              _sessionError = null;
              _loadingSession = false;
            });
            return;
          } catch (configuredError) {
            authError = configuredError;
          }
        }
      }
      if (candidate == configured) {
        await _sessionStore.clear();
      }
      if (!mounted) return;
      setState(() {
        _session = _isAuthenticationFailure(authError) ? null : candidate;
        _sessionError = _isAuthenticationFailure(authError) ? authError : null;
        _loadingSession = false;
      });
    }
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    await _snapshotCache.clear();
    if (mounted) {
      setState(() {
        _session = null;
        _sessionError = null;
        _loadingSession = true;
      });
    }
    await _restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session == null) {
      return Scaffold(
        body: ErrorView(error: _sessionError, onRetry: _restoreSession),
      );
    }
    return AppShell(session: session, onLogout: _logout);
  }
}

AuthSession? _configuredOwnerSession() {
  final token = ownerAccessToken.trim();
  if (token.isEmpty) return null;
  return AuthSession(
    accessToken: token,
    userName: ownerUserName.trim().isEmpty ? 'Dueño' : ownerUserName.trim(),
    email: ownerUserEmail.trim(),
  );
}

bool _isAuthenticationFailure(Object error) {
  final message = error.toString();
  return message.contains('HTTP 401') || message.contains('HTTP 403');
}

class OwnerSessionConfigurationException implements Exception {
  const OwnerSessionConfigurationException();

  @override
  String toString() {
    return 'OWNER_ACCESS_TOKEN no esta configurado para app_owner.';
  }
}
