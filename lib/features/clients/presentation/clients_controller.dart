import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../data/client_repository.dart';
import '../domain/client.dart';

class ClientsController extends ChangeNotifier {
  ClientsController({required ClientRepository repository})
    : _repository = repository;

  final ClientRepository _repository;

  bool isLoading = false;
  String currentQuery = '';
  FriendlyErrorMessage? loadError;
  List<Client> clients = const [];

  Future<void> load({String? query}) async {
    if (query != null) {
      currentQuery = query;
    }

    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      clients = await _repository.fetchAll(query: currentQuery);
    } catch (error) {
      loadError = FriendlyErrorMessages.moduleLoad('clientes', error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> save(Client client) async {
    try {
      await _repository.save(client);
      await load();
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'guardar el cliente',
        error,
        module: 'clientes',
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
        'eliminar el cliente',
        error,
        module: 'clientes',
      );
    }
  }
}
