import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/safe_area_padding.dart';
import '../../core/utils.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_card.dart';
import '../../widgets/record_card.dart';

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({
    super.key,
    required this.items,
    this.searchQueryNotifier,
    this.filterNotifier,
  });

  final List<Map<String, dynamic>> items;
  final ValueNotifier<String>? searchQueryNotifier;
  final ValueNotifier<String>? filterNotifier;

  @override
  State<InstallmentsPage> createState() => _InstallmentsPageState();
}

class _InstallmentsPageState extends State<InstallmentsPage> {
  String _query = '';
  String _filter = 'Todas';

  @override
  void initState() {
    super.initState();
    widget.searchQueryNotifier?.addListener(_onQueryChanged);
    widget.filterNotifier?.addListener(_onFilterChanged);
    _query = widget.searchQueryNotifier?.value ?? '';
    _filter = widget.filterNotifier?.value ?? 'Todas';
  }

  @override
  void didUpdateWidget(covariant InstallmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQueryNotifier != widget.searchQueryNotifier) {
      oldWidget.searchQueryNotifier?.removeListener(_onQueryChanged);
      widget.searchQueryNotifier?.addListener(_onQueryChanged);
      _query = widget.searchQueryNotifier?.value ?? '';
    }
    if (oldWidget.filterNotifier != widget.filterNotifier) {
      oldWidget.filterNotifier?.removeListener(_onFilterChanged);
      widget.filterNotifier?.addListener(_onFilterChanged);
      _filter = widget.filterNotifier?.value ?? 'Todas';
    }
  }

  @override
  void dispose() {
    widget.searchQueryNotifier?.removeListener(_onQueryChanged);
    widget.filterNotifier?.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() => _query = widget.searchQueryNotifier?.value ?? '');
  }

  void _onFilterChanged() {
    setState(() => _filter = widget.filterNotifier?.value ?? 'Todas');
  }

  List<Map<String, dynamic>> get _items {
    final query = _query.trim().toLowerCase();
    final orderedItems = [...widget.items]..sort(_compareInstallments);
    return orderedItems
        .where((item) {
          if (query.isNotEmpty &&
              !item.toString().toLowerCase().contains(query)) {
            return false;
          }
          return _matchesFilter(item);
        })
        .toList(growable: false);
  }

  bool _matchesFilter(Map<String, dynamic> item) {
    if (_filter == 'Todas') return true;
    final status = item['status']?.toString().toLowerCase() ?? '';
    final isPaid = status.contains('pag') || status.contains('paid');
    final isOverdue = _isOverdueInstallment(item);
    if (_filter == 'Pendientes') return !isPaid && !isOverdue;
    if (_filter == 'Vencidas') return isOverdue;
    if (_filter == 'Pagadas') return isPaid;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: 16,
                bottom: mobileSafeBottomPadding(context),
              ),
              itemCount: items.isEmpty ? 2 : items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _InstallmentsListHeader(
                    filter: _filter,
                    count: items.length,
                    onClearFilter: () {
                      setState(() => _filter = 'Todas');
                      widget.filterNotifier?.value = 'Todas';
                    },
                  );
                }

                if (items.isEmpty) {
                  return EmptyCard(
                    title: _query.isNotEmpty || _filter != 'Todas'
                        ? 'No hay cuotas con ese criterio.'
                        : 'No hay cuotas registradas.',
                  );
                }

                final itemIndex = index - 1;
                return AnimatedListItem(
                  index: itemIndex,
                  child: RecordCard(
                    view: RecordBuilders.installment(items[itemIndex]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallmentsListHeader extends StatelessWidget {
  const _InstallmentsListHeader({
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
          _ActiveFilterChip(label: filter, onClear: onClearFilter),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '$count ${count == 1 ? 'cuota' : 'cuotas'}',
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

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.primary,
              size: 15,
            ),
          ),
        ],
      ),
    );
  }
}

int _compareInstallments(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final byNumber = _installmentNumber(
    left,
  ).compareTo(_installmentNumber(right));
  if (byNumber != 0) return byNumber;
  return _compareDates(left['dueDate'], right['dueDate']);
}

int _installmentNumber(Map<String, dynamic> installment) {
  return int.tryParse(installment['installmentNumber']?.toString() ?? '') ??
      999999;
}

int _compareDates(Object? left, Object? right) {
  final leftDate = DateTime.tryParse(left?.toString() ?? '');
  final rightDate = DateTime.tryParse(right?.toString() ?? '');
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return leftDate.compareTo(rightDate);
}

bool _isOverdueInstallment(Map<String, dynamic> installment) {
  final status = installment['status']?.toString().toLowerCase() ?? '';
  final isPaid = status.contains('pag') || status.contains('paid');
  if (status.contains('venc') || status.contains('overdue')) return true;
  final dueDate = DateTime.tryParse(installment['dueDate']?.toString() ?? '');
  if (dueDate == null || isPaid) return false;
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  return dueDate.isBefore(todayOnly);
}
