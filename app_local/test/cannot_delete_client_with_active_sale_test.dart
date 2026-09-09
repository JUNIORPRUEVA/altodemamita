import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/errors/active_sales_block_delete_exception.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late ClientRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'cannot_delete_client_active_sale_',
    );
    appDatabase = AppDatabase.test(path.join(tempDir.path, 'test.db'));
    await appDatabase.initialize();
    repository = ClientRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('cannot_delete_client_with_active_sale_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-active-1',
      'cedula': '00100000001',
      'nombre': 'Juan Perez',
      'telefono': '8091234567',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-active-1',
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 200.0,
      'precio_por_metro': 3500.0,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final userId = await db.rawQuery(
      'SELECT id FROM ${DatabaseSchema.usersTable} LIMIT 1',
    );
    final uid = userId.first['id'] as int;

    await db.insert(DatabaseSchema.salesTable, {
      'sync_id': 'sale-block-client-1',
      'version': 1,
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': uid,
      'vendedor_id': null,
      'fecha_venta': now,
      'precio_venta': 700000.0,
      'inicial_porcentaje': 10.0,
      'inicial_monto': 70000.0,
      'monto_inicial_requerido': 70000.0,
      'monto_inicial_pagado': 70000.0,
      'monto_inicial_pendiente': 0.0,
      'saldo_financiado': 630000.0,
      'saldo_pendiente': 630000.0,
      'interes_mensual': 1.0,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    expect(
      () => repository.delete(clientId),
      throwsA(isA<ActiveSalesBlockDeleteException>()),
    );
  });

  test('can_delete_client_without_active_sale_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-no-sale-1',
      'cedula': '00100000002',
      'nombre': 'Maria Lopez',
      'telefono': '8097654321',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    // No sales created → should delete without error.
    await expectLater(repository.delete(clientId), completes);

    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'id = ?',
      whereArgs: [clientId],
    );
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['cedula'], '__DELETED__$clientId');
  });

  test(
    'blocks_duplicate_active_client_document_and_allows_recreate_after_delete',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.now();
      final document = '00100000999';

      final firstId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-dup-1',
        'cedula': document,
        'nombre': 'Cliente Uno',
        'telefono': '8090000001',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await expectLater(
        repository.save(
          Client(
            fullName: 'Cliente Dos',
            documentId: document,
            phone: '8090000002',
            address: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cliente activo con esta cédula'),
          ),
        ),
      );

      await repository.delete(firstId);

      await expectLater(
        repository.save(
          Client(
            fullName: 'Cliente Recreado',
            documentId: document,
            phone: '8090000003',
            address: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        completes,
      );

      final activeRows = await db.query(
        DatabaseSchema.clientsTable,
        where: 'TRIM(cedula) = ? AND deleted_at IS NULL',
        whereArgs: [document],
      );
      expect(activeRows.length, 1);
    },
  );

  test(
    'active_pending_client_is_listed_and_deleted_client_does_not_block',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.now();
      final deletedAt = now.subtract(const Duration(days: 1)).toIso8601String();

      await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-yosayra-deleted',
        'cedula': '__DELETED__37',
        'nombre': 'YOSAYRA FELIX',
        'telefono': '(829) 554-4479',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': deletedAt,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final activeId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-yosaira-active',
        'cedula': '02800984631',
        'nombre': 'YOSAIRA FELIX',
        'telefono': '8295544479',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPendingCreate,
      });

      final allClients = await repository.fetchAll();
      expect(allClients.map((client) => client.id), contains(activeId));
      expect(
        allClients.any((client) => client.fullName == 'YOSAYRA FELIX'),
        isFalse,
      );

      final byPlainPhone = await repository.fetchAll(query: '8295544479');
      expect(byPlainPhone.map((client) => client.id), contains(activeId));
      expect(
        byPlainPhone.any((client) => client.fullName == 'YOSAYRA FELIX'),
        isFalse,
      );

      final byFormattedPhone = await repository.fetchAll(
        query: '(829) 554-4479',
      );
      expect(byFormattedPhone.map((client) => client.id), contains(activeId));
      expect(
        byFormattedPhone.any((client) => client.fullName == 'YOSAYRA FELIX'),
        isFalse,
      );

      await expectLater(
        repository.save(
          Client(
            fullName: 'Cliente Telefono Duplicado',
            documentId: '02800984632',
            phone: '(829) 554-4479',
            address: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cliente activo con este teléfono'),
          ),
        ),
      );

      await db.update(
        DatabaseSchema.clientsTable,
        {
          'deleted_at': now.toIso8601String(),
          'sync_status': DatabaseSchema.syncStatusPendingDelete,
        },
        where: 'id = ?',
        whereArgs: [activeId],
      );

      await expectLater(
        repository.save(
          Client(
            fullName: 'Nuevo Cliente Mismo Telefono',
            documentId: '02800984632',
            phone: '(829) 554-4479',
            address: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        completes,
      );
    },
  );

  test('client_phone_search_accepts_letters_and_free_text', () async {
    final db = await appDatabase.database;
    final now = DateTime.now();

    final alphaPhoneId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-phone-alpha',
      'cedula': '02800984633',
      'nombre': 'Cliente Alfanumerico',
      'telefono': '829ABC4479',
      'direccion': 'Oficina Principal',
      'fecha_creacion': now.toIso8601String(),
      'fecha_actualizacion': now.toIso8601String(),
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    final extPhoneId = await db.insert(DatabaseSchema.clientsTable, {
      'sync_id': 'client-phone-ext',
      'cedula': '02800984634',
      'nombre': 'Cliente Extension',
      'telefono': 'Ext. 23',
      'direccion': 'Oficina 2',
      'fecha_creacion': now.toIso8601String(),
      'fecha_actualizacion': now.toIso8601String(),
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPendingCreate,
    });

    final byLetters = await repository.fetchAll(query: 'ABC');
    expect(byLetters.map((client) => client.id), contains(alphaPhoneId));

    final byExtension = await repository.fetchAll(query: 'Ext');
    expect(byExtension.map((client) => client.id), contains(extPhoneId));

    final byNormalizedExtension = await repository.fetchAll(query: 'Ext23');
    expect(
      byNormalizedExtension.map((client) => client.id),
      contains(extPhoneId),
    );

    final byAddress = await repository.fetchAll(query: 'Oficina 2');
    expect(byAddress.map((client) => client.id), contains(extPhoneId));

    await repository.save(
      Client(
        fullName: 'Cliente Texto Libre',
        documentId: '02800984635',
        phone: ' Oficina 99 ',
        address: null,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final freeTextRows = await db.query(
      DatabaseSchema.clientsTable,
      columns: ['telefono'],
      where: 'cedula = ? AND deleted_at IS NULL',
      whereArgs: ['02800984635'],
      limit: 1,
    );
    expect(freeTextRows.single['telefono'], ' Oficina 99 ');
  });
}
