import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final authController = context.watch<AuthController>();
    final realtimeController = context.watch<RealtimeController>();
    final location = GoRouterState.of(context).uri.path;
    final summaryItems = <_NavItem>[
      const _NavItem(
        route: '/dashboard',
        icon: Icons.grid_view_rounded,
        label: 'Resumen general',
      ),
      const _NavItem(
        route: '/reports',
        icon: Icons.query_stats_rounded,
        label: 'Reportes',
      ),
      const _NavItem(
        route: '/clients',
        icon: Icons.people_alt_outlined,
        label: 'Clientes',
      ),
      if (authController.hasPermission('products.read') || authController.isPanelAdmin)
        const _NavItem(
          route: '/products',
          icon: Icons.domain_outlined,
          label: 'Solares',
        ),
    ];
    final adminItems = <_NavItem>[
      if (authController.canManageUsers)
        const _NavItem(
          route: '/users',
          icon: Icons.manage_accounts_outlined,
          label: 'Usuarios',
        ),
      if (authController.canAccessSettings)
        const _NavItem(
          route: '/settings',
          icon: Icons.settings_outlined,
          label: 'Configuracion',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1120;
        final compact = constraints.maxWidth < 760;
        final sidebar = _Sidebar(
          summaryItems: summaryItems,
          adminItems: adminItems,
          currentRoute: location,
          compact: !wide,
        );

        return Scaffold(
          key: scaffoldKey,
          drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
          backgroundColor: const Color(0xFFF6EBDD),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF5EBDD), Color(0xFFF4F0E7), Color(0xFFE7DDCF)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -110,
                  left: -50,
                  child: _GlowOrb(
                    size: 240,
                    color: const Color(0xFFCC8749).withValues(alpha: 0.18),
                  ),
                ),
                Positioned(
                  right: -80,
                  bottom: -120,
                  child: _GlowOrb(
                    size: 280,
                    color: const Color(0xFF36506C).withValues(alpha: 0.10),
                  ),
                ),
                SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide)
                        SizedBox(
                          width: 310,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 22, 10, 22),
                            child: sidebar,
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(wide ? 10 : 14, compact ? 14 : 22, compact ? 14 : 18, compact ? 12 : 18),
                          child: Column(
                            children: [
                              _TopBar(
                                realtimeController: realtimeController,
                                onOpenMenu: wide ? null : scaffoldKey.currentState?.openDrawer,
                              ),
                              SizedBox(height: compact ? 12 : 18),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(compact ? 2 : 6, 0, compact ? 2 : 4, 0),
                                  child: child,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    final compact = MediaQuery.sizeOf(context).width < 760;

    return DesktopSurface(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: compact ? 10 : 14),
      radius: compact ? 20 : 24,
      child: Row(
        children: [
          if (onOpenMenu != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: onOpenMenu,
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          Expanded(
            child: Wrap(
              spacing: compact ? 8 : 10,
              runSpacing: compact ? 8 : 10,
              children: [
                const _HeaderBadge(
                  icon: Icons.desktop_windows_outlined,
                  label: 'PWA alineada con escritorio',
                  color: Color(0xFF223048),
                  fill: Color(0xFFEAF0F7),
                ),
                _HeaderBadge(
                  icon: realtimeController.isConnected
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_off_rounded,
                  label: realtimeController.isConnected
                      ? 'Realtime activo'
                      : 'Realtime desconectado',
                  color: realtimeController.isConnected
                      ? const Color(0xFF246B53)
                      : const Color(0xFFA85A2C),
                  fill: realtimeController.isConnected
                      ? const Color(0xFFE8F6F0)
                      : const Color(0xFFFCEEDF),
                ),
                _HeaderBadge(
                  icon: Icons.lock_outline_rounded,
                  label: authController.user?.panelRole == PanelRole.admin
                      ? 'Acceso administrador'
                      : 'Acceso supervisado',
                  color: const Color(0xFF5A6782),
                  fill: const Color(0xFFF0F3F9),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FB),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFC6894C),
                    child: Text(
                      (authController.user?.fullName.isNotEmpty == true
                              ? authController.user!.fullName[0]
                              : 'U')
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authController.user?.fullName ?? 'Sin usuario',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (!compact)
                        Text(
                          authController.user?.email ?? '',
                          style: const TextStyle(
                            color: Color(0xFF6F7891),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ],
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.summaryItems,
    required this.adminItems,
    required this.currentRoute,
    required this.compact,
  });

  final List<_NavItem> summaryItems;
  final List<_NavItem> adminItems;
  final String currentRoute;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2A37),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3646),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sistema Solares',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Mismo lenguaje visual del escritorio para supervision, consulta y control.',
                    style: TextStyle(color: Color(0xFFD2D8E2), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Resumen y operacion'),
            const SizedBox(height: 10),
            ...summaryItems.map((item) => _NavTile(
                  item: item,
                  selected: currentRoute == item.route,
                  compact: compact,
                )),
            if (adminItems.isNotEmpty) ...[
              const SizedBox(height: 18),
              const _SectionLabel('Administracion'),
              const SizedBox(height: 10),
              ...adminItems.map((item) => _NavTile(
                    item: item,
                    selected: currentRoute == item.route,
                    compact: compact,
                  )),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3646),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Modo protegido',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ventas, pagos, cuotas y caja siguen bloqueados en la PWA para evitar desajustes operativos.',
                    style: TextStyle(color: Color(0xFFD2D8E2), height: 1.45),
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

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.compact,
  });

  final _NavItem item;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFC6894C) : const Color(0xFF2A3646),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(item.icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFFAAB5C7),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.fill,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
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

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
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