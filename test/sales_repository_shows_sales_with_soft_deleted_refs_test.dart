import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SalesRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sales_repository_shows_sales_with_soft_deleted_refs_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = SalesRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'fetchAll y fetchDetail conservan ventas activas aunque cliente o solar tengan deleted_at local',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 5, 5, 9, 0).toIso8601String();
      final deletedAt = DateTime(2026, 5, 5, 10, 0).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-soft-deleted-ref-1',
        'version': 10,
        'nombre': 'Cliente Historico',
        'cedula': '001-0000888-1',
        'telefono': '8095558881',
        'direccion': 'Calle Historica',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': deletedAt,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-soft-deleted-ref-1',
        'version': 10,
        'manzana_numero': 'H',
        'solar_numero': '07',
        'metros_cuadrados': 170,
        'precio_por_metro': 2800,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': deletedAt,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-with-soft-deleted-refs-1',
        'version': 25,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': now,
        'precio_venta': 476000,
        'inicial_porcentaje': 10,
        'inicial_monto': 47600,
        'monto_inicial_requerido': 47600,
        'monto_inicial_pagado': 47600,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': now,
        'saldo_financiado': 428400,
        'saldo_pendiente': 428400,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final summaries = await repository.fetchAll();
      final detail = await repository.fetchDetail(saleId);

      expect(summaries, hasLength(1));
      expect(summaries.single.id, saleId);
      expect(summaries.single.clientName, 'Cliente Historico');
      expect(summaries.single.lotDisplayCode, 'MH-S07');
      expect(detail, isNotNull);
      expect(detail!.clientName, 'Cliente Historico');
      expect(detail.lotDisplayCode, 'MH-S07');
    },
  );
}