import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/resilience/benign_runtime_errors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('suprime database_closed como cierre benigno de SQLite', () {
    expect(
      BenignRuntimeErrors.shouldSuppress(
        _TestDatabaseException('database_closed'),
      ),
      isTrue,
    );
    expect(
      BenignRuntimeErrors.shouldSuppress(
        _TestDatabaseException('This database has already been closed'),
      ),
      isTrue,
    );
  });

  test('no suprime errores reales de base de datos', () {
    expect(
      BenignRuntimeErrors.shouldSuppress(
        _TestDatabaseException('UNIQUE constraint failed: clientes.cedula'),
      ),
      isFalse,
    );
  });
}

class _TestDatabaseException extends DatabaseException {
  _TestDatabaseException(super.message);

  @override
  Object? get result => null;

  @override
  int? getResultCode() => null;
}
