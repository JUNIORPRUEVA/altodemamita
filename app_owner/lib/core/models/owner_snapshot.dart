class OwnerSnapshot {
  const OwnerSnapshot({
    required this.dashboard,
    required this.clients,
    required this.sellers,
    required this.lots,
    required this.sales,
    required this.installments,
    required this.payments,
  });

  final Map<String, dynamic> dashboard;
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> sellers;
  final List<Map<String, dynamic>> lots;
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> installments;
  final List<Map<String, dynamic>> payments;
}

List<Map<String, dynamic>> listOfMaps(Object? maybeList) {
  if (maybeList is List) {
    return maybeList.cast<Map<String, dynamic>>();
  }
  return [];
}
