import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final realtimeController = context.watch<RealtimeController>();
    final location = GoRouterState.of(context).uri.path;
    final items = <_NavItem>[
      const _NavItem(
        route: '/dashboard',
        icon: Icons.space_dashboard_outlined,
        label: 'Dashboard',
      ),
      const _NavItem(
        route: '/reports',
        icon: Icons.query_stats_outlined,
        label: 'Reportes',
      ),
      const _NavItem(
        route: '/clients',
        icon: Icons.people_outline,
        label: 'Clientes',
      ),
      if (authController.canManageUsers)
        const _NavItem(
          route: '/users',
          icon: Icons.manage_accounts_outlined,
          label: 'Usuarios',
        ),
      if (authController.canAccessSettings)
        const _NavItem(
          route: '/settings',
          icon: Icons.tune_outlined,
          label: 'Configuracion',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final rail = SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 10, 20),
            child: _Sidebar(
              items: items,
              currentRoute: location,
            ),
          ),
        );

        return Scaffold(
          drawer: wide
              ? null
              : Drawer(
                  child: _Sidebar(
                    items: items,
                    currentRoute: location,
                    compact: true,
                  ),
                ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF7EFE3), Color(0xFFF2E5CF), Color(0xFFF7F5EE)],
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (wide) rail,
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(wide ? 10 : 12, 16, 16, 16),
                      child: Column(
                        children: [
                          _TopBar(
                            realtimeController: realtimeController,
                            onOpenMenu: wide
                                ? null
                                : () => Scaffold.of(context).openDrawer(),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.realtimeController,
    required this.onOpenMenu,
  });

  final RealtimeController realtimeController;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            if (onOpenMenu != null)
              IconButton(
                onPressed: onOpenMenu,
                icon: const Icon(Icons.menu),
              ),
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2A37),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Modo Administracion / Panel Web',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusPill(
                    icon: realtimeController.isConnected
                        ? Icons.wifi_tethering
                        : Icons.wifi_off,
                    label: realtimeController.isConnected
                        ? 'Realtime activo'
                        : 'Realtime desconectado',
                    color: realtimeController.isConnected
                        ? const Color(0xFF266A54)
                        : const Color(0xFFC96F3B),
                  ),
                  _StatusPill(
                    icon: Icons.lock_outline,
                    label: authController.user?.panelRole == PanelRole.admin
                        ? 'Acceso administrador'
                        : 'Acceso solo lectura',
                    color: const Color(0xFF5C6B8A),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Sesion',
              onSelected: (value) async {
                if (value == 'logout') {
                  await context.read<AuthController>().signOut();
                  if (context.mounted) {
                    context.go('/login');
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Text('Cerrar sesion'),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFC96F3B),
                    child: Text(
                      (authController.user?.fullName.isNotEmpty == true
                              ? authController.user!.fullName[0]
                              : 'U')
                          .toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authController.user?.fullName ?? 'Sin usuario',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        authController.user?.email ?? '',
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.currentRoute,
    this.compact = false,
  });

  final List<_NavItem> items;
  final String currentRoute;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1F2A37),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Sistema Solares',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Supervision, usuarios y configuracion del sistema.',
              style: TextStyle(color: Color(0xFFCAD1DB), height: 1.45),
            ),
            const SizedBox(height: 18),
            ...items.map((item) {
              final selected = currentRoute == item.route;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    context.go(item.route);
                    if (compact) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFC96F3B)
                          : const Color(0xFF2B3748),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon, color: Colors.white),
                        const SizedBox(width: 12),
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2B3748),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'Operaciones criticas bloqueadas: ventas, pagos, cuotas y caja.',
                style: TextStyle(color: Color(0xFFD6DCE6), height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.route,
    required this.icon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final String label;
}