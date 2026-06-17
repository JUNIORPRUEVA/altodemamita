import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../core/constants.dart';

/// Módulos visibles en el Drawer (excluye Installments y Payments).
const List<OwnerModule> _drawerModules = [
  OwnerModule.dashboard,
  OwnerModule.sales,
  OwnerModule.clients,
  OwnerModule.lots,
  OwnerModule.sellers,
];

IconData _moduleIcon(OwnerModule module) {
  switch (module) {
    case OwnerModule.dashboard:
      return Icons.dashboard_outlined;
    case OwnerModule.clients:
      return Icons.people_alt_outlined;
    case OwnerModule.lots:
      return Icons.map_outlined;
    case OwnerModule.sales:
      return Icons.point_of_sale_outlined;
    case OwnerModule.installments:
      return Icons.event_note_outlined;
    case OwnerModule.payments:
      return Icons.payments_outlined;
    case OwnerModule.sellers:
      return Icons.badge_outlined;
  }
}

class OwnerDrawer extends StatelessWidget {
  const OwnerDrawer({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final OwnerModule selected;
  final ValueChanged<OwnerModule> onSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      elevation: 0,
      backgroundColor: const Color(0xFFF6F9FC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(26),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DrawerHeader(),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                itemCount: _drawerModules.length,
                itemBuilder: (context, index) {
                  final module = _drawerModules[index];
                  final isSelected = selected == module;

                  return _DrawerItem(
                    module: module,
                    selected: isSelected,
                    onTap: () {
                      onSelected(module);

                      // En móvil cierra el drawer después de elegir.
                      final navigator = Navigator.of(context);
                      if (navigator.canPop()) {
                        navigator.pop();
                      }
                    },
                  );
                },
              ),
            ),
            const _DrawerFooter(),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            child: const Icon(
              Icons.real_estate_agent_outlined,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
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
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Owner App',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 12.5,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
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

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.module,
    required this.selected,
    required this.onTap,
  });

  final OwnerModule module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.primary : AppColors.textSecondary;
    final textColor = selected ? AppColors.primary : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.border : Colors.transparent,
                width: 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x0C000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryLight
                        : const Color(0xFFEAF0F6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Icon(
                    _moduleIcon(module),
                    size: 21,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      height: 1.1,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
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

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.cloud_sync_outlined,
              color: AppColors.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'Actualización automática cada 3 segundos.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
