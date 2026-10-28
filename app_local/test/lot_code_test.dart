import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/lots/domain/lot_code.dart';

Lot _lot(String block, String number, {String status = 'disponible'}) {
  return Lot(
    id: 1,
    blockNumber: block,
    lotNumber: number,
    area: 100,
    pricePerSquareMeter: 1000,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('LotCode.canonicalBlock', () {
    test('quita el prefijo de manzana del backend', () {
      expect(LotCode.canonicalBlock('M-N'), 'N');
      expect(LotCode.canonicalBlock('M-Ñ'), 'Ñ');
      expect(LotCode.canonicalBlock('M'), '');
      expect(LotCode.canonicalBlock('N'), 'N');
      expect(LotCode.canonicalBlock(' A '), 'A');
    });
  });

  group('Lot.displayCode', () {
    test('nunca duplica el prefijo de manzana', () {
      expect(_lot('M-N', '493').displayCode, 'MN-S493');
      expect(_lot('N', '493').displayCode, 'MN-S493');
      expect(_lot('M-Ñ', '272').displayCode, 'MÑ-S272');
      expect(_lot('A', '10').displayCode, 'MA-S10');
    });

    test('conserva la diferencia entre N y Ñ', () {
      expect(
        _lot('M-Ñ', '272').displayCode,
        isNot(_lot('M-N', '272').displayCode),
      );
      expect(_lot('M-Ñ', '272').displayCode, 'MÑ-S272');
      expect(_lot('M-N', '272').displayCode, 'MN-S272');
    });
  });

  group('Lot.matchesQuery', () {
    final ene = _lot('M-N', '272');
    final enye = _lot('M-Ñ', '272');

    test('acepta numero solo, codigo completo y formato con espacios', () {
      expect(enye.matchesQuery('272'), isTrue);
      expect(enye.matchesQuery('M-Ñ 272'), isTrue);
      expect(enye.matchesQuery('M-Ñ-S272'), isTrue);
      expect(enye.matchesQuery('mñs272'), isTrue);
      expect(enye.matchesQuery('  M Ñ 272 '), isTrue);
      expect(enye.matchesQuery('MÑ-S272'), isTrue);
    });

    test('distingue N de Ñ', () {
      expect(enye.matchesQuery('M-N 272'), isFalse);
      expect(ene.matchesQuery('M-Ñ 272'), isFalse);
      expect(ene.matchesQuery('M-N 272'), isTrue);
    });

    test('una busqueda por numero coincide con varias manzanas', () {
      // Ambiguedad esperada: el llamador debe exigir seleccion explicita.
      expect(ene.matchesQuery('272'), isTrue);
      expect(enye.matchesQuery('272'), isTrue);
    });

    test('no coincide con codigos ajenos', () {
      expect(enye.matchesQuery('493'), isFalse);
      expect(enye.matchesQuery('M-K 272'), isFalse);
    });

    test('acepta area y precio como criterio adicional', () {
      expect(enye.matchesQuery('100.00'), isTrue);
      expect(enye.matchesQuery('1000.00'), isTrue);
    });
  });

  group('Lot estado', () {
    test('isAvailable y statusLabel son canonicos', () {
      expect(_lot('M-N', '1', status: 'disponible').isAvailable, isTrue);
      expect(_lot('M-N', '1', status: 'Disponible').isAvailable, isTrue);
      expect(_lot('M-N', '1', status: 'vendido').isAvailable, isFalse);
      expect(_lot('M-N', '1', status: 'VENDIDO').statusLabel, 'Vendido');
      expect(_lot('M-N', '1', status: 'reservado').statusLabel, 'Reservado');
    });
  });
}
