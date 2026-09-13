import 'package:flutter/material.dart';

import '../../core/responsive/app_breakpoints.dart';
import 'pwa_install_state.dart';

/// Entrada de navegación móvil (módulo del sistema).
class MobileNavigationItem {
  const MobileNavigationItem({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.prominent = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool enabled;

  /// Destino principal destacado (hoy: Ventas).
  ///
  /// En la barra inferior móvil se dibuja más grande, con relleno y sombra,
  /// para que quede visualmente por encima del resto de los destinos.
  final bool prominent;
}

class MobileDrawerSection {
  const MobileDrawerSection({required this.title, required this.items});

  final String title;
  final List<MobileNavigationItem> items;
}

/// Shell de navegación para pantallas pequeñas.
///
/// Reglas de diseño acordadas:
/// - Máximo 4 destinos en la barra inferior.
/// - Los módulos secundarios viven en el Drawer.
/// - Resumen usa un header compacto dentro del body.
/// - Subpáginas usan AppBar compacta.
///
/// Este widget es ADITIVO: no sustituye ni modifica el shell de escritorio.
/// En Windows sigue usándose el `AppShell` existente.
class MobileNavigationShell extends StatelessWidget {
  const MobileNavigationShell({
    super.key,
    required this.title,
    required this.child,
    required this.primaryItems,
    required this.selectedId,
    required this.onSelected,
    this.drawerSections = const [],
    this.actions = const [],
    this.showBackButton,
    this.onBack,
    this.leading,
    this.bottom,
    this.hideAppBar = false,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset = true,
    this.companyName,
    this.userName,
    this.userRole,
    this.showHomeHeader = false,
    this.onOpenProfile,
    this.onSignOut,
    this.showInstallButton,
  });

  /// Título mostrado en la AppBar.
  final String title;

  /// Contenido del módulo activo.
  final Widget child;

  /// Destinos visibles en la barra inferior (se recomiendan 3 o 4).
  final List<MobileNavigationItem> primaryItems;

  final String selectedId;
  final ValueChanged<String> onSelected;

  /// Módulos secundarios agrupados en el Drawer.
  final List<MobileDrawerSection> drawerSections;

  /// Acción principal de la AppBar (una sola, para no saturarla).
  final List<Widget> actions;

  /// `null` = automático (se muestra si hay algo que volver).
  final bool? showBackButton;
  final VoidCallback? onBack;

  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool hideAppBar;
  final Widget? floatingActionButton;
  final bool resizeToAvoidBottomInset;

  final String? companyName;
  final String? userName;
  final String? userRole;
  final bool showHomeHeader;
  final Future<void> Function()? onOpenProfile;
  final Future<void> Function()? onSignOut;
  final bool? showInstallButton;

  bool get _canPop => showBackButton ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useCompactNavigation = AppBreakpoints.usesCompactNavigation(context);
    final hasDrawer = drawerSections.any((section) => section.items.isNotEmpty);
    final homeHeader = showHomeHeader && useCompactNavigation && !_canPop;
    final showInstall =
        useCompactNavigation &&
        (showInstallButton ?? shouldShowPwaInstallButton());
    final effectiveActions = <Widget>[
      if (showInstall) const _InstallPwaButton(),
      ...actions,
    ];

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: hasDrawer ? _buildDrawer(context) : null,
      appBar: homeHeader || hideAppBar
          ? null
          : AppBar(
              toolbarHeight: 56,
              title: Text(title, overflow: TextOverflow.ellipsis),
              centerTitle: false,
              automaticallyImplyLeading: false,
              leading:
                  leading ??
                  (_canPop
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Volver',
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                        )
                      : hasDrawer
                      ? Builder(
                          builder: (buttonContext) => IconButton(
                            icon: const Icon(Icons.menu_rounded),
                            tooltip: 'Menú',
                            onPressed: () =>
                                Scaffold.of(buttonContext).openDrawer(),
                          ),
                        )
                      : null),
              actions: effectiveActions,
              bottom: bottom,
            ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: homeHeader
            ? Column(
                children: [
                  _MobileHomeHeader(
                    companyName: companyName ?? title,
                    showInstallButton: showInstall,
                    onOpenDrawer: hasDrawer
                        ? (headerContext) =>
                              Scaffold.of(headerContext).openDrawer()
                        : null,
                    onOpenProfile: onOpenProfile,
                  ),
                  Expanded(child: child),
                ],
              )
            : child,
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: useCompactNavigation
          ? _buildNavigationBar(context)
          : null,
    );
  }

  Widget _buildNavigationBar(BuildContext context) {
    final ids = <String>[for (final item in primaryItems) item.id];
    final currentIndex = ids.indexOf(selectedId);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;

    return _MobileBottomNavigationBar(
      items: primaryItems,
      currentIndex: safeIndex,
      onSelected: (index) => onSelected(ids[index]),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      width: 304,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D2844),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.wb_sunny_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          companyName ?? title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF102A43),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if ((userName ?? '').trim().isNotEmpty)
                              userName!.trim(),
                            if ((userRole ?? '').trim().isNotEmpty)
                              userRole!.trim(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (final section in drawerSections) ...[
                    _DrawerSectionTitle(section.title),
                    for (final item in section.items)
                      _DrawerNavigationTile(
                        item: item,
                        selected:
                            item.id == selectedId ||
                            (item.id == 'settings.users' &&
                                selectedId == 'settings'),
                        onTap: item.enabled
                            ? () {
                                Navigator.of(context).pop();
                                onSelected(item.id);
                              }
                            : null,
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onOpenProfile != null)
                    _DrawerNavigationTile(
                      item: const MobileNavigationItem(
                        id: '__profile__',
                        label: 'Mi cuenta',
                        icon: Icons.person_outline,
                      ),
                      selected: false,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await onOpenProfile?.call();
                      },
                    ),
                  if (onSignOut != null)
                    _DrawerNavigationTile(
                      item: const MobileNavigationItem(
                        id: '__logout__',
                        label: 'Cerrar sesión',
                        icon: Icons.logout_rounded,
                      ),
                      selected: false,
                      warning: true,
                      onTap: () => _confirmSignOut(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final drawerNavigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text('¿Deseas cerrar tu sesión en este dispositivo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      drawerNavigator.pop();
      await onSignOut?.call();
    }
  }
}

/// Barra inferior de navegación móvil (PWA / pantallas pequeñas).
///
/// Reglas visuales acordadas:
/// - El destino activo se resalta con un fondo suave ("sombreado") y color
///   primario, para que la pantalla actual sea inequívoca.
/// - El destino marcado como [MobileNavigationItem.prominent] (Ventas) se
///   dibuja más grande, con relleno, borde y sombra, y queda por encima del
///   resto de los destinos.
class _MobileBottomNavigationBar extends StatelessWidget {
  const _MobileBottomNavigationBar({
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<MobileNavigationItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Color del destino activo.
  static const Color activeColor = Color(0xFF123A5E);

  /// Color de un destino inactivo.
  static const Color inactiveColor = Color(0xFF6B7A90);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE4EAF2))),
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                for (var index = 0; index < items.length; index++)
                  Expanded(
                    child: MobileBottomNavigationItem(
                      item: items[index],
                      selected: index == currentIndex,
                      onTap: () => onSelected(index),
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

/// Destino individual de la barra inferior móvil.
///
/// Es público (y expone [selected]) para que las pruebas y cualquier
/// consumidor puedan verificar qué pantalla está activa.
class MobileBottomNavigationItem extends StatelessWidget {
  const MobileBottomNavigationItem({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MobileNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.1,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected
            ? _MobileBottomNavigationBar.activeColor
            : const Color(0xFF7A8699),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: item.enabled ? onTap : null,
        highlightColor: _MobileBottomNavigationBar.activeColor.withValues(
          alpha: 0.06,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: item.prominent
              ? _buildProminentItem(label)
              : _buildRegularItem(label),
        ),
      ),
    );
  }

  List<Widget> _buildProminentItem(Widget label) {
    return [
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E4E79), Color(0xFF123A5E)],
          ),
          border: Border.all(
            color: selected ? Colors.white : const Color(0xFFDCE6F1),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _MobileBottomNavigationBar.activeColor.withValues(
                alpha: selected ? 0.42 : 0.26,
              ),
              blurRadius: selected ? 14 : 9,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(item.icon, size: 24, color: Colors.white),
      ),
      const SizedBox(height: 2),
      label,
    ];
  }

  List<Widget> _buildRegularItem(Widget label) {
    final color = selected
        ? _MobileBottomNavigationBar.activeColor
        : _MobileBottomNavigationBar.inactiveColor;

    return [
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? _MobileBottomNavigationBar.activeColor.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(item.icon, size: 20, color: color),
      ),
      const SizedBox(height: 3),
      label,
    ];
  }
}

class _MobileHomeHeader extends StatelessWidget {
  const _MobileHomeHeader({
    required this.companyName,
    required this.showInstallButton,
    required this.onOpenDrawer,
    required this.onOpenProfile,
  });

  final String companyName;
  final bool showInstallButton;
  final void Function(BuildContext context)? onOpenDrawer;
  final Future<void> Function()? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xFFF7F9FC),
          border: Border(bottom: BorderSide(color: Color(0xFFE8EDF4))),
        ),
        child: Row(
          children: [
            Builder(
              builder: (buttonContext) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Menú',
                onPressed: onOpenDrawer == null
                    ? null
                    : () => onOpenDrawer!(buttonContext),
              ),
            ),
            Expanded(
              child: Text(
                companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF102A43),
                ),
              ),
            ),
            if (showInstallButton) ...[
              const SizedBox(width: 8),
              const _InstallPwaButton(compact: true),
            ],
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Mi cuenta',
              onPressed: onOpenProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallPwaButton extends StatelessWidget {
  const _InstallPwaButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      'Instalar',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 12 : 13,
        fontWeight: FontWeight.w800,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(right: compact ? 0 : 8),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: Size(compact ? 90 : 104, compact ? 34 : 38),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13),
          backgroundColor: const Color(0xFF123A5E),
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _showInstallInstructions(context),
        icon: Icon(Icons.ios_share_rounded, size: compact ? 17 : 18),
        label: label,
      ),
    );
  }

  void _showInstallInstructions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Instalar en iPhone'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Para usar Sistema Solares como app en iPhone:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 14),
            _InstallStep(number: '1', text: 'Abre esta página en Safari.'),
            _InstallStep(
              number: '2',
              text: 'Toca el botón Compartir de Safari.',
            ),
            _InstallStep(
              number: '3',
              text: 'Elige “Agregar a pantalla de inicio”.',
            ),
            _InstallStep(
              number: '4',
              text: 'Toca “Agregar” y abre la app desde el icono creado.',
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

class _InstallStep extends StatelessWidget {
  const _InstallStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF123A5E),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  const _DrawerSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF7A8699),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerNavigationTile extends StatelessWidget {
  const _DrawerNavigationTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.warning = false,
  });

  final MobileNavigationItem item;
  final bool selected;
  final VoidCallback? onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final foreground = warning
        ? const Color(0xFF8A3A3A)
        : selected
        ? const Color(0xFF0D2844)
        : const Color(0xFF344054);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? const Color(0xFFEAF2FA) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(item.icon, size: 21, color: foreground),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 14),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF0D76BD),
                    ),
                  )
                else
                  const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
