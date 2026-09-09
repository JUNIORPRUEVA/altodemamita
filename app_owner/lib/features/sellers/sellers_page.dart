import 'package:flutter/material.dart';

import '../../widgets/owner_entity_records_page.dart';

class SellersPage extends StatelessWidget {
  const SellersPage({
    super.key,
    required this.items,
    this.searchQueryNotifier,
    this.filterNotifier,
    this.allSales = const [],
    this.allClients = const [],
    this.allLots = const [],
  });

  final List<Map<String, dynamic>> items;
  final ValueNotifier<String>? searchQueryNotifier;
  final ValueNotifier<String>? filterNotifier;
  final List<Map<String, dynamic>> allSales;
  final List<Map<String, dynamic>> allClients;
  final List<Map<String, dynamic>> allLots;

  @override
  Widget build(BuildContext context) {
    return OwnerEntityRecordsPage(
      kind: OwnerEntityKind.seller,
      items: items,
      searchQueryNotifier: searchQueryNotifier,
      filterNotifier: filterNotifier,
      allSellers: items,
      allSales: allSales,
      allClients: allClients,
      allLots: allLots,
    );
  }
}
