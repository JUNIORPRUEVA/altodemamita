import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ClientRepository clientRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'clients_delete_ack_tombstone_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    clientRepository = ClientRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'clients_delete_ack_keeps_tombstone_when_referenced_by_sale_test',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 5, 5, 9, 0).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-sync-delete-ref-1',
        'version': 2,
        'nombre': 'Cliente Referenciado',
        'cedula': '001-0000999-1',
        'telefono': '8095559991',
        'direccion': 'Calle Referencia',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': now,
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
      });

      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'lot-sync-delete-ref-1',
        'version': 1,
        'manzana_numero': 'Z',
        'solar_numero': '01',
        'metros_cuadrados': 150,
        'precio_por_metro': 2500,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-sync-delete-ref-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': now,
        'precio_venta': 375000,
        'inicial_porcentaje': 10,
        'inicial_monto': 37500,
        'monto_inicial_requerido': 37500,
        'monto_inicial_pagado': 37500,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': now,
        'saldo_financiado': 337500,
        'saldo_pendiente': 337500,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await clientRepository.markAsSynced(['client-sync-delete-ref-1']);

      final rows = await db.query(
        DatabaseSchema.clientsTable,
        where: 'sync_id = ?',
        whereArgs: ['client-sync-delete-ref-1'],
        limit: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], isNotNull);
      expect(rows.single['sync_status'], DatabaseSchema.syncStatusSynced);
    },
  );
}
