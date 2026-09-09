import 'package:flutter/material.dart';

import '../../widgets/owner_entity_records_page.dart';

class LotsPage extends StatelessWidget {
  const LotsPage({
    super.key,
    required this.items,
    this.searchQueryNotifier,
    this.filterNotifier,
    this.allSales = const [],
    this.allClients = const [],
  });

  final List<Map<String, dynamic>> items;
  final ValueNotifier<String>? searchQueryNotifier;
  final ValueNotifier<String>? filterNotifier;
  final List<Map<String, dynamic>> allSales;
  final List<Map<String, dynamic>> allClients;

  @override
  Widget build(BuildContext context) {
    return OwnerEntityRecordsPage(
      kind: OwnerEntityKind.lot,
      items: items,
      searchQueryNotifier: searchQueryNotifier,
      filterNotifier: filterNotifier,
      allLots: items,
      allSales: allSales,
      allClients: allClients,
    );
  }
}
