import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
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

  test('suprime diagnosticos RenderFlex overflow de Flutter', () {
    expect(
      BenignRuntimeErrors.shouldSuppress(
        FlutterError('A RenderFlex overflowed by 4.0 pixels on the bottom.'),
      ),
      isTrue,
    );
  });

  test('suprime diagnosticos Scrollbar sin ScrollPosition de Flutter', () {
    expect(
      BenignRuntimeErrors.shouldSuppress(
        FlutterError(
          "The Scrollbar's ScrollController has no ScrollPosition attached. "
          'A Scrollbar cannot be painted without a ScrollPosition.',
        ),
      ),
      isTrue,
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
