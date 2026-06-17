import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../widgets/records_page.dart';

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({
    super.key,
    required this.items,
    this.searchNotifier,
  });

  final List<Map<String, dynamic>> items;
  final ValueNotifier<bool>? searchNotifier;

  @override
  Widget build(BuildContext context) {
    return RecordsPage(
      items: items,
      builder: RecordBuilders.payment,
      searchHint: 'Buscar por referencia, método...',
      searchNotifier: searchNotifier,
      accentColor: const Color(0xFF1B7A4A),
    );
  }
}
