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
      );

  List<Seller> get sellers => items;
}
