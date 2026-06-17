import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/resilience/global_error_controller.dart';
import '../core/system/system_config_service.dart';
import '../features/auth/presentation/auth_provider.dart';
import '../features/auth/presentation/bootstrap_admin_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import 'navigation/app_shell.dart';
import '../core/theme/app_theme.dart';
import '../shared/widgets/recovery_experience.dart';

class SistemaSolaresApp extends StatelessWidget {
  const SistemaSolaresApp({super.key, required this.errorController});

  final GlobalErrorController errorController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SystemConfigService>(
          create: (_) => SystemConfigService.instance..initialize(),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'Sistema de Solares',
        debugShowCheckedModeBanner: false,
        navigatorKey: errorController.navigatorKey,
        theme: AppTheme.light(),
        builder: (context, child) => GlobalErrorOverlay(
          controller: errorController,
          child: _ReadOnlyModeFrame(child: child ?? const SizedBox.shrink()),
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _ReadOnlyModeFrame extends StatelessWidget {
  const _ReadOnlyModeFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final systemConfig = context.watch<SystemConfigService>();

    return Stack(
      children: [child, if (systemConfig.isReadOnly) const _ReadOnlyBanner()],
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              elevation: 6,
              color: const Color(0xFF8F2436),
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Modo solo lectura activado',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!auth.isAuthenticated) {
          if (auth.requiresInitialSetup) {
            return const BootstrapAdminScreen();
          }
          return const LoginScreen();
        }

        return const AppShell();
      },
    );
  }
}
