import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/errors/active_sales_block_delete_exception.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/controllers/resilient_list_controller.dart';
import '../data/lot_repository.dart';
import '../domain/lot.dart';

class LotsController extends ResilientListController<Lot> {
  LotsController({required LotRepository repository})
    : _repository = repository,
      super(
        moduleLabel: 'Solares',
        fetch: (query) => repository.fetchAll(query: query),
        fetchCache: repository.fetchCachedList,
      );

  final LotRepository _repository;

  List<Lot> get lots => items;

  Future<String?> save(Lot lot) async {
    try {
      await _repository.save(lot);
      await load();
      return null;
    } on DuplicateLotException catch (error) {
      return error.message;
    } on DatabaseException catch (error) {
      return _decodeLotWriteError(error) ??
          FriendlyErrorMessages.forOperation(
            'guardar el solar',
            error,
            module: 'solares',
          );
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'guardar el solar',
        error,
        module: 'solares',
      );
    }
  }

  Future<String?> delete(int id) async {
    try {
      await _repository.delete(id);
      removeItemById((lot) => lot.id ?? 0, id);
      await load();
      return null;
    } on ActiveSalesBlockDeleteException catch (error) {
      return error.message;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'eliminar el solar',
        error,
        module: 'solares',
      );
    }
  }

  String? _decodeLotWriteError(Object error) {
    final normalized = error.toString();
    if (normalized.contains('DUPLICATE_ACTIVE_LOT') ||
        normalized.contains('uq_solares_manzana_solar_active')) {
      return 'Ya existe un solar activo con este número. No se permiten solares repetidos.';
    }
    return null;
  }
}
