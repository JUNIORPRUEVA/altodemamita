import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late InstallmentsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'installments_conflict_merge_prefers_server_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = InstallmentsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'mergeRemoteRecords aplica el record remoto cuando la cuota local esta en conflict',
    () async {
      final db = await appDatabase.database;
      final createdAt = DateTime(2026, 5, 5, 10, 0).toIso8601String();
      final localUpdatedAt = DateTime(2026, 5, 5, 10, 1).toIso8601String();
      final remoteUpdatedAt = DateTime(2026, 5, 5, 10, 2).toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-installment-conflict-1',
        'version': 1,
        'nombre': 'Cliente Cuota Conflicto',
        'cedula': '001-0000777-1',
        'telefono': '8095557771',
        'direccion': 'Calle Conflicto',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'lot-installment-conflict-1',
        'version': 1,
        'manzana_numero': 'D',
        'solar_numero': '12',
        'metros_cuadrados': 140,
        'precio_por_metro': 3000,
        'estado': 'vendido',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-installment-conflict-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'vendedor_id': null,
        'fecha_venta': createdAt,
        'precio_venta': 420000,
        'inicial_porcentaje': 10,
        'inicial_monto': 42000,
        'monto_inicial_requerido': 42000,
        'monto_inicial_pagado': 42000,
        'monto_inicial_pendiente': 0,
        'monto_apartado_minimo': null,
        'fecha_limite_inicial': null,
        'fecha_activacion': createdAt,
        'saldo_financiado': 378000,
        'saldo_pendiente': 378000,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      await db.insert(DatabaseSchema.installmentsTable, {
        'sync_id': 'installment-conflict-1',
        'id_remote': 'remote-installment-conflict-1',
        'version': 5,
        'venta_id': saleId,
        'numero_cuota': 1,
        'fecha_vencimiento': createdAt,
        'saldo_inicial': 35000,
        'capital_cuota': 30000,
        'interes_cuota': 5000,
        'monto_cuota': 35000,
        'monto_pagado': 0,
        'capital_pagado': 0,
        'interes_pagado': 0,
        'saldo_final': 385000,
        'estado': 'pendiente',
        'fecha_creacion': createdAt,
        'fecha_actualizacion': localUpdatedAt,
        'last_modified_local': localUpdatedAt,
        'last_modified_remote': createdAt,
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusConflict,
      });

      await repository.mergeRemoteRecords([
        {
          'id': 'remote-installment-conflict-1',
          'sync_id': 'installment-conflict-1',
          'sale_sync_id': 'sale-installment-conflict-1',
          'version': 6,
          'installment_number': 1,
          'due_date': createdAt,
          'opening_balance': 35000,
          'principal_amount': 31000,
          'interest_amount': 4000,
          'total_amount': 35000,
          'paid_amount': 1000,
          'paid_principal_amount': 1000,
          'paid_interest_amount': 0,
          'ending_balance': 384000,
          'status': 'vencida',
          'created_at': createdAt,
          'updated_at': remoteUpdatedAt,
          'deleted_at': null,
        },
      ]);

      final rows = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'sync_id = ?',
        whereArgs: ['installment-conflict-1'],
        limit: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.single['version'], 6);
      expect(rows.single['monto_pagado'], 1000);
      expect(rows.single['estado'], 'vencida');
      expect(rows.single['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(rows.single['last_modified_remote'], remoteUpdatedAt);
    },
  );
}