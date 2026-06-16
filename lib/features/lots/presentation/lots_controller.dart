import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/errors/active_sales_block_delete_exception.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../data/lot_repository.dart';
import '../domain/lot.dart';

class LotsController extends ChangeNotifier {
  LotsController({required LotRepository repository})
    : _repository = repository;

  final LotRepository _repository;

  bool isLoading = false;
  String currentQuery = '';
  FriendlyErrorMessage? loadError;
  List<Lot> lots = const [];

  Future<void> load({String? query}) async {
    if (query != null) {
      currentQuery = query;
    }

    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      lots = await _repository.fetchAll(query: currentQuery);
    } catch (error) {
      loadError = FriendlyErrorMessages.moduleLoad('solares', error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

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
