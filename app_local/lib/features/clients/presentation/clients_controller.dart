import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/errors/active_sales_block_delete_exception.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/controllers/resilient_list_controller.dart';
import '../data/client_repository.dart';
import '../domain/client.dart';

class ClientsController extends ResilientListController<Client> {
  ClientsController({required ClientRepository repository})
    : _repository = repository,
      super(
        moduleLabel: 'Clientes',
        fetch: (query) => repository.fetchAll(query: query),
        fetchCache: repository.fetchCachedList,
      );

  final ClientRepository _repository;

  List<Client> get clients => items;

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
      removeItemById((client) => client.id ?? 0, id);
      await load();
      return null;
    } on ActiveSalesBlockDeleteException catch (error) {
      return error.message;
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
      final message = error.message.toString().trim();
      if (message.isNotEmpty) {
        return message;
      }
    }

    if (error is DatabaseException) {
      final normalized = error.toString();
      if (normalized.contains('DUPLICATE_ACTIVE_CLIENT')) {
        return 'Ya existe un cliente activo con esta cédula o documento. Verifica los datos antes de continuar.';
      }
      if (normalized.contains('UNIQUE constraint failed: clientes.cedula')) {
        return 'Ya existe un cliente activo con esta cédula. Verifica los datos antes de continuar.';
      }
      if (normalized.contains('NOT NULL constraint failed: clientes.cedula')) {
        return 'La cédula es obligatoria.';
      }
    }

    return null;
  }
}
