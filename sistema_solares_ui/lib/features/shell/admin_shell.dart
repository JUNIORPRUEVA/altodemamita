import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;
  static const String _companyName = 'Sistema Solares';

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
        final drawerWidth = math.min(constraints.maxWidth * 0.92, 364.0);
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
          drawer: wide
              ? null
              : Drawer(
                  width: drawerWidth,
                  child: SafeArea(child: sidebar),
                ),
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
                    padding: EdgeInsets.fromLTRB(
                      wide ? 0 : compact ? 0 : 14,
                      compact ? 0 : 16,
                      compact ? 0 : 16,
                      compact ? 0 : 16,
                    ),
                    child: _ShellContentFrame(
                      decorated: !compact,
                      child: Column(
                        children: [
                          _TopBar(
                            title: currentItem?.label ?? _companyName,
                            realtimeController: realtimeController,
                            onOpenMenu: wide ? null : scaffoldKey.currentState?.openDrawer,
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                compact ? 12 : 16,
                                compact ? 12 : 16,
                                compact ? 12 : 16,
                                compact ? 18 : 16,
                              ),
                              child: child,
                            ),
                          ),
                          const _ShellFooter(companyName: _companyName),
                        ],
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

class _ShellContentFrame extends StatelessWidget {
  const _ShellContentFrame({
    required this.decorated,
    required this.child,
  });

  final bool decorated;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!decorated) {
      return child;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
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
        child: child,
      ),
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
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final veryCompact = width < 420;

    final sessionMenu = PopupMenuButton<String>(
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
      child: compact
          ? Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FB),
                border: Border.all(color: const Color(0xFFE4EAF2)),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(
                (authController.user?.fullName.isNotEmpty == true
                        ? authController.user!.fullName[0]
                        : 'U')
                    .toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF173450),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            )
          : Container(
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
    );

    if (compact) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, veryCompact ? 10 : 12, 12, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFECEFF3), width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (onOpenMenu != null) ...[
                  _TopBarActionButton(
                    icon: Icons.menu_rounded,
                    tooltip: 'Abrir menu',
                    onPressed: onOpenMenu,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF0D2640),
                              fontWeight: FontWeight.w800,
                              fontSize: veryCompact ? 16 : 17,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sistema Solares',
                        style: TextStyle(
                          color: const Color(0xFF0D2640).withValues(alpha: 0.42),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                sessionMenu,
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeaderBadge(
                  icon: realtimeController.isConnected
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_off_rounded,
                  label: realtimeController.isConnected ? 'Realtime activo' : 'Realtime desconectado',
                  color: realtimeController.isConnected
                      ? const Color(0xFF2BB673)
                      : const Color(0xFF6B7682),
                  fill: realtimeController.isConnected
                      ? const Color(0xFFE9F8F0)
                      : const Color(0xFFF1F4F8),
                  compact: true,
                ),
                if (!veryCompact)
                  _HeaderBadge(
                    icon: Icons.person_outline_rounded,
                    label: authController.user?.panelRole == PanelRole.admin
                        ? 'Administrador'
                        : 'Supervisor',
                    color: const Color(0xFF173450),
                    fill: const Color(0xFFF1F4FA),
                    compact: true,
                  ),
              ],
            ),
          ],
        ),
      );
    }

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
              child: _TopBarActionButton(
                icon: Icons.menu_rounded,
                tooltip: 'Abrir menu',
                onPressed: onOpenMenu,
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
          const SizedBox(width: 10),
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
          const SizedBox(width: 10),
          sessionMenu,
        ],
      ),
    );
  }
}

class _TopBarActionButton extends StatelessWidget {
  const _TopBarActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE4EAF2)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 28, color: const Color(0xFF173450)),
          ),
        ),
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
    final drawerMode = MediaQuery.sizeOf(context).width < 760;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2844), Color(0xFF071829)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(drawerMode ? 16 : 18, drawerMode ? 18 : 16, drawerMode ? 16 : 18, drawerMode ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(drawerMode ? 16 : 14, drawerMode ? 16 : 14, drawerMode ? 16 : 14, drawerMode ? 14 : 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF59B6FF), Color(0xFF1B5BA8)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4B9EE8).withValues(alpha: 0.32),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.wb_sunny_rounded,
                      size: 21,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sistema Solares',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Navegacion ejecutiva',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0x8AFFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Destacados'),
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
                    'Acceso rapido',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Resumen, reportes, clientes y configuracion con la misma jerarquia visual del escritorio.',
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
    final drawerMode = MediaQuery.sizeOf(context).width < 760;
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
          padding: EdgeInsets.symmetric(
            horizontal: drawerMode ? 16 : 14,
            vertical: drawerMode ? 16 : 14,
          ),
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
              Icon(item.icon, color: Colors.white, size: drawerMode ? 26 : 22),
              SizedBox(width: drawerMode ? 14 : 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: drawerMode ? 15 : 14,
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
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color fill;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 9 : 10),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: color.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 16 : 18, color: color),
          SizedBox(width: compact ? 6 : 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 13,
            ),
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

class _ShellFooter extends StatelessWidget {
  const _ShellFooter({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Color(0xFFE8EDF4))),
      ),
      child: Text(
        '© 2026 $companyName · Todos los derechos reservados',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFFABB5C3),
          fontWeight: FontWeight.w400,
          fontSize: 10.5,
          letterSpacing: 0.1,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}