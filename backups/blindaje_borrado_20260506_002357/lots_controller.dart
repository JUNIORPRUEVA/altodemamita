import 'package:flutter/foundation.dart';

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
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'eliminar el solar',
        error,
        module: 'solares',
      );
    }
  }
}
