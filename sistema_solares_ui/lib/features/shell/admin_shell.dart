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
      if (authController.canAccessSales)
        const _NavItem(
          route: '/sales',
          icon: Icons.point_of_sale_outlined,
          label: 'Ventas',
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
        final currentItem = [...summaryItems, ...adminItems].cast<_NavItem?>().firstWhere(
              (item) => item?.route == location,
              orElse: () => summaryItems.isNotEmpty ? summaryItems.first : null,
            );
        final sidebar = _Sidebar(
          summaryItems: summaryItems,
          adminItems: adminItems,
          currentRoute: location,
          compact: !wide,
        );

        return Scaffold(
          key: scaffoldKey,
          drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
          backgroundColor: const Color(0xFFF0F3F8),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  SizedBox(
                    width: 288,
                    child: sidebar,
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(wide ? 0 : 14, compact ? 14 : 16, compact ? 14 : 16, compact ? 14 : 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(wide ? 20 : 18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE4EAF2)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 20,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _TopBar(
                              title: currentItem?.label ?? 'Sistema Solares',
                              realtimeController: realtimeController,
                              onOpenMenu: wide ? null : scaffoldKey.currentState?.openDrawer,
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(compact ? 14 : 16, 16, compact ? 14 : 16, 16),
                                child: child,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
    required this.title,
    required this.realtimeController,
    required this.onOpenMenu,
  });

  final String title;
  final RealtimeController realtimeController;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: compact ? 12 : 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border(bottom: BorderSide(color: Color(0xFFECEFF3), width: 1)),
      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF0D2640),
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Sistema Solares',
                  style: TextStyle(
                    color: const Color(0xFF0D2640).withValues(alpha: 0.32),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          _HeaderBadge(
            icon: realtimeController.isConnected
                ? Icons.wifi_tethering_rounded
                : Icons.wifi_off_rounded,
            label: realtimeController.isConnected
                ? 'Realtime activo'
                : 'Realtime desconectado',
            color: realtimeController.isConnected
                ? const Color(0xFF2BB673)
                : const Color(0xFF6B7682),
            fill: realtimeController.isConnected
                ? const Color(0xFFE9F8F0)
                : const Color(0xFFF1F4F8),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
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
                border: Border.all(color: const Color(0xFFE4EAF2)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF173450),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D2640),
                        ),
                      ),
                      if (!compact)
                        Text(
                          authController.user?.panelRole == PanelRole.admin
                              ? 'Administrador'
                              : 'Supervisor',
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2844), Color(0xFF071829)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sistema Solares',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Panel administrativo',
                    style: TextStyle(color: Color(0xFFAAB8C8), height: 1.4),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado del panel',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Consulta, seguimiento y configuracion disponibles desde este entorno.',
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
            color: selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
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
        border: Border.all(color: color.withValues(alpha: 0.20)),
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