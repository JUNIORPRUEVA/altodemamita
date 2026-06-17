import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ClientRepository clientRepository;
  late LotRepository lotRepository;
  late SalesRepository salesRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_apartado_split_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    clientRepository = ClientRepository(appDatabase: appDatabase);
    lotRepository = LotRepository(appDatabase: appDatabase);
    salesRepository = SalesRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<int> _seedSaleAsApartado({
    required DateTime saleDate,
    required double apartadoAmount,
    required DateTime? deadline,
  }) async {
    await clientRepository.save(
      Client(
        fullName: 'Cliente Apartado Split',
        documentId: '001-3333333-3',
        phone: '8090000000',
        createdAt: saleDate,
        updatedAt: saleDate,
      ),
    );
    await lotRepository.save(
      Lot(
        blockNumber: 'C',
        lotNumber: '03',
        area: 200,
        price: 100000,
        status: 'disponible',
        createdAt: saleDate,
        updatedAt: saleDate,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final lot = (await lotRepository.fetchAll()).single;

    return salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: lot.id!,
        userId: 1,
        saleDate: saleDate,
        salePrice: 100000,
        downPaymentPercentage: 10,
        requiredInitialPayment: 10000,
        initialPaymentPaid: apartadoAmount,
        initialPaymentDeadline: deadline,
        initialIsApartado: true,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );
  }

  test(
    'apartado no se acredita al inicial: monto_inicial_pagado=0 y monto_apartado_pagado=apartado',
    () async {
      final saleDate = DateTime(2026, 5, 6);
      final deadline = saleDate.add(const Duration(days: 25));

      final saleId = await _seedSaleAsApartado(
        saleDate: saleDate,
        apartadoAmount: 10000,
        deadline: deadline,
      );

      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
      );
      expect(rows, hasLength(1));
      final row = rows.single;

      // El inicial sigue pendiente al 100%.
      expect((row['monto_inicial_requerido'] as num).toDouble(), 10000);
      expect((row['monto_inicial_pagado'] as num).toDouble(), 0);
      expect((row['monto_inicial_pendiente'] as num).toDouble(), 10000);
      // El monto entregado quedo registrado como apartado.
      expect((row['monto_apartado_pagado'] as num).toDouble(), 10000);
      // La venta NO se activo.
      expect(row['estado'], isNot('activa'));
      expect(row['estado'], anyOf('apartado', 'inicial_incompleto'));

      // Y no se generaron cuotas.
      final cuotas = await db.query(
        DatabaseSchema.installmentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
      );
      expect(cuotas, isEmpty);

      // El pago registrado al crear la venta esta marcado como apartado.
      final pagos = await db.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
      );
      expect(pagos, hasLength(1));
      expect(pagos.single['tipo_pago'], 'apartado');
      expect((pagos.single['monto_pagado'] as num).toDouble(), 10000);
    },
  );
}
