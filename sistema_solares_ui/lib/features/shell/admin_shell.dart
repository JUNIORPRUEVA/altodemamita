import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';

const double shellMobileBreakpoint = 760;
const double shellDesktopBreakpoint = 1024;
const double shellSidebarLaptopWidth = 232;
const double shellSidebarDesktopWidth = 264;

bool isCompactShellWidth(double width) => width < shellMobileBreakpoint;

bool isDesktopShellWidth(double width) => width >= shellDesktopBreakpoint;

double shellSidebarWidthFor(double width) {
  if (!isDesktopShellWidth(width)) {
    return 0;
  }

  return width >= 1280 ? shellSidebarDesktopWidth : shellSidebarLaptopWidth;
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;
  static const String _companyName = 'Sistema Solares';

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final realtimeController = context.watch<RealtimeController>();
    final location = GoRouterState.of(context).uri.path;
    final summaryItems = <_NavItem>[
      const _NavItem(
        route: '/reports',
        icon: Icons.query_stats_rounded,
        label: 'Reporte',
      ),
      if (authController.canAccessGlobalSearch)
        const _NavItem(
          route: '/search',
          icon: Icons.travel_explore_outlined,
          label: 'Buscador',
        ),
      if (authController.canAccessSales)
        const _NavItem(
          route: '/sales',
          icon: Icons.point_of_sale_outlined,
          label: 'Ventas',
        ),
      if (authController.canAccessPayments)
        const _NavItem(
          route: '/payments',
          icon: Icons.payments_outlined,
          label: 'Pagos',
        ),
      const _NavItem(
        route: '/clients',
        icon: Icons.people_alt_outlined,
        label: 'Clientes',
      ),
      if (authController.canAccessSellers)
        const _NavItem(
          route: '/sellers',
          icon: Icons.badge_outlined,
          label: 'Vendedores',
        ),
      if (authController.hasPermission('products.read') ||
          authController.isPanelAdmin)
        const _NavItem(
          route: '/products',
          icon: Icons.domain_outlined,
          label: 'Solares',
        ),
    ];
    final adminItems = <_NavItem>[
      if (authController.canAccessSettings)
        _NavItem(
          route: '/settings',
          icon: Icons.settings_outlined,
          label: 'Configuracion',
          activeRoutes: authController.canManageUsers
              ? const ['/settings', '/users']
              : const ['/settings'],
        ),
    ];
    final contextItems = <_NavItem>[
      ...summaryItems,
      if (authController.canManageUsers)
        const _NavItem(
          route: '/users',
          icon: Icons.manage_accounts_outlined,
          label: 'Usuarios',
        ),
      ...adminItems,
    ];
    final mobileNavItems = <_NavItem>[
      const _NavItem(
        route: '/reports',
        icon: Icons.query_stats_rounded,
        label: 'Reporte',
      ),
      _NavItem(
        route: '/search',
        icon: Icons.travel_explore_outlined,
        label: 'Buscador',
        enabled: authController.canAccessGlobalSearch,
      ),
      _NavItem(
        route: '/sales',
        icon: Icons.point_of_sale_outlined,
        label: 'Ventas',
        enabled: authController.canAccessSales,
      ),
    ];
    final mobileNavRoutes = mobileNavItems
        .where((item) => item.enabled)
        .map((item) => item.route)
        .toSet();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = isDesktopShellWidth(constraints.maxWidth);
        final compact = isCompactShellWidth(constraints.maxWidth);
        final desktopSidebarWidth = shellSidebarWidthFor(constraints.maxWidth);
        if (compact && location == '/payments') {
          final redirectRoute = authController.canAccessSales
              ? '/sales'
              : '/reports';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(redirectRoute);
            }
          });

          return const Scaffold(
            backgroundColor: Color(0xFFF0F3F8),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final drawerWidth = math.min(constraints.maxWidth * 0.9, 348.0);
        final drawerSummaryItems = compact
            ? summaryItems
                  .where(
                    (item) =>
                        !mobileNavRoutes.contains(item.route) &&
                        item.route != '/payments',
                  )
                  .toList(growable: false)
            : summaryItems;
        final currentItem = contextItems.cast<_NavItem?>().firstWhere(
          (item) => item?.matches(location) ?? false,
          orElse: () => summaryItems.isNotEmpty ? summaryItems.first : null,
        );
        final sidebar = _Sidebar(
          summaryItems: drawerSummaryItems,
          adminItems: adminItems,
          currentRoute: location,
          compact: !wide,
        );

        if (compact) {
          return Scaffold(
            drawer: Drawer(
              width: drawerWidth,
              child: SafeArea(child: sidebar),
            ),
            backgroundColor: const Color(0xFFF0F3F8),
            appBar: _MobileShellAppBar(
              title: currentItem?.label ?? _companyName,
              realtimeController: realtimeController,
            ),
            body: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: child,
              ),
            ),
            bottomNavigationBar: _MobileBottomNav(
              items: mobileNavItems,
              currentRoute: location,
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF0F3F8),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide) SizedBox(width: desktopSidebarWidth, child: sidebar),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide
                          ? 0
                          : compact
                          ? 0
                          : 14,
                      compact ? 0 : 14,
                      compact ? 0 : 14,
                      compact ? 0 : 14,
                    ),
                    child: _ShellContentFrame(
                      decorated: !compact,
                      child: Column(
                        children: [
                          _TopBar(
                            title: currentItem?.label ?? _companyName,
                            realtimeController: realtimeController,
                            onOpenMenu: null,
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                compact ? 12 : 18,
                                compact ? 10 : 14,
                                compact ? 12 : 18,
                                compact ? 14 : 14,
                              ),
                              child: child,
                            ),
                          ),
                          const _ShellFooter(),
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

class _MobileShellAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _MobileShellAppBar({
    required this.title,
    required this.realtimeController,
  });

  final String title;
  final RealtimeController realtimeController;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      toolbarHeight: 60,
      titleSpacing: 6,
      leadingWidth: 62,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      foregroundColor: const Color(0xFF173450),
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
        child: Builder(
          builder: (context) {
            return _MobileAppBarIconButton(
              tooltip: 'Abrir menu',
              icon: Icons.menu_rounded,
              size: 42,
              iconSize: 22,
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: const LinearGradient(
                colors: [Color(0xFF1A4D73), Color(0xFF214C68)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.wb_sunny_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sistema Solares',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6C7890),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MobileStatusIcon(isConnected: realtimeController.isConnected),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Sesion',
                onSelected: (value) async {
                  if (value == 'settings') {
                    context.go('/settings');
                    return;
                  }
                  if (value == 'logout') {
                    await context.read<AuthController>().signOut();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  }
                },
                itemBuilder: (context) => [
                  if (authController.canAccessSettings)
                    const PopupMenuItem<String>(
                      value: 'settings',
                      child: Text('Configuracion'),
                    ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('Cerrar sesion'),
                  ),
                ],
                child: const _MobileSessionMenuButton(),
              ),
            ],
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFECEFF3)),
      ),
    );
  }
}

class _MobileAppBarIconButton extends StatelessWidget {
  const _MobileAppBarIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.iconSize = 20,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FB),
              border: Border.all(color: const Color(0xFFE4EAF2)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0810263D),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF173450), size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _MobileSessionMenuButton extends StatelessWidget {
  const _MobileSessionMenuButton();

  @override
  Widget build(BuildContext context) {
    return _MobileAppBarIconButton(
      tooltip: 'Opciones de sesion',
      icon: Icons.more_horiz_rounded,
    );
  }
}

class _MobileStatusIcon extends StatelessWidget {
  const _MobileStatusIcon({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: isConnected ? const Color(0xFFEAF8F0) : const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              (isConnected ? const Color(0xFF2BB673) : const Color(0xFF8B96A7))
                  .withValues(alpha: 0.18),
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        isConnected ? Icons.sync_rounded : Icons.sync_disabled_rounded,
        size: 19,
        color: isConnected ? const Color(0xFF2BB673) : const Color(0xFF6B7682),
      ),
    );
  }
}

class _ShellContentFrame extends StatelessWidget {
  const _ShellContentFrame({required this.decorated, required this.child});

  final bool decorated;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!decorated) {
      return child;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE4EAF2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A10263D),
              blurRadius: 28,
              offset: Offset(0, 8),
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
    final roleLabel = authController.user?.panelRole == PanelRole.admin
        ? 'Administrador'
        : 'Supervisor';
    final fullName = authController.user?.fullName ?? 'Sin usuario';

    final sessionMenu = PopupMenuButton<String>(
      tooltip: 'Sesion',
      onSelected: (value) async {
        if (value == 'settings') {
          context.go('/settings');
          return;
        }
        if (value == 'logout') {
          await context.read<AuthController>().signOut();
          if (context.mounted) {
            context.go('/login');
          }
        }
      },
      itemBuilder: (context) => [
        if (authController.canAccessSettings)
          const PopupMenuItem<String>(
            value: 'settings',
            child: Text('Configuracion'),
          ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Cerrar sesion'),
        ),
      ],
      child: compact
          ? const _MobileSessionMenuButton()
          : _DesktopProfileMenuButton(fullName: fullName, roleLabel: roleLabel),
    );

    if (compact) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, veryCompact ? 8 : 10, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFECEFF3), width: 1),
          ),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF0D2640),
                              fontWeight: FontWeight.w800,
                              fontSize: veryCompact ? 15 : 15.5,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Panel administrativo',
                        style: TextStyle(
                          color: const Color(
                            0xFF0D2640,
                          ).withValues(alpha: 0.42),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                sessionMenu,
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ConnectionIndicator(
                  isConnected: realtimeController.isConnected,
                ),
                if (!veryCompact) ...[
                  const SizedBox(width: 8),
                  Text(
                    authController.user?.panelRole == PanelRole.admin
                        ? 'Administrador'
                        : 'Supervisor',
                    style: const TextStyle(
                      color: Color(0xFF6F7891),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 8,
      ),
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
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0D2640),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _DesktopConnectionBadge(isConnected: realtimeController.isConnected),
          const SizedBox(width: 12),
          sessionMenu,
        ],
      ),
    );
  }
}

class _DesktopProfileMenuButton extends StatelessWidget {
  const _DesktopProfileMenuButton({
    required this.fullName,
    required this.roleLabel,
  });

  final String fullName;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Ink(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0810263D),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF12385F), Color(0xFF0A2037)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(
                  _initialsFor(fullName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF10263D),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7682),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF556273),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopConnectionBadge extends StatelessWidget {
  const _DesktopConnectionBadge({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? const Color(0xFF2BB673)
        : const Color(0xFF6B7682);
    final label = isConnected ? 'Realtime activo' : 'Realtime desconectado';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D2640),
            ),
          ),
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE4EAF2)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 21, color: const Color(0xFF173450)),
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
          colors: [Color(0xFF0C263E), Color(0xFF081A2B)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              drawerMode ? 16 : 18,
              drawerMode ? 18 : 18,
              drawerMode ? 16 : 18,
              drawerMode ? 18 : 18,
            ),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _SidebarBrandHeader(drawerMode: drawerMode),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: drawerMode ? 20 : 24),
                ),
                if (!drawerMode)
                  const SliverToBoxAdapter(
                    child: _SidebarSectionLabel(label: 'NAVEGACION'),
                  ),
                SliverList.list(
                  children: [
                    ...summaryItems.map(
                      (item) => _NavTile(
                        item: item,
                        selected: item.matches(currentRoute),
                        compact: compact,
                      ),
                    ),
                  ],
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      if (adminItems.isNotEmpty) ...[
                        if (!drawerMode)
                          const Padding(
                            padding: EdgeInsets.only(left: 8, bottom: 10),
                            child: _SidebarSectionLabel(label: 'CONFIGURACION'),
                          ),
                        ...adminItems.map(
                          (item) => _NavTile(
                            item: item,
                            selected: item.matches(currentRoute),
                            compact: compact,
                          ),
                        ),
                      ],
                      _SidebarLogoutTile(compact: compact),
                      const SizedBox(height: 8),
                      const _SidebarFooterNote(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
            horizontal: drawerMode ? 13 : 10,
            vertical: drawerMode ? 11 : 10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.025),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: drawerMode ? 44 : 36,
                height: drawerMode ? 44 : 36,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.icon,
                  color: Colors.white,
                  size: drawerMode ? 24 : 20,
                ),
              ),
              SizedBox(width: drawerMode ? 12 : 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: drawerMode ? 15 : 13.5,
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0.24,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8FCFFF),
                    shape: BoxShape.circle,
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

class _SidebarLogoutTile extends StatelessWidget {
  const _SidebarLogoutTile({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final drawerMode = MediaQuery.sizeOf(context).width < 760;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await context.read<AuthController>().signOut();
          if (!context.mounted) {
            return;
          }
          if (drawerMode && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          context.go('/login');
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: drawerMode ? 13 : 10,
            vertical: drawerMode ? 11 : 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.025),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: drawerMode ? 44 : 36,
                height: drawerMode ? 44 : 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: drawerMode ? 24 : 20,
                ),
              ),
              SizedBox(width: drawerMode ? 12 : 10),
              Expanded(
                child: Text(
                  'Cerrar sesion',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: drawerMode ? 15 : 13.5,
                  ),
                ),
              ),
              if (!compact)
                AnimatedOpacity(
                  opacity: 0.24,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8FCFFF),
                      shape: BoxShape.circle,
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

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? const Color(0xFF2BB673)
        : const Color(0xFF8B96A7);
    final fill = isConnected
        ? const Color(0xFFEAF8F0)
        : const Color(0xFFF1F4F8);

    return Tooltip(
      message: isConnected
          ? 'Sincronizacion activa'
          : 'Sincronizacion inactiva',
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Icon(
          isConnected ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({required this.items, required this.currentRoute});

  final List<_NavItem> items;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFD),
      elevation: 14,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5EBF3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1210263D),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: _MobileBottomNavItem(
                      item: item,
                      selected: item.matches(currentRoute),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNavItem extends StatelessWidget {
  const _MobileBottomNavItem({required this.item, required this.selected});

  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final foreground = item.enabled
        ? (selected ? const Color(0xFF123A5D) : const Color(0xFF637186))
        : const Color(0xFFB7C0CC);

    return Opacity(
      opacity: item.enabled ? 1 : 0.72,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: item.enabled
              ? () {
                  if (!selected) {
                    context.go(item.route);
                  }
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEFF4FA) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFDCE8F4)
                        : const Color(0xFFF6F8FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, size: 18, color: foreground),
                ),
                const SizedBox(height: 5),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
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
    this.activeRoutes = const [],
    this.enabled = true,
  });

  final String route;
  final IconData icon;
  final String label;
  final List<String> activeRoutes;
  final bool enabled;

  bool matches(String route) =>
      route == this.route || activeRoutes.contains(route);
}

class _SidebarBrandHeader extends StatelessWidget {
  const _SidebarBrandHeader({required this.drawerMode});

  final bool drawerMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        drawerMode ? 14 : 12,
        drawerMode ? 14 : 12,
        drawerMode ? 14 : 12,
        drawerMode ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(20),
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
                  color: const Color(0xFF4B9EE8).withValues(alpha: 0.24),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sistema Solares',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Panel PWA administrativo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0x8AFFFFFF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.34),
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    );
  }
}

class _SidebarFooterNote extends StatelessWidget {
  const _SidebarFooterNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Navegacion limpia y enfocada',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.42),
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

String _initialsFor(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'SS';
  }
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length.clamp(0, 2))
        .toUpperCase();
  }
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

class _ShellFooter extends StatelessWidget {
  const _ShellFooter();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: 5,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFAFBFD),
            border: Border(top: BorderSide(color: Color(0xFFE8EDF4))),
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sistema Solares · Panel PWA',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF96A0AE),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '© 2026',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB0B8C4),
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text(
                      'Sistema Solares · Panel PWA',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF96A0AE),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '© 2026',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB0B8C4),
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
