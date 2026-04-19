import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/core/system/system_config_controller.dart';
import 'package:sistema_solares_ui/core/theme/app_theme.dart';
import 'package:sistema_solares_ui/features/auth/login_screen.dart';
import 'package:sistema_solares_ui/features/clients/clients_screen.dart';
import 'package:sistema_solares_ui/features/global_search/global_search_screen.dart';
import 'package:sistema_solares_ui/features/products/products_screen.dart';
import 'package:sistema_solares_ui/features/reports/reports_screen.dart';
import 'package:sistema_solares_ui/features/sales/sales_screen.dart';
import 'package:sistema_solares_ui/features/sellers/sellers_screen.dart';
import 'package:sistema_solares_ui/features/settings/settings_screen.dart';
import 'package:sistema_solares_ui/features/shell/admin_shell.dart';
import 'package:sistema_solares_ui/features/users/users_screen.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final ApiClient _apiClient;
  late final RealtimeController _realtimeController;
  late final SystemConfigController _systemConfigController;
  late final AuthController _authController;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _realtimeController = RealtimeController();
    _systemConfigController = SystemConfigController(apiClient: _apiClient);
    _authController = AuthController(
      apiClient: _apiClient,
      realtimeController: _realtimeController,
      systemConfigController: _systemConfigController,
    );
    _router = _buildRouter(_authController);
    _systemConfigController.initialize();
    _authController.initialize();
  }

  @override
  void dispose() {
    _authController.dispose();
    _systemConfigController.dispose();
    _realtimeController.dispose();
    super.dispose();
  }

  GoRouter _buildRouter(AuthController authController) {
    return GoRouter(
      refreshListenable: authController,
      initialLocation: '/loading',
      redirect: (context, state) {
        final location = state.uri.path;
        if (!authController.initialized) {
          return location == '/loading' ? null : '/loading';
        }

        if (!authController.isAuthenticated) {
          return location == '/login' ? null : '/login';
        }

        if (location == '/loading' || location == '/login' || location == '/') {
          return '/reports';
        }

        if (location == '/search' && !authController.canAccessGlobalSearch) {
          return '/reports';
        }

        if (location == '/users' && !authController.canManageUsers) {
          return '/reports';
        }

        if (location == '/sales' && !authController.canAccessSales) {
          return '/reports';
        }

        if (
          location == '/products' &&
          !authController.hasPermission('products.read') &&
          !authController.isPanelAdmin
        ) {
          return '/reports';
        }

        if (location == '/sellers' && !authController.canAccessSellers) {
          return '/reports';
        }

        if (location == '/settings' && !authController.canAccessSettings) {
          return '/reports';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/loading',
          builder: (context, state) => const _LoadingScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => AdminShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              redirect: (context, state) => '/reports',
            ),
            GoRoute(
              path: '/search',
              builder: (context, state) => const GlobalSearchScreen(),
            ),
            GoRoute(
              path: '/reports',
              builder: (context, state) => const ReportsScreen(),
            ),
            GoRoute(
              path: '/sales',
              builder: (context, state) => const SalesScreen(),
            ),
            GoRoute(
              path: '/clients',
              builder: (context, state) => const ClientsScreen(),
            ),
            GoRoute(
              path: '/sellers',
              builder: (context, state) => const SellersScreen(),
            ),
            GoRoute(
              path: '/products',
              builder: (context, state) => const ProductsScreen(),
            ),
            GoRoute(
              path: '/users',
              builder: (context, state) => const UsersScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _apiClient),
        ChangeNotifierProvider<SystemConfigController>.value(
          value: _systemConfigController,
        ),
        ChangeNotifierProvider<RealtimeController>.value(
          value: _realtimeController,
        ),
        ChangeNotifierProvider<AuthController>.value(value: _authController),
      ],
      child: MaterialApp.router(
        title: 'Sistema Solares | Panel Web',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: _router,
        builder: (context, child) => _ReadOnlyShell(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ReadOnlyShell extends StatelessWidget {
  const _ReadOnlyShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final systemConfig = context.watch<SystemConfigController>();

    return Stack(
      children: [
        child,
        if (systemConfig.isReadOnly)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Material(
                  elevation: 4,
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
      ],
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
