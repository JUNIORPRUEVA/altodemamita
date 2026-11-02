import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/clients/presentation/client_admin_fields.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/lots/presentation/lot_admin_fields.dart';

/// FASE 04B — contrato de los campos administrativos OWNER.
///
/// Estos tests fijan dos defectos reales detectados en la revisión del
/// trabajo pendiente de 04B:
///  1. El campo `price` del solar se enviaba con el precio TOTAL cuando el
///     backend persiste PRECIO POR M² (corrompía el catálogo).
///  2. El campo `name` del cliente se había omitido, y el backend lo exige.
Lot _lot() => Lot(
  id: 1,
  blockNumber: 'M-Ñ',
  lotNumber: '272',
  area: 200,
  pricePerSquareMeter: 3000,
  status: 'disponible',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Client _client() => Client(
  id: 1,
  fullName: 'HECTOR JULIO DEL CARMEN HENRIQUEZ',
  documentId: '028-00367696',
  phone: '8292714965',
  address: 'Calle 1',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('buildLotAdminFields', () {
    test('el campo price lleva PRECIO POR M2, nunca el total', () {
      final lot = _lot();
      final fields = buildLotAdminFields(lot, 'update_details');
      final price = fields.firstWhere((field) => field.key == 'price');

      expect(lot.totalPrice, 600000);
      expect(
        price.initial,
        '3000.00',
        reason: 'Debe enviarse el unitario (m²), no el total (600000).',
      );
      expect(price.initial, isNot('600000.00'));
      expect(price.label.toLowerCase(), contains('metro'));
      expect(price.numeric, isTrue);
    });

    test('update_details incluye manzana, solar y area', () {
      final keys = buildLotAdminFields(
        _lot(),
        'update_details',
      ).map((field) => field.key).toList();
      expect(keys, containsAll(<String>['block', 'number', 'area', 'price']));
    });

    test('update_status solo ofrece los estados manuales canonicos', () {
      final fields = buildLotAdminFields(_lot(), 'update_status');
      expect(fields, hasLength(1));
      expect(fields.single.key, 'status');
      expect(fields.single.label, contains('disponible'));
      expect(fields.single.label, contains('reservado'));
      expect(fields.single.label, contains('bloqueado'));
      expect(fields.single.label, contains('mantenimiento'));
      // 'vendido' lo determina la venta: no debe ofrecerse a mano.
      expect(fields.single.label, isNot(contains('vendido')));
    });

    test('acciones no editables no generan campos', () {
      expect(buildLotAdminFields(_lot(), 'audit'), isEmpty);
      expect(buildLotAdminFields(_lot(), 'deactivate'), isEmpty);
      expect(buildLotAdminFields(_lot(), 'reactivate'), isEmpty);
    });

    test('el resumen muestra unitario y total para evitar confusion', () {
      final summary = buildLotAdminSummary(_lot());
      expect(summary.any((line) => line.contains('Precio por m²')), isTrue);
      expect(summary.any((line) => line.contains('Precio total')), isTrue);
      expect(summary.any((line) => line.contains('MÑ-S272')), isTrue);
    });
  });

  group('buildClientIdentityFields', () {
    test('incluye name (obligatorio en backend) con el nombre actual', () {
      final fields = buildClientIdentityFields(_client());
      final name = fields.firstWhere((field) => field.key == 'name');

      expect(name.initial, 'HECTOR JULIO DEL CARMEN HENRIQUEZ');
      expect(name.label, 'Nombre');
    });

    test('incluye documento, telefono y direccion', () {
      final keys = buildClientIdentityFields(
        _client(),
      ).map((field) => field.key).toList();
      expect(keys, <String>['name', 'document', 'phone', 'address']);
    });

    test('tolera telefono y direccion nulos', () {
      final client = Client(
        id: 2,
        fullName: 'ANA PEREZ',
        documentId: '001-0000000-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final fields = buildClientIdentityFields(client);
      expect(
        fields.firstWhere((field) => field.key == 'phone').initial,
        isEmpty,
      );
      expect(
        fields.firstWhere((field) => field.key == 'address').initial,
        isEmpty,
      );
    });
  });
}
