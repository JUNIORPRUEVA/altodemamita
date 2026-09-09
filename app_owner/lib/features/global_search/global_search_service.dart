import '../../core/models/owner_snapshot.dart';
import 'global_search_models.dart';

class GlobalSearchService {
  const GlobalSearchService();

  List<GlobalSearchResult> search(OwnerSnapshot snapshot, String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];

    final normalized = _normalize(query);
    final resultsByKey = <String, GlobalSearchResult>{};

    for (final sale in snapshot.sales) {
      if (_matchesSale(sale, query, normalized)) {
        final result = _buildFromSale(snapshot, sale);
        resultsByKey[_resultKey(result)] = result;
      }
    }

    for (final client in snapshot.clients) {
      if (_matchesClient(client, query, normalized)) {
        final relatedSales = _salesForClient(snapshot.sales, client);
        if (relatedSales.isEmpty) {
          final result = _buildResult(snapshot, client: client);
          resultsByKey[_resultKey(result)] = result;
        } else {
          for (final sale in relatedSales) {
            final result = _buildFromSale(snapshot, sale, client: client);
            resultsByKey[_resultKey(result)] = result;
          }
        }
      }
    }

    for (final lot in snapshot.lots) {
      if (_matchesLot(lot, query, normalized)) {
        final relatedSales = _salesForLot(snapshot.sales, lot);
        if (relatedSales.isEmpty) {
          final result = _buildResult(snapshot, lot: lot);
          resultsByKey[_resultKey(result)] = result;
        } else {
          for (final sale in relatedSales) {
            final result = _buildFromSale(snapshot, sale, lot: lot);
            resultsByKey[_resultKey(result)] = result;
          }
        }
      }
    }

    final results = resultsByKey.values.toList();
    results.sort((a, b) => b.totalPending.compareTo(a.totalPending));
    return results;
  }

  bool _matchesClient(
    Map<String, dynamic> client,
    String query,
    String normalized,
  ) {
    return _contains(client['name'], query) ||
        _containsNormalized(client['document'], normalized) ||
        _containsNormalized(client['phone'], normalized) ||
        _containsNormalized(client['syncId'], normalized) ||
        _containsNormalized(client['id'], normalized);
  }

  bool _matchesLot(Map<String, dynamic> lot, String query, String normalized) {
    return _contains(lot['display'], query) ||
        _contains(lot['number'], query) ||
        _contains(lot['block'], query) ||
        _contains(lot['status'], query) ||
        _containsNormalized(lot['syncId'], normalized) ||
        _containsNormalized(lot['id'], normalized);
  }

  bool _matchesSale(
    Map<String, dynamic> sale,
    String query,
    String normalized,
  ) {
    return _contains(sale['client'], query) ||
        _contains(sale['lot'], query) ||
        _contains(sale['status'], query) ||
        _contains(sale['seller'], query) ||
        _containsNormalized(sale['syncId'], normalized) ||
        _containsNormalized(sale['saleId'], normalized) ||
        _containsNormalized(sale['clientPhone'], normalized) ||
        _containsNormalized(sale['cedula'], normalized) ||
        _containsNormalized(sale['lotSyncId'], normalized) ||
        _containsNormalized(sale['clientSyncId'], normalized);
  }

  GlobalSearchResult _buildFromSale(
    OwnerSnapshot snapshot,
    Map<String, dynamic> sale, {
    Map<String, dynamic>? client,
    Map<String, dynamic>? lot,
  }) {
    final resolvedClient = client ?? _clientForSale(snapshot.clients, sale);
    final resolvedLot = lot ?? _lotForSale(snapshot.lots, sale);
    final resolvedSeller = _sellerForSale(snapshot.sellers, sale);
    return _buildResult(
      snapshot,
      client: resolvedClient,
      lot: resolvedLot,
      seller: resolvedSeller,
      sale: sale,
    );
  }

  GlobalSearchResult _buildResult(
    OwnerSnapshot snapshot, {
    Map<String, dynamic>? client,
    Map<String, dynamic>? lot,
    Map<String, dynamic>? seller,
    Map<String, dynamic>? sale,
  }) {
    final sales = sale != null
        ? [sale]
        : client != null
        ? _salesForClient(snapshot.sales, client)
        : lot != null
        ? _salesForLot(snapshot.sales, lot)
        : <Map<String, dynamic>>[];
    final selectedSale = sale ?? (sales.isEmpty ? null : sales.first);
    final saleIds = sales.expand(_saleIds).toSet();
    final payments =
        snapshot.payments
            .where((payment) {
              return saleIds.any(
                    (id) => _paymentSaleIds(payment).contains(id),
                  ) ||
                  (client != null &&
                      _clientIds(
                        client,
                      ).any(_paymentClientIds(payment).contains));
            })
            .toList(growable: true)
          ..sort(_comparePayments);
    final installments =
        snapshot.installments
            .where((installment) {
              return saleIds.any(
                (id) => _installmentSaleIds(installment).contains(id),
              );
            })
            .toList(growable: true)
          ..sort(_compareInstallments);

    final totalPaid = payments.fold<num>(
      0,
      (total, payment) => total + _asNum(payment['amount']),
    );
    final totalPending = sales.fold<num>(
      0,
      (total, item) => total + _asNum(item['balance']),
    );
    var totalOverdue = 0.0;
    var overdueInstallments = 0;
    DateTime? nextPaymentDate;
    final today = DateTime.now();

    for (final installment in installments) {
      final dueDate = DateTime.tryParse(
        installment['dueDate']?.toString() ?? '',
      );
      final status = installment['status']?.toString().toLowerCase() ?? '';
      final isPaid = status.contains('pag') || status.contains('paid');
      final isOverdue =
          status.contains('venc') ||
          status.contains('overdue') ||
          (dueDate != null &&
              dueDate.isBefore(DateTime(today.year, today.month, today.day)) &&
              !isPaid);
      if (isOverdue) {
        overdueInstallments++;
        totalOverdue += _installmentDueAmount(installment).toDouble();
      }
      if (!isPaid && dueDate != null) {
        if (nextPaymentDate == null || dueDate.isBefore(nextPaymentDate)) {
          nextPaymentDate = dueDate;
        }
      }
    }

    return GlobalSearchResult(
      client: client ?? _clientForSale(snapshot.clients, selectedSale),
      lot: lot ?? _lotForSale(snapshot.lots, selectedSale),
      seller: seller ?? _sellerForSale(snapshot.sellers, selectedSale),
      sale: selectedSale,
      payments: payments,
      installments: installments,
      totalPaid: totalPaid,
      totalPending: totalPending,
      totalOverdue: totalOverdue,
      overdueInstallments: overdueInstallments,
      nextPaymentDate: nextPaymentDate,
    );
  }

  Map<String, dynamic>? _sellerForSale(
    List<Map<String, dynamic>> sellers,
    Map<String, dynamic>? sale,
  ) {
    if (sale == null) return null;
    final sellerSyncId = sale['sellerSyncId']?.toString().trim() ?? '';
    final sellerName = sale['seller']?.toString().trim().toLowerCase() ?? '';
    return sellers.cast<Map<String, dynamic>?>().firstWhere((seller) {
      if (seller == null) return false;
      return (sellerSyncId.isNotEmpty &&
              seller['syncId']?.toString() == sellerSyncId) ||
          (sellerName.isNotEmpty &&
              seller['name']?.toString().trim().toLowerCase() == sellerName);
    }, orElse: () => null);
  }

  Map<String, dynamic>? _clientForSale(
    List<Map<String, dynamic>> clients,
    Map<String, dynamic>? sale,
  ) {
    if (sale == null) return null;
    final ids = _saleClientIds(sale);
    final name = sale['client']?.toString().trim().toLowerCase() ?? '';
    final document = sale['cedula']?.toString().trim().toLowerCase() ?? '';
    return clients.cast<Map<String, dynamic>?>().firstWhere((client) {
      if (client == null) return false;
      return _clientIds(client).any(ids.contains) ||
          (name.isNotEmpty &&
              client['name']?.toString().trim().toLowerCase() == name) ||
          (document.isNotEmpty &&
              client['document']?.toString().trim().toLowerCase() == document);
    }, orElse: () => null);
  }

  Map<String, dynamic>? _lotForSale(
    List<Map<String, dynamic>> lots,
    Map<String, dynamic>? sale,
  ) {
    if (sale == null) return null;
    final ids = _saleLotIds(sale);
    final label = sale['lot']?.toString().trim().toLowerCase() ?? '';
    return lots.cast<Map<String, dynamic>?>().firstWhere((lot) {
      if (lot == null) return false;
      final number = lot['number']?.toString().trim().toLowerCase() ?? '';
      final display = lot['display']?.toString().trim().toLowerCase() ?? '';
      return _lotIds(lot).any(ids.contains) ||
          (label.isNotEmpty &&
              (label == display ||
                  label == number ||
                  label == 'solar $number'));
    }, orElse: () => null);
  }

  List<Map<String, dynamic>> _salesForClient(
    List<Map<String, dynamic>> sales,
    Map<String, dynamic> client,
  ) {
    final ids = _clientIds(client);
    final name = client['name']?.toString().trim().toLowerCase() ?? '';
    final document = client['document']?.toString().trim().toLowerCase() ?? '';
    return sales
        .where((sale) {
          return _saleClientIds(sale).any(ids.contains) ||
              (name.isNotEmpty &&
                  sale['client']?.toString().trim().toLowerCase() == name) ||
              (document.isNotEmpty &&
                  sale['cedula']?.toString().trim().toLowerCase() == document);
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _salesForLot(
    List<Map<String, dynamic>> sales,
    Map<String, dynamic> lot,
  ) {
    final ids = _lotIds(lot);
    final number = lot['number']?.toString().trim().toLowerCase() ?? '';
    final display = lot['display']?.toString().trim().toLowerCase() ?? '';
    return sales
        .where((sale) {
          final label = sale['lot']?.toString().trim().toLowerCase() ?? '';
          return _saleLotIds(sale).any(ids.contains) ||
              (label.isNotEmpty &&
                  (label == display ||
                      label == number ||
                      label == 'solar $number'));
        })
        .toList(growable: false);
  }

  String _resultKey(GlobalSearchResult result) {
    final saleId = result.sale?['syncId'] ?? result.sale?['saleId'];
    final clientId = result.client?['syncId'] ?? result.client?['id'];
    final lotId = result.lot?['syncId'] ?? result.lot?['id'];
    final sellerId = result.seller?['syncId'] ?? result.seller?['id'];
    return [saleId, clientId, lotId, sellerId].whereType<Object>().join('|');
  }

  Set<String> _clientIds(Map<String, dynamic> client) {
    return [
      client['syncId'],
      client['id'],
      client['localId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _lotIds(Map<String, dynamic> lot) {
    return [
      lot['syncId'],
      lot['id'],
      lot['localId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _saleIds(Map<String, dynamic> sale) {
    return [
      sale['syncId'],
      sale['saleId'],
      sale['id'],
      sale['localId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _saleClientIds(Map<String, dynamic> sale) {
    return [
      sale['clientSyncId'],
      sale['clientId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _saleLotIds(Map<String, dynamic> sale) {
    return [
      sale['lotSyncId'],
      sale['lotId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _paymentSaleIds(Map<String, dynamic> payment) {
    return [
      payment['saleSyncId'],
      payment['saleId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _paymentClientIds(Map<String, dynamic> payment) {
    return [
      payment['clientSyncId'],
      payment['clientId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  Set<String> _installmentSaleIds(Map<String, dynamic> installment) {
    return [
      installment['saleSyncId'],
      installment['saleId'],
    ].whereType<Object>().map((value) => value.toString()).toSet();
  }

  bool _contains(Object? value, String query) {
    return value?.toString().toLowerCase().contains(query.toLowerCase()) ??
        false;
  }

  bool _containsNormalized(Object? value, String normalized) {
    if (normalized.isEmpty) return false;
    return _normalize(value?.toString() ?? '').contains(normalized);
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
  }

  num _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  num _installmentDueAmount(Map<String, dynamic> installment) {
    final total = _asNum(installment['totalAmount']);
    final paid = _asNum(installment['paidAmount']);
    final pending = total - paid;
    if (pending > 0) return pending;
    if (total > 0 && paid <= 0) return total;
    return 0;
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

  int _comparePayments(Map<String, dynamic> left, Map<String, dynamic> right) {
    return _compareDates(left['paidAt'], right['paidAt']);
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
}
