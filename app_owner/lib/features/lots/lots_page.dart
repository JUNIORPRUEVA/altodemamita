import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../widgets/records_page.dart';

class LotsPage extends StatelessWidget {
  const LotsPage({
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
      builder: RecordBuilders.lot,
      searchHint: 'Buscar por número, manzana...',
      searchNotifier: searchNotifier,
    );
  }
}
