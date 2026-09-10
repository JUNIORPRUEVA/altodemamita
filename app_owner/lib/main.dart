import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/app_theme.dart';
import 'core/constants.dart';
import 'core/services/api_client.dart';
import 'core/services/customer_session_store.dart';
import 'features/auth/login_page.dart';
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
      title: 'Sistema Solares Cliente',
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
  AuthSession? _session;
  bool _loadingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final stored = await _sessionStore.read();
    if (stored == null) {
      if (mounted) setState(() => _loadingSession = false);
      return;
    }
    try {
      final refreshed = await ApiClient(baseUrl).refresh(stored.accessToken);
      await _sessionStore.write(refreshed);
      if (!mounted) return;
      setState(() {
        _session = refreshed;
        _loadingSession = false;
      });
    } catch (error) {
      if (_isAuthenticationFailure(error)) {
        await _sessionStore.clear();
        if (!mounted) return;
        setState(() => _loadingSession = false);
        return;
      }
      if (!mounted) return;
      setState(() {
        _session = stored;
        _loadingSession = false;
      });
    }
  }

  Future<void> _login(String email, String password) async {
    final session = await ApiClient(
      baseUrl,
    ).login(email: email, password: password);
    await ApiClient(
      baseUrl,
      accessToken: session.accessToken,
    ).fetchDashboardSnapshot();
    await _sessionStore.write(session);
    if (!mounted) return;
    setState(() => _session = session);
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session == null) {
      return LoginPage(onLogin: _login);
    }
    return AppShell(session: session, onLogout: _logout);
  }
}

bool _isAuthenticationFailure(Object error) {
  final message = error.toString();
  return message.contains('HTTP 401') || message.contains('HTTP 403');
}
