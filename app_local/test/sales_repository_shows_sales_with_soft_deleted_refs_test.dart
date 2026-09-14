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

  test(
    'fetchAll agrega cuotas vencidas sin contar futuras, pagadas, ajustadas ni canceladas',
    () async {
      final db = await appDatabase.database;
      final now = DateTime(2026, 3, 6, 9, 0).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-pending-installments-1',
        'version': 1,
        'nombre': 'THELEMARQUE WISMIQUE',
        'cedula': '001-0000117-1',
        'telefono': '8095550117',
        'direccion': 'Calle Principal',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'product-pending-installments-1',
        'version': 1,
        'manzana_numero': 'M-B-1',
        'solar_numero': '446',
        'metros_cuadrados': 250,
        'precio_por_metro': 3000,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-pending-installments-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': now,
        'precio_venta': 750000,
        'inicial_porcentaje': 10,
        'inicial_monto': 75000,
        'monto_inicial_requerido': 75000,
        'monto_inicial_pagado': 75000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'monto_apartado_pagado': 0,
        'fecha_limite_inicial': null,
        'fecha_activacion': now,
        'saldo_financiado': 675000,
        'saldo_pendiente': 675000,
        'interes_mensual': 1,
        'cantidad_cuotas': 120,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await _insertInstallment(
        appDatabase: appDatabase,
        saleId: saleId,
        number: 1,
        dueDate: DateTime(2026, 9, 12),
        now: now,
        status: 'pendiente',
        totalAmount: 1000,
        paidAmount: 0,
      );
      await _insertInstallment(
        appDatabase: appDatabase,
        saleId: saleId,
        number: 2,
        dueDate: DateTime(2026, 9, 13),
        now: now,
        status: 'parcial',
        totalAmount: 1000,
        paidAmount: 250,
      );
      await _insertInstallment(
        appDatabase: appDatabase,
        saleId: saleId,
        number: 3,
        dueDate: DateTime(2026, 10, 13),
        now: now,
        status: 'pendiente',
        totalAmount: 1000,
        paidAmount: 0,
      );
      await _insertInstallment(
        appDatabase: appDatabase,
        saleId: saleId,
        number: 4,
        dueDate: DateTime(2026, 9, 11),
        now: now,
        status: 'pagada',
        totalAmount: 1000,
        paidAmount: 1000,
      );
      await _insertInstallment(
        appDatabase: appDatabase,
        saleId: saleId,
        number: 5,
        dueDate: DateTime(2026, 9, 11),
        now: now,
        status: 'ajustada',
        totalAmount: 0,
        paidAmount: 0,
      );
      await _insertInstallment(
        appDatabase: appDatabase,
        saleId: saleId,
        number: 6,
        dueDate: DateTime(2026, 9, 11),
        now: now,
        status: 'cancelada',
        totalAmount: 1000,
        paidAmount: 0,
      );

      final summaries = await repository.fetchAll();

      expect(summaries, hasLength(1));
      expect(summaries.single.overdueInstallmentCount, 2);
      expect(summaries.single.overdueInstallmentsLabel, '2 cuotas vencidas');
    },
  );
}

Future<void> _insertInstallment({
  required AppDatabase appDatabase,
  required int saleId,
  required int number,
  required DateTime dueDate,
  required String now,
  required String status,
  required double totalAmount,
  required double paidAmount,
}) async {
  final db = await appDatabase.database;
  await db.insert(DatabaseSchema.installmentsTable, {
    'sync_id': 'installment-$saleId-$number',
    'version': 1,
    'venta_id': saleId,
    'numero_cuota': number,
    'fecha_vencimiento': dueDate.toIso8601String(),
    'saldo_inicial': 0,
    'capital_cuota': totalAmount,
    'interes_cuota': 0,
    'monto_cuota': totalAmount,
    'monto_pagado': paidAmount,
    'capital_pagado': paidAmount,
    'interes_pagado': 0,
    'saldo_final': 0,
    'estado': status,
    'fecha_creacion': now,
    'fecha_actualizacion': now,
    'deleted_at': null,
    'sync_status': DatabaseSchema.syncStatusSynced,
  });
}
