import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/responsive.dart';
import '../../core/constants.dart';
import '../../core/models/owner_snapshot.dart';
import '../../core/utils.dart';
import '../../widgets/owner_desktop_page_frame.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.snapshot, this.onOpenModule});

  final OwnerSnapshot snapshot;
  final ValueChanged<OwnerModule>? onOpenModule;

  @override
  Widget build(BuildContext context) {
    final counts = snapshot.dashboard['counts'] as Map<String, dynamic>? ?? {};
    final totals = snapshot.dashboard['totals'] as Map<String, dynamic>? ?? {};
    final sellersCount = counts['sellers'] ?? snapshot.sellers.length;
    final paid = _asNum(totals['paid']);
    final pending = _asNum(totals['balance']);
    final sold = _asNum(totals['sold']);

    final items = <_DashboardItem>[
      _DashboardItem(
        label: 'Cobrado',
        value: money(paid),
        icon: Icons.account_balance_wallet_outlined,
        module: OwnerModule.payments,
        isMoney: true,
      ),
      _DashboardItem(
        label: 'Pendiente',
        value: money(pending),
        icon: Icons.receipt_long_outlined,
        module: OwnerModule.installments,
        isMoney: true,
      ),
      _DashboardItem(
        label: 'Vendido',
        value: money(sold),
        icon: Icons.trending_up,
        module: OwnerModule.sales,
        isMoney: true,
      ),
      _DashboardItem(
        label: 'Ventas',
        value: text(counts['sales'], '0'),
        icon: Icons.point_of_sale_outlined,
        module: OwnerModule.sales,
      ),
      _DashboardItem(
        label: 'Cuotas pendientes',
        value: text(counts['installments'], '0'),
        icon: Icons.event_note_outlined,
        module: OwnerModule.installments,
      ),
      _DashboardItem(
        label: 'Solares',
        value: text(counts['lots'], '0'),
        icon: Icons.map_outlined,
        module: OwnerModule.lots,
      ),
      _DashboardItem(
        label: 'Clientes',
        value: text(counts['clients'], '0'),
        icon: Icons.people_alt_outlined,
        module: OwnerModule.clients,
      ),
      _DashboardItem(
        label: 'Vendedores',
        value: text(sellersCount, '0'),
        icon: Icons.badge_outlined,
        module: OwnerModule.sellers,
      ),
    ];

    return OwnerDesktopPageFrame(
      maxWidth: 1180,
      mobileHorizontalPadding: 16,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          Responsive.isDesktop(context) ? 22 : 16,
          0,
          24,
        ),
        child: _DashboardGrid(items: items, onTap: onOpenModule),
      ),
    );
  }

  num _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _DashboardGrid extends StatelessWidget {
  const _DashboardGrid({required this.items, required this.onTap});

  final List<_DashboardItem> items;
  final ValueChanged<OwnerModule>? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final columns = availableWidth >= 1060
            ? 4
            : availableWidth >= 760
            ? 3
            : availableWidth < 320
            ? 1
            : 2;
        final spacing = Responsive.isDesktop(context) ? 14.0 : 10.0;
        final itemWidth =
            (availableWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((item) {
            return SizedBox(
              width: itemWidth,
              child: _DashboardCard(
                item: item,
                onTap: onTap == null ? null : () => onTap!(item.module),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.item, required this.onTap});

  final _DashboardItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final valueSize = item.isMoney ? (isDesktop ? 17.0 : 15.5) : 24.0;
    final radius = isDesktop ? 14.0 : 16.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          height: isDesktop ? 124 : 112,
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 16 : 13,
            isDesktop ? 16 : 13,
            isDesktop ? 16 : 13,
            isDesktop ? 14 : 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: isDesktop ? 0.025 : 0.035,
                ),
                blurRadius: isDesktop ? 8 : 10,
                offset: Offset(0, isDesktop ? 3 : 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Icon(item.icon, color: AppColors.primary, size: 18),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 19,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: valueSize,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.8,
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardItem {
  const _DashboardItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.module,
    this.isMoney = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final OwnerModule module;
  final bool isMoney;
}
