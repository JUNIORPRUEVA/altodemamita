import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../widgets/records_page.dart';

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key, required this.items, this.searchNotifier});

  final List<Map<String, dynamic>> items;
  final ValueNotifier<bool>? searchNotifier;

  @override
  Widget build(BuildContext context) {
    final orderedItems = [...items]..sort(_comparePayments);
    return RecordsPage(
      items: orderedItems,
      builder: RecordBuilders.payment,
      searchHint: 'Buscar por referencia, método...',
      searchNotifier: searchNotifier,
      accentColor: const Color(0xFF1B7A4A),
    );
  }
}

int _comparePayments(Map<String, dynamic> left, Map<String, dynamic> right) {
  final leftDate = DateTime.tryParse(left['paidAt']?.toString() ?? '');
  final rightDate = DateTime.tryParse(right['paidAt']?.toString() ?? '');
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return leftDate.compareTo(rightDate);
}
