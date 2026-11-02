import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/clients/domain/client_search.dart';

Client _client({
  String name = '',
  String document = '',
  String? phone,
  String? address,
}) {
  final now = DateTime(2026, 1, 1);
  return Client(
    id: 1,
    version: 1,
    fullName: name,
    documentId: document,
    phone: phone,
    address: address,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('foldClientSearchText', () {
    test('quita acentos y pasa a minusculas', () {
      expect(foldClientSearchText('José Ramón Peña'), 'jose ramon pena');
      expect(foldClientSearchText('ILUMINADA RODRÍGUEZ OZUNA'), 'iluminada rodriguez ozuna');
      expect(foldClientSearchText('Núñez'), 'nunez');
    });

    test('colapsa espacios y recorta', () {
      expect(foldClientSearchText('  jose   ramon  '), 'jose ramon');
      expect(foldClientSearchText(''), '');
      expect(foldClientSearchText(null), '');
    });
  });

  group('clientMatchesSearch', () {
    final jose = _client(
      name: 'José Ramón Peña',
      document: '001-1234567-8',
      phone: '809-555-1234',
      address: 'Calle Duarte 45, Santo Domingo',
    );

    test('encuentra por nombre escrito SIN acentos', () {
      expect(clientMatchesSearch(jose, 'jose'), isTrue);
      expect(clientMatchesSearch(jose, 'pena'), isTrue);
      expect(clientMatchesSearch(jose, 'ramon'), isTrue);
    });

    test('encuentra por nombre escrito CON acentos', () {
      expect(clientMatchesSearch(jose, 'José'), isTrue);
      expect(clientMatchesSearch(jose, 'PEÑA'), isTrue);
    });

    test('varias palabras en cualquier orden', () {
      expect(clientMatchesSearch(jose, 'jose pena'), isTrue);
      expect(clientMatchesSearch(jose, 'pena jose'), isTrue);
      expect(clientMatchesSearch(jose, 'ramon pena'), isTrue);
    });

    test('varias palabras exige TODAS (no es OR)', () {
      expect(clientMatchesSearch(jose, 'jose castillo'), isFalse);
    });

    test('encuentra por cedula con o sin separadores', () {
      expect(clientMatchesSearch(jose, '001-1234567-8'), isTrue);
      expect(clientMatchesSearch(jose, '00112345678'), isTrue);
    });

    test('encuentra por telefono con o sin separadores', () {
      expect(clientMatchesSearch(jose, '809-555-1234'), isTrue);
      expect(clientMatchesSearch(jose, '8095551234'), isTrue);
    });

    test('encuentra por direccion (paridad con la busqueda en la nube)', () {
      expect(clientMatchesSearch(jose, 'duarte'), isTrue);
    });

    test('no encuentra un cliente distinto', () {
      expect(clientMatchesSearch(jose, 'castillo'), isFalse);
    });

    test('consulta vacia no filtra', () {
      expect(clientMatchesSearch(jose, ''), isTrue);
      expect(clientMatchesSearch(jose, '   '), isTrue);
    });
  });
}
