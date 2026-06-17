import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../core/constants.dart';
import '../../core/models/owner_snapshot.dart';
import '../../core/utils.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.snapshot,
    this.onOpenModule,
    this.filterLabel = 'Hoy',
  });

  final OwnerSnapshot snapshot;
  final ValueChanged<OwnerModule>? onOpenModule;
  final String filterLabel;

  @override
  Widget build(BuildContext context) {
    final counts = snapshot.dashboard['counts'] as Map<String, dynamic>? ?? {};
    final sellersCount = counts['sellers'] ?? snapshot.sellers.length;
    final filteredSales = snapshot.sales.where(_matchesFilter).toList();
    final filteredPayments = snapshot.payments.where(_matchesFilter).toList();
    final paid = filteredPayments.fold<num>(
      0,
      (total, payment) => total + _asNum(payment['amount']),
    );
    final pending = filteredSales.fold<num>(
      0,
      (total, sale) => total + _asNum(sale['balance']),
    );
    final sold = filteredSales.fold<num>(
      0,
      (total, sale) => total + _asNum(sale['total']),
    );

    final items = <_DashboardItem>[
      _DashboardItem(
        label: 'Cobrado',
        value: money(paid),
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.accentGreen,
        module: OwnerModule.payments,
        isMoney: true,
      ),
      _DashboardItem(
        label: 'Pendiente',
        value: money(pending),
        icon: Icons.receipt_long_outlined,
        color: AppColors.accentAmber,
        module: OwnerModule.installments,
        isMoney: true,
      ),
      _DashboardItem(
        label: 'Vendido',
        value: money(sold),
        icon: Icons.trending_up,
        color: AppColors.accentBlue,
        module: OwnerModule.sales,
        isMoney: true,
      ),
      _DashboardItem(
        label: 'Ventas',
        value: text(counts['sales'], '0'),
        icon: Icons.point_of_sale_outlined,
        color: AppColors.accentGreen,
        module: OwnerModule.sales,
      ),
      _DashboardItem(
        label: 'Cuotas pendientes',
        value: text(counts['installments'], '0'),
        icon: Icons.event_note_outlined,
        color: AppColors.accentAmber,
        module: OwnerModule.installments,
      ),
      _DashboardItem(
        label: 'Solares',
        value: text(counts['lots'], '0'),
        icon: Icons.map_outlined,
        color: AppColors.accentBlue,
        module: OwnerModule.lots,
      ),
      _DashboardItem(
        label: 'Clientes',
        value: text(counts['clients'], '0'),
        icon: Icons.people_alt_outlined,
        color: AppColors.accentBlue,
        module: OwnerModule.clients,
      ),
      _DashboardItem(
        label: 'Vendedores',
        value: text(sellersCount, '0'),
        icon: Icons.badge_outlined,
        color: AppColors.accentRose,
        module: OwnerModule.sellers,
      ),
    ];

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: _DashboardGrid(items: items, onTap: onOpenModule),
    );
  }

  bool _matchesFilter(Map<String, dynamic> item) {
    final normalized = filterLabel.trim().toLowerCase();
    if (normalized == 'personalizado') return true;
    final date = DateTime.tryParse(
      text(item['saleDate'] ?? item['paidAt'] ?? item['updatedAt'], ''),
    );
    if (date == null) return true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(date.year, date.month, date.day);

    switch (normalized) {
      case 'hoy':
        return itemDay == today;
      case 'ayer':
        return itemDay == today.subtract(const Duration(days: 1));
      case 'esta semana':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return !itemDay.isBefore(weekStart) && !itemDay.isAfter(weekEnd);
      case 'este mes':
        return itemDay.year == today.year && itemDay.month == today.month;
      default:
        return true;
    }
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

        final columns = availableWidth < 320 ? 1 : 2;
        const spacing = 12.0;
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
    final valueSize = item.isMoney ? 17.0 : 26.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 126,
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4EAF1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x07000000),
                blurRadius: 12,
                offset: Offset(0, 5),
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
                      color: item.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 18),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: item.color.withValues(alpha: 0.36),
                    size: 21,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: item.color,
                  fontSize: valueSize,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF7D8B9C),
                  fontSize: 11.8,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
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
    required this.color,
    required this.module,
    this.isMoney = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final OwnerModule module;
  final bool isMoney;
}
