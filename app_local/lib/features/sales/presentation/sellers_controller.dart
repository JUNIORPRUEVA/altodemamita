import '../../../shared/controllers/resilient_list_controller.dart';
import '../data/seller_repository.dart';
import '../domain/seller.dart';

/// Controlador del modulo Vendedores con UX cache-first / no-fatal.
class SellersController extends ResilientListController<Seller> {
  SellersController({required SellerRepository repository})
    : super(
        moduleLabel: 'Vendedores',
        fetch: (query) => query.trim().isEmpty
            ? repository.getAll()
            : repository.search(query.trim()),
        fetchCache: repository.fetchCachedList,
        filterCache: _filterSellers,
      );

  List<Seller> get sellers => items;

  static List<Seller> _filterSellers(List<Seller> sellers, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return sellers;
    final digits = query.replaceAll(RegExp(r'\D+'), '');
    return sellers.where((seller) {
      final haystack = [
        seller.name,
        seller.documentId,
        seller.phone,
      ].join(' ').toLowerCase();
      final normalizedDigits = [
        seller.documentId,
        seller.phone,
      ].join(' ').replaceAll(RegExp(r'\D+'), '');
      return haystack.contains(normalized) ||
          (digits.length >= 2 && normalizedDigits.contains(digits));
    }).toList(growable: false);
  }
}
