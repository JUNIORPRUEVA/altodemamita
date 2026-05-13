import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/utils/dominican_validators.dart';

void main() {
  group('DominicanValidators.validateDominicanId', () {
    test('accepts a valid cedula checksum', () {
      expect(
        DominicanValidators.validateDominicanId('402-1234567-8'),
        isNull,
      );
    });

    test('accepts a valid cedula without dashes', () {
      expect(
        DominicanValidators.validateDominicanId('40212345678'),
        isNull,
      );
    });

    test('rejects an invalid cedula checksum', () {
      expect(
        DominicanValidators.validateDominicanId('402-1234567-9'),
        'La cédula no es válida.',
      );
    });

    test('formats valid cedulas consistently', () {
      expect(
        DominicanValidators.formatDominicanId('40212345678'),
        '402-1234567-8',
      );
    });
  });

  group('DominicanValidators.validateDominicanPhone', () {
    test('accepts valid local prefixes', () {
      expect(
        DominicanValidators.validateDominicanPhone('8091234567'),
        isNull,
      );
      expect(
        DominicanValidators.validateDominicanPhone('(829) 555-0199'),
        isNull,
      );
      expect(
        DominicanValidators.validateDominicanPhone('+1 849 555 0199'),
        isNull,
      );
    });

    test('rejects invalid prefixes', () {
      expect(
        DominicanValidators.validateDominicanPhone('7001234567'),
        'El teléfono debe iniciar con 809, 829 o 849.',
      );
    });

    test('formats phone numbers consistently', () {
      expect(
        DominicanValidators.formatDominicanPhone('+1 809 555 0199'),
        '(809) 555-0199',
      );
    });
  });

  group('DominicanValidators.validateFlexibleDocumentId', () {
    test('accepts numeric documents with separators', () {
      expect(
        DominicanValidators.validateFlexibleDocumentId('402-1234567-8'),
        isNull,
      );
    });

    test('accepts numeric documents longer than 11 digits', () {
      expect(
        DominicanValidators.validateFlexibleDocumentId('123456789012345'),
        isNull,
      );
    });
  });

  group('DominicanValidators.validateFlexiblePhone', () {
    test('accepts numbers with 10 or more digits', () {
      expect(
        DominicanValidators.validateFlexiblePhone('8091234567'),
        isNull,
      );
      expect(
        DominicanValidators.validateFlexiblePhone('18095550199'),
        isNull,
      );
    });

    test('rejects numbers shorter than 10 digits', () {
      expect(
        DominicanValidators.validateFlexiblePhone('123456789'),
        'El teléfono debe tener al menos 10 dígitos.',
      );
    });
  });
}
