import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/safe_area_padding.dart';
import '../../core/utils.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/desktop_detail_pane.dart';
import '../../widgets/owner_desktop_page_frame.dart';
import '../../app/responsive.dart';
import 'sale_detail_page.dart';
import 'sale_installments_page.dart';
import 'sale_payments_page.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.items,
    this.searchQueryNotifier,
    this.filterNotifier,
    this.allInstallments = const [],
    this.allPayments = const [],
    this.allClients = const [],
    this.allSellers = const [],
    this.allLots = const [],
  });

  final List<Map<String, dynamic>> items;
  final ValueNotifier<String>? searchQueryNotifier;
  final ValueNotifier<String>? filterNotifier;
  final List<Map<String, dynamic>> allInstallments;
  final List<Map<String, dynamic>> allPayments;
  final List<Map<String, dynamic>> allClients;
  final List<Map<String, dynamic>> allSellers;
  final List<Map<String, dynamic>> allLots;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  String _query = '';
  String _filter = 'Todas';

  @override
  void initState() {
    super.initState();
    widget.searchQueryNotifier?.addListener(_onSearchQueryChanged);
    widget.filterNotifier?.addListener(_onFilterChanged);
    _query = widget.searchQueryNotifier?.value ?? '';
    _filter = widget.filterNotifier?.value ?? 'Todas';
  }

  @override
  void dispose() {
    widget.searchQueryNotifier?.removeListener(_onSearchQueryChanged);
    widget.filterNotifier?.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onSearchQueryChanged() {
    setState(() => _query = widget.searchQueryNotifier?.value ?? '');
  }

  void _onFilterChanged() {
    setState(() => _filter = widget.filterNotifier?.value ?? 'Todas');
  }

  List<Map<String, dynamic>> get _filteredSales {
    final sales = widget.items.where((sale) {
      // Apply status filter
      if (_filter != 'Todas') {
        final status = (sale['status'] as String?)?.toLowerCase() ?? '';
        switch (_filter) {
          case 'Activas':
            if (status != 'activa' && status != 'active') return false;
            break;
          case 'Pendientes':
            if (status != 'pendiente' && status != 'pending') return false;
            break;
          case 'Pagadas':
            if (status != 'pagada' && status != 'paid' && status != 'pagado') {
              return false;
            }
            break;
          case 'Vencidas':
            if (status != 'vencida' &&
                status != 'overdue' &&
                status != 'vencido') {
              return false;
            }
            break;
        }
      }

      // Apply date filter
      if (_filter == 'Hoy' ||
          _filter == 'Esta semana' ||
          _filter == 'Este mes') {
        final dateStr = sale['saleDate']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date == null) return false;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final saleDay = DateTime(date.year, date.month, date.day);

        switch (_filter) {
          case 'Hoy':
            if (saleDay != today) return false;
            break;
          case 'Esta semana':
            final weekStart = today.subtract(Duration(days: today.weekday - 1));
            final weekEnd = weekStart.add(const Duration(days: 6));
            if (saleDay.isBefore(weekStart) || saleDay.isAfter(weekEnd)) {
              return false;
            }
            break;
          case 'Este mes':
            if (saleDay.month != today.month || saleDay.year != today.year) {
              return false;
            }
            break;
        }
      }

      return true;
    }).toList();

    if (_query.trim().isEmpty) return sales;
    final q = _query.toLowerCase();
    return sales.where((sale) {
      final searchable = [
        sale['client'],
        sale['lot'],
        sale['syncId'],
        sale['status'],
        sale['cedula'],
        sale['seller'],
        sale['plan'],
      ].join(' ').toLowerCase();
      return searchable.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sales = _filteredSales;

    return OwnerDesktopPageFrame(
      maxWidth: 1120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: Responsive.isDesktop(context) ? 20 : 16,
                bottom: mobileSafeBottomPadding(context),
              ),
              itemCount: sales.isEmpty ? 2 : sales.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _SalesListHeader(
                    filter: _filter,
                    count: sales.length,
                    onClearFilter: () {
                      setState(() => _filter = 'Todas');
                      widget.filterNotifier?.value = 'Todas';
                    },
                  );
                }

                if (sales.isEmpty) {
                  return _buildEmptyState();
                }

                final itemIndex = index - 1;
                final sale = sales[itemIndex];
                return AnimatedListItem(
                  index: itemIndex,
                  child: _SaleCard(
                    sale: sale,
                    onTap: () => _openDetail(sale),
                    allInstallments: widget.allInstallments,
                    allPayments: widget.allPayments,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilter = _filter != 'Todas' || _query.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            hasFilter ? Icons.search_off_rounded : Icons.storefront_outlined,
            size: 48,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter
                ? 'No se encontraron ventas'
                : 'No hay ventas registradas',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                setState(() {
                  _filter = 'Todas';
                  _query = '';
                });
                widget.filterNotifier?.value = 'Todas';
                widget.searchQueryNotifier?.value = '';
              },
              child: const Text('Limpiar filtros'),
            ),
          ],
        ],
      ),
    );
  }

  void _openDetail(Map<String, dynamic> sale) {
    if (DesktopDetailScope.openIfAvailable(
      context,
      () => SaleDetailPage(
        sale: sale,
        allInstallments: widget.allInstallments,
        allPayments: widget.allPayments,
        allClients: widget.allClients,
        allSellers: widget.allSellers,
        allLots: widget.allLots,
      ),
    )) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailPage(
          sale: sale,
          allInstallments: widget.allInstallments,
          allPayments: widget.allPayments,
          allClients: widget.allClients,
          allSellers: widget.allSellers,
          allLots: widget.allLots,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Sales list header
// ──────────────────────────────────────────────

class _SalesListHeader extends StatelessWidget {
  const _SalesListHeader({
    required this.filter,
    required this.count,
    required this.onClearFilter,
  });

  final String filter;
  final int count;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter != 'Todas') ...[
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filter,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onClearFilter,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '$count ${count == 1 ? 'venta' : 'ventas'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Sale card widget
// ──────────────────────────────────────────────

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.onTap,
    required this.allInstallments,
    required this.allPayments,
  });

  final Map<String, dynamic> sale;
  final VoidCallback onTap;
  final List<Map<String, dynamic>> allInstallments;
  final List<Map<String, dynamic>> allPayments;

  String? get _syncId => sale['syncId']?.toString();
  String? get _saleId => sale['saleId']?.toString();
  String? get _id => sale['id']?.toString();
  String? get _localId => sale['localId']?.toString();

  List<Map<String, dynamic>> get _relatedInstallments {
    if (allInstallments.isEmpty) return [];
    final ids = [_syncId, _saleId, _id, _localId].whereType<String>().toSet();
    if (ids.isEmpty) return [];
    return allInstallments.where((inst) {
      return ids.any(
        (id) =>
            inst['saleId']?.toString() == id ||
            inst['saleSyncId']?.toString() == id ||
            inst['syncId']?.toString() == id,
      );
    }).toList();
  }

  List<Map<String, dynamic>> get _relatedPayments {
    if (allPayments.isEmpty) return [];
    final ids = [_syncId, _saleId, _id, _localId].whereType<String>().toSet();
    if (ids.isEmpty) return [];
    return allPayments.where((pay) {
      return ids.any(
        (id) =>
            pay['saleId']?.toString() == id ||
            pay['saleSyncId']?.toString() == id ||
            pay['syncId']?.toString() == id,
      );
    }).toList();
  }

  void _openInstallments(BuildContext context) {
    final installments = _relatedInstallments;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SaleInstallmentsPage(sale: sale, installments: installments),
      ),
    );
  }

  void _openPayments(BuildContext context) {
    final payments = _relatedPayments;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalePaymentsPage(sale: sale, payments: payments),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'activa':
      case 'active':
        return AppColors.accentBlue;
      case 'pagada':
      case 'paid':
      case 'pagado':
        return AppColors.accentGreen;
      case 'pendiente':
      case 'pending':
        return AppColors.accentAmber;
      case 'vencida':
      case 'overdue':
      case 'vencido':
        return AppColors.accentRose;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'activa':
      case 'active':
        return 'Activa';
      case 'pagada':
      case 'paid':
      case 'pagado':
        return 'Pagada';
      case 'pendiente':
      case 'pending':
        return 'Pendiente';
      case 'vencida':
      case 'overdue':
      case 'vencido':
        return 'Vencida';
      default:
        return status ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = sale['status']?.toString();
    final statusColor = _statusColor(status);
    final client = text(sale['client'], 'Cliente');
    final balance = money(sale['balance']);
    final isDesktop = Responsive.isDesktop(context);
    final radius = isDesktop ? 14.0 : 18.0;

    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 18 : 15,
              isDesktop ? 16 : 14,
              isDesktop ? 14 : 12,
              isDesktop ? 16 : 14,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: isDesktop ? 0.025 : 0.035,
                  ),
                  blurRadius: isDesktop ? 8 : 12,
                  offset: Offset(0, isDesktop ? 3 : 5),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 58,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        client,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.2,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _SaleStatusChip(
                            label: _statusLabel(status),
                            color: statusColor,
                          ),
                          const SizedBox(width: 10),
                          if (balance.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                'Resta $balance',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.3,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _statusLegend(status),
                        style: const TextStyle(
                          fontSize: 11.3,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  padding: EdgeInsets.zero,
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'installments':
                        _openInstallments(context);
                        break;
                      case 'payments':
                        _openPayments(context);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem<String>(
                      value: 'installments',
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 18,
                            color: AppColors.accentBlue,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Ver cuotas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'payments',
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 18,
                            color: AppColors.accentGreen,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Ver pagos',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLegend(String? status) {
    switch (status?.toLowerCase()) {
      case 'activa':
      case 'active':
        return 'Al día — al corriente con sus pagos';
      case 'pagada':
      case 'paid':
      case 'pagado':
        return 'Totalmente liquidada — sin deuda pendiente';
      case 'pendiente':
      case 'pending':
        return 'Con cuotas pendientes por pagar';
      case 'vencida':
      case 'overdue':
      case 'vencido':
        return 'Una o más cuotas están vencidas';
      default:
        return 'Estado sin definir';
    }
  }
}

// ──────────────────────────────────────────────
// Status chip
// ──────────────────────────────────────────────

class _SaleStatusChip extends StatelessWidget {
  const _SaleStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
