class GlobalSearchResult {
  const GlobalSearchResult({
    this.client,
    this.lot,
    this.seller,
    this.sale,
    this.payments = const [],
    this.installments = const [],
    this.totalPaid = 0,
    this.totalPending = 0,
    this.totalOverdue = 0,
    this.overdueInstallments = 0,
    this.nextPaymentDate,
  });

  final Map<String, dynamic>? client;
  final Map<String, dynamic>? lot;
  final Map<String, dynamic>? seller;
  final Map<String, dynamic>? sale;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> installments;
  final num totalPaid;
  final num totalPending;
  final num totalOverdue;
  final int overdueInstallments;
  final DateTime? nextPaymentDate;

  String get displayClient {
    final value = client?['name'] ?? sale?['client'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Cliente no disponible' : text;
  }

  String get displayLot {
    final value = lot?['display'] ?? sale?['lot'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Solar no disponible' : text;
  }

  String get status {
    final value = sale?['status'] ?? lot?['status'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'No disponible' : text;
  }

  String get displaySeller {
    final value = seller?['name'] ?? sale?['seller'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Vendedor no disponible' : text;
  }
}
