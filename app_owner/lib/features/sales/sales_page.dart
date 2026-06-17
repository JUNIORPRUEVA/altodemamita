import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../core/utils.dart';
import 'sale_detail_page.dart';
import 'sale_installments_page.dart';
import 'sale_payments_page.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.items,
    this.searchNotifier,
    this.filterTriggerNotifier,
    this.allInstallments = const [],
    this.allPayments = const [],
  });

  final List<Map<String, dynamic>> items;
  final ValueNotifier<bool>? searchNotifier;
  final ValueNotifier<int>? filterTriggerNotifier;
  final List<Map<String, dynamic>> allInstallments;
  final List<Map<String, dynamic>> allPayments;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  String _query = '';
  String _filter = 'Todas';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searchNotifier?.addListener(_onSearchToggle);
    widget.filterTriggerNotifier?.addListener(_onFilterTrigger);
  }

  @override
  void dispose() {
    widget.searchNotifier?.removeListener(_onSearchToggle);
    widget.filterTriggerNotifier?.removeListener(_onFilterTrigger);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onFilterTrigger() {
    showFilterSheet();
  }

  void _onSearchToggle() {
    if (widget.searchNotifier?.value ?? false) {
      setState(() {
        _showSearch = true;
      });
      _searchFocus.requestFocus();
    } else {
      setState(() {
        _showSearch = false;
        _searchController.clear();
        _query = '';
        _searchFocus.unfocus();
      });
    }
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
            if (status != 'pagada' && status != 'paid' && status != 'pagado') return false;
            break;
          case 'Vencidas':
            if (status != 'vencida' && status != 'overdue' && status != 'vencido') return false;
            break;
        }
      }

      // Apply date filter
      if (_filter == 'Hoy' || _filter == 'Esta semana' || _filter == 'Este mes') {
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
            if (saleDay.isBefore(weekStart) || saleDay.isAfter(weekEnd)) return false;
            break;
          case 'Este mes':
            if (saleDay.month != today.month || saleDay.year != today.year) return false;
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

  void showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SaleFilterSheet(
        current: _filter,
        onSelected: (value) {
          Navigator.pop(ctx);
          setState(() => _filter = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sales = _filteredSales;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar (toggleable via AppBar search button)
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          height: _showSearch ? 48 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _showSearch ? 1.0 : 0.0,
            child: _showSearch ? _buildSearchField() : const SizedBox.shrink(),
          ),
        ),
        if (_showSearch) const SizedBox(height: 8),
        // Active filter chip
        if (_filter != 'Todas') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        _filter,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _filter = 'Todas'),
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
          ),
        ],
        // Count label
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '${sales.length} ${sales.length == 1 ? 'venta' : 'ventas'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Sales list
        if (sales.isEmpty)
          _buildEmptyState()
        else
          ...sales.map((sale) => _SaleCard(
                sale: sale,
                onTap: () => _openDetail(sale),
                allInstallments: widget.allInstallments,
                allPayments: widget.allPayments,
              )),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textSecondary,
          size: 20,
        ),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textSecondary,
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            : null,
        hintText: 'Buscar cliente, solar, ID...',
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      onChanged: (value) => setState(() => _query = value),
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
                  _searchController.clear();
                });
              },
              child: const Text('Limpiar filtros'),
            ),
          ],
        ],
      ),
    );
  }

  void _openDetail(Map<String, dynamic> sale) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailPage(
          sale: sale,
          allInstallments: widget.allInstallments,
          allPayments: widget.allPayments,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Filter bottom sheet
// ──────────────────────────────────────────────

class _SaleFilterSheet extends StatelessWidget {
  const _SaleFilterSheet({
    required this.current,
    required this.onSelected,
  });

  final String current;
  final ValueChanged<String> onSelected;

  static const _filters = [
    'Todas',
    'Activas',
    'Pendientes',
    'Pagadas',
    'Vencidas',
    'Hoy',
    'Esta semana',
    'Este mes',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filtrar ventas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _filters.map((f) {
                final selected = f == current;
                return ChoiceChip(
                  label: Text(f),
                  selected: selected,
                  onSelected: (_) => onSelected(f),
                  selectedColor: AppColors.primaryLight,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.border,
                    ),
                  ),
                  backgroundColor: Colors.white,
                );
              }).toList(),
            ),
          ],
        ),
      ),
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
      return ids.any((id) =>
          inst['saleId']?.toString() == id ||
          inst['saleSyncId']?.toString() == id ||
          inst['syncId']?.toString() == id);
    }).toList();
  }

  List<Map<String, dynamic>> get _relatedPayments {
    if (allPayments.isEmpty) return [];
    final ids = [_syncId, _saleId, _id, _localId].whereType<String>().toSet();
    if (ids.isEmpty) return [];
    return allPayments.where((pay) {
      return ids.any((id) =>
          pay['saleId']?.toString() == id ||
          pay['saleSyncId']?.toString() == id ||
          pay['syncId']?.toString() == id);
    }).toList();
  }

  void _openInstallments(BuildContext context) {
    final installments = _relatedInstallments;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleInstallmentsPage(
          sale: sale,
          installments: installments,
        ),
      ),
    );
  }

  void _openPayments(BuildContext context) {
    final payments = _relatedPayments;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalePaymentsPage(
          sale: sale,
          payments: payments,
        ),
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
    final lot = text(sale['lot'], '-');
    final balance = money(sale['balance']);
    final total = money(sale['total']);
    final date = dateText(sale['saleDate']);
    final cedula = text(sale['cedula'], '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status indicator
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Client name + status badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              client,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _SaleStatusChip(
                            label: _statusLabel(status),
                            color: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Lot + date
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            lot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Balance row
                      Row(
                        children: [
                          if (cedula.isNotEmpty) ...[
                            Text(
                              cedula,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Text(
                            'Total: $total',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            balance,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Menu with quick actions
                PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: AppColors.textMuted,
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
                          Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.accentBlue),
                          SizedBox(width: 10),
                          Text('Ver cuotas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'payments',
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet_rounded, size: 18, color: AppColors.accentGreen),
                          SizedBox(width: 10),
                          Text('Ver pagos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
}

// ──────────────────────────────────────────────
// Status chip
// ──────────────────────────────────────────────

class _SaleStatusChip extends StatelessWidget {
  const _SaleStatusChip({
    required this.label,
    required this.color,
  });

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
