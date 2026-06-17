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
      'sistema_solares_partial_initial_',
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

  test(
    'acepta venta con inicial parcial cuando hay fecha limite del completivo',
    () async {
      final saleDate = DateTime(2026, 5, 6);
      final deadline = saleDate.add(const Duration(days: 25));

      await clientRepository.save(
        Client(
          fullName: 'Cliente Apartado',
          documentId: '001-1111111-1',
          phone: '8090000000',
          createdAt: saleDate,
          updatedAt: saleDate,
        ),
      );
      await lotRepository.save(
        Lot(
          blockNumber: 'A',
          lotNumber: '01',
          area: 200,
          price: 100000,
          status: 'disponible',
          createdAt: saleDate,
          updatedAt: saleDate,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: saleDate,
          salePrice: 100000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 10000,
          initialPaymentPaid: 3000,
          initialPaymentDeadline: deadline,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      expect(saleId, greaterThan(0));

      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
      );
      expect(rows, hasLength(1));
      final row = rows.single;

      expect(row['estado'], 'inicial_incompleto');
      expect((row['monto_inicial_requerido'] as num).toDouble(), 10000);
      expect((row['monto_inicial_pagado'] as num).toDouble(), 3000);
      expect((row['monto_inicial_pendiente'] as num).toDouble(), 7000);
      expect(row['fecha_limite_inicial'], deadline.toIso8601String());
    },
  );

  test(
    'rechaza venta con inicial parcial sin fecha limite del completivo',
    () async {
      final saleDate = DateTime(2026, 5, 6);

      await clientRepository.save(
        Client(
          fullName: 'Cliente Sin Plazo',
          documentId: '001-2222222-2',
          createdAt: saleDate,
          updatedAt: saleDate,
        ),
      );
      await lotRepository.save(
        Lot(
          blockNumber: 'B',
          lotNumber: '02',
          area: 200,
          price: 100000,
          status: 'disponible',
          createdAt: saleDate,
          updatedAt: saleDate,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;

      await expectLater(
        salesRepository.createSale(
          SaleDraft(
            clientId: client.id!,
            lotId: lot.id!,
            userId: 1,
            saleDate: saleDate,
            salePrice: 100000,
            downPaymentPercentage: 10,
            requiredInitialPayment: 10000,
            initialPaymentPaid: 3000,
            initialPaymentDeadline: null,
            monthlyInterest: 1,
            installmentCount: 12,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
