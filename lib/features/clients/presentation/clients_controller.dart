import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      debugPrint('ERROR REAL (guardar cliente): $error');

      final decoded = _decodeClientWriteError(error);
      if (decoded != null) {
        FriendlyErrorMessages.forOperation(
          'guardar el cliente',
          error,
          module: 'clientes',
          presentToUser: false,
        );
        return decoded;
      }
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
      debugPrint('ERROR REAL (eliminar cliente): $error');

      final decoded = _decodeClientWriteError(error);
      if (decoded != null) {
        FriendlyErrorMessages.forOperation(
          'eliminar el cliente',
          error,
          module: 'clientes',
          presentToUser: false,
        );
        return decoded;
      }
      return FriendlyErrorMessages.forOperation(
        'eliminar el cliente',
        error,
        module: 'clientes',
      );
    }
  }

  String? _decodeClientWriteError(Object error) {
    if (error is StateError) {
      final message = error.message?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    if (error is DatabaseException) {
      final normalized = error.toString();
      if (normalized.contains('UNIQUE constraint failed: clientes.cedula')) {
        return 'Ya existe un cliente con esa cédula.';
      }
      if (normalized.contains('NOT NULL constraint failed: clientes.cedula')) {
        return 'La cédula es obligatoria.';
      }
    }

    return null;
  }
}
