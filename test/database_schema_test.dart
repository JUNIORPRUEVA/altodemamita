import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/data/receipt_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/payments/presentation/receipt/receipt_pdf_builder.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/features/settings/data/company_repository.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';
import 'package:sistema_solares/features/settings/data/printer_repository.dart';
import 'package:sistema_solares/features/settings/domain/printer_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ClientRepository clientRepository;
  late LotRepository lotRepository;
  late SalesRepository salesRepository;
  late SellerRepository sellerRepository;
  late PaymentsRepository paymentsRepository;
  late ReceiptRepository receiptRepository;
  late PrinterRepository printerRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    clientRepository = ClientRepository(appDatabase: appDatabase);
    lotRepository = LotRepository(appDatabase: appDatabase);
    salesRepository = SalesRepository(appDatabase: appDatabase);
    sellerRepository = SellerRepository(database: appDatabase);
    paymentsRepository = PaymentsRepository(appDatabase: appDatabase);
    receiptRepository = ReceiptRepository(
      appDatabase: appDatabase,
      paymentsRepository: paymentsRepository,
    );
    printerRepository = PrinterRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('crea tablas principales y mantiene relaciones validas', () async {
    final db = await appDatabase.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    expect(
      tableNames,
      containsAll({
        DatabaseSchema.clientsTable,
        DatabaseSchema.usersTable,
        DatabaseSchema.lotsTable,
        DatabaseSchema.salesTable,
        DatabaseSchema.installmentsTable,
        DatabaseSchema.paymentsTable,
        DatabaseSchema.settingsTable,
      }),
    );

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'nombre': 'Maria Gomez',
      'cedula': '001-0000000-1',
      'telefono': '8095550101',
      'direccion': 'Calle Central',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'manzana_numero': 'A',
      'solar_numero': '12',
      'metros_cuadrados': 180.5,
      'precio_por_metro': 850000 / 180.5,
      'estado': 'disponible',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    });

    final saleId = await db.insert(DatabaseSchema.salesTable, {
      'cliente_id': clientId,
      'solar_id': lotId,
      'usuario_id': 1,
      'fecha_venta': DateTime.now().toIso8601String(),
      'precio_venta': 850000,
      'inicial_porcentaje': 20,
      'inicial_monto': 170000,
      'saldo_financiado': 680000,
      'saldo_pendiente': 680000,
      'interes_mensual': 2,
      'cantidad_cuotas': 12,
      'estado': 'activa',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    });

    final installmentId = await db.insert(DatabaseSchema.installmentsTable, {
      'venta_id': saleId,
      'numero_cuota': 1,
      'fecha_vencimiento': DateTime.now().toIso8601String(),
      'saldo_inicial': 680000,
      'capital_cuota': 50000,
      'interes_cuota': 13600,
      'monto_cuota': 63600,
      'saldo_final': 630000,
      'estado': 'pendiente',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    });

    final paymentId = await db.insert(DatabaseSchema.paymentsTable, {
      'venta_id': saleId,
      'cliente_id': clientId,
      'cuota_id': installmentId,
      'fecha_pago': DateTime.now().toIso8601String(),
      'monto_pagado': 63600,
      'metodo_pago': 'efectivo',
      'tipo_pago': 'cuota',
      'referencia': 'REC-001',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    });

    expect(saleId, greaterThan(0));
    expect(installmentId, greaterThan(0));
    expect(paymentId, greaterThan(0));

    expect(
      () => db.insert(DatabaseSchema.salesTable, {
        'cliente_id': 999999,
        'solar_id': lotId,
        'usuario_id': 1,
        'fecha_venta': DateTime.now().toIso8601String(),
        'precio_venta': 100,
        'inicial_porcentaje': 0,
        'inicial_monto': 0,
        'saldo_financiado': 100,
        'saldo_pendiente': 100,
        'interes_mensual': 0,
        'cantidad_cuotas': 1,
        'estado': 'activa',
        'fecha_creacion': DateTime.now().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('guarda impresora predeterminada y la mantiene persistente', () async {
    final firstPrinter = await printerRepository.createPrinter(
      PrinterConfig.empty().copyWith(
        nombre: 'Caja principal',
        modelo: 'EPSON TM-T20',
        tipo: 'térmica',
        configuracionJson:
            '{"url":"printer://epson-main","name":"Caja principal"}',
      ),
    );

    final secondPrinter = await printerRepository.createPrinter(
      PrinterConfig.empty().copyWith(
        nombre: 'Oficina',
        modelo: 'HP LaserJet',
        tipo: 'laser',
        esPredeterminada: true,
        configuracionJson: '{"url":"printer://office","name":"Oficina"}',
      ),
    );

    await printerRepository.updatePrinter(
      secondPrinter.copyWith(esPredeterminada: true),
    );

    final storedPrinters = await printerRepository.getAllPrinters();
    final defaultPrinter = await printerRepository.getDefaultPrinter();

    expect(storedPrinters, hasLength(2));
    expect(defaultPrinter?.nombre, 'Oficina');
    expect(defaultPrinter?.printerUrl, 'printer://office');
    expect(
      storedPrinters.where((printer) => printer.esPredeterminada),
      hasLength(1),
    );
    expect(firstPrinter.id, isNotNull);
  });

  test('al eliminar la predeterminada promueve otra impresora', () async {
    final firstPrinter = await printerRepository.createPrinter(
      PrinterConfig.empty().copyWith(
        nombre: 'Caja 1',
        modelo: 'EPSON 1',
        tipo: 'térmica',
      ),
    );
    final secondPrinter = await printerRepository.createPrinter(
      PrinterConfig.empty().copyWith(
        nombre: 'Caja 2',
        modelo: 'EPSON 2',
        tipo: 'térmica',
      ),
    );

    await printerRepository.setDefaultPrinter(secondPrinter.id!);
    await printerRepository.deletePrinter(secondPrinter.id!);

    final defaultPrinter = await printerRepository.getDefaultPrinter();
    expect(defaultPrinter?.id, firstPrinter.id);
  });

  test('crud basico de clientes funciona sin errores', () async {
    final now = DateTime.now();

    await clientRepository.save(
      Client(
        fullName: 'Ana Perez',
        documentId: '001-0000000-2',
        phone: '8095550102',
        address: 'Las Flores',
        createdAt: now,
        updatedAt: now,
      ),
    );

    var clients = await clientRepository.fetchAll();
    expect(clients, hasLength(1));
    expect(clients.single.fullName, 'Ana Perez');

    final updatedClient = clients.single.copyWith(phone: '8295550102');
    await clientRepository.save(updatedClient);

    clients = await clientRepository.fetchAll(query: '8295550102');
    expect(clients, hasLength(1));
    expect(clients.single.phone, '8295550102');

    await clientRepository.delete(clients.single.id!);
    expect(await clientRepository.fetchAll(), isEmpty);
  });

  test('los datos persisten al cerrar y reabrir la base local', () async {
    final now = DateTime.now();

    await clientRepository.save(
      Client(
        fullName: 'Persistencia Real',
        documentId: '001-0000000-9',
        phone: '8095550999',
        address: 'Ruta estable',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await appDatabase.close();
    await appDatabase.initialize();

    final reopenedRepository = ClientRepository(appDatabase: appDatabase);
    final clients = await reopenedRepository.fetchAll(query: 'Persistencia');

    expect(clients, hasLength(1));
    expect(clients.single.documentId, '001-0000000-9');
  });

  test('crud basico de solares funciona sin errores', () async {
    final now = DateTime.now();

    await lotRepository.save(
      Lot(
        blockNumber: 'B',
        lotNumber: '07',
        area: 210,
        pricePerSquareMeter: 920000 / 210,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    var lots = await lotRepository.fetchAll();
    expect(lots, hasLength(1));
    expect(lots.single.displayCode, 'MB-S07');
    expect(lots.single.totalPrice, closeTo(920000, 0.01));

    final updatedLot = lots.single.copyWith(status: 'reservado');
    await lotRepository.save(updatedLot);

    lots = await lotRepository.fetchAll(query: 'reservado');
    expect(lots, hasLength(1));
    expect(lots.single.status, 'reservado');

    await lotRepository.delete(lots.single.id!);
    expect(await lotRepository.fetchAll(), isEmpty);
  });

  test(
    'rechaza ventas con inicial menor al minimo requerido',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Pedro Ramirez',
          documentId: '001-0000000-3',
          phone: '8095550110',
          address: 'Villa Esperanza',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'C',
          lotNumber: '15',
          area: 200,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
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
            saleDate: now,
            salePrice: 0,
            downPaymentPercentage: 10,
            requiredInitialPayment: 100000,
            initialPaymentPaid: 25000,
            minimumReserveAmount: 20000,
            initialPaymentDeadline: now.add(const Duration(days: 15)),
            monthlyInterest: 1,
            installmentCount: 12,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final detail = await salesRepository.fetchDetail(1);
      expect(detail, isNull);

      final saleLot = await lotRepository.findById(lot.id!);
      expect(saleLot, isNotNull);
      expect(saleLot!.status, 'disponible');

      final financedSaleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: 1000000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      expect(financedSaleId, greaterThan(0));

      await lotRepository.save(
        Lot(
          blockNumber: 'D',
          lotNumber: '09',
          area: 220,
          pricePerSquareMeter: 950000 / 220,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final allLots = await lotRepository.fetchAll();
      final secondLot = allLots.firstWhere(
        (item) => item.blockNumber == 'D' && item.lotNumber == '09',
      );
      final cashSaleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: secondLot.id!,
          userId: 1,
          saleDate: now,
          salePrice: secondLot.totalPrice,
          downPaymentPercentage: 100,
          requiredInitialPayment: secondLot.totalPrice,
          initialPaymentPaid: secondLot.totalPrice,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final cashSaleDetail = await salesRepository.fetchDetail(cashSaleId);
      expect(cashSaleDetail, isNotNull);
      expect(cashSaleDetail!.sale.status, 'pagada');
      expect(cashSaleDetail.sale.financedBalance, 0);
      expect(cashSaleDetail.sale.pendingBalance, 0);
      expect(cashSaleDetail.installments, isEmpty);
    },
  );

  test(
    'crear venta con inicial completo activa la venta y genera cuotas de inmediato',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Adriana Peguero',
          documentId: '001-0000000-7',
          phone: '8095550144',
          address: 'Autopista Duarte',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'G',
          lotNumber: '06',
          area: 180,
          price: 850000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 85000,
          initialPaymentPaid: 85000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.sale.status, 'activa');
      expect(detail.sale.paidInitialPayment, 85000);
      expect(detail.sale.pendingInitialPayment, 0);
      expect(detail.installments, hasLength(12));

      final lotAfterSale = await lotRepository.findById(lot.id!);
      expect(lotAfterSale, isNotNull);
      expect(lotAfterSale!.status, 'vendido');
    },
  );

  test(
    'crear venta con inicial mayor al minimo usa el inicial real y baja el financiamiento',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Laura Medina',
          documentId: '001-0000200-7',
          phone: '8095550207',
          address: 'Mirador Norte',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'P',
          lotNumber: '04',
          area: 150,
          price: 500000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 50000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.sale.status, 'activa');
      expect(detail.sale.downPaymentAmount, 100000);
      expect(detail.sale.requiredInitialPayment, 50000);
      expect(detail.sale.paidInitialPayment, 100000);
      expect(detail.sale.pendingInitialPayment, 0);
      expect(detail.sale.financedBalance, 400000);
      expect(detail.sale.pendingBalance, 400000);
      expect(detail.installments, hasLength(12));
      expect(detail.installments.first.openingBalance, 400000);
    },
  );

  test(
    'rechaza venta con inicial por encima del precio total',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Miguel Acosta',
          documentId: '001-0000201-5',
          phone: '8095550208',
          address: 'Ensanche Ozama',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'Q',
          lotNumber: '08',
          area: 180,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;
      await expectLater(
        () => salesRepository.createSale(
          SaleDraft(
            clientId: client.id!,
            lotId: lot.id!,
            userId: 1,
            saleDate: now,
            salePrice: lot.price,
            downPaymentPercentage: 10,
            requiredInitialPayment: 100000,
            initialPaymentPaid: 1000001,
            monthlyInterest: 1,
            installmentCount: 12,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'venta activa con inicial del 10% genera tabla coherente de cuota fija mensual',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Rosa Martinez',
          documentId: '001-0000000-9',
          phone: '8095550150',
          address: 'Los Proceres',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'G',
          lotNumber: '10',
          area: 200,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.sale.financedBalance, 900000);
      expect(detail.sale.pendingBalance, 900000);
      expect(detail.installments, hasLength(12));
      expect(detail.installments.first.openingBalance, 900000);

      final fixedInstallmentAmount = detail.installments.first.totalAmount;
      final principalSum = detail.installments.fold<double>(
        0,
        (sum, installment) => sum + installment.principalAmount,
      );

      for (var index = 0; index < detail.installments.length; index++) {
        final installment = detail.installments[index];
        expect(installment.totalAmount, fixedInstallmentAmount);
        if (index == 0) {
          continue;
        }

        final previousInstallment = detail.installments[index - 1];
        expect(installment.openingBalance, previousInstallment.endingBalance);
        expect(
          installment.interestAmount,
          lessThan(previousInstallment.interestAmount),
        );
        if (index < detail.installments.length - 1) {
          expect(
            installment.principalAmount,
            greaterThan(previousInstallment.principalAmount),
          );
        }
      }

      expect(principalSum, 900000);
      expect(detail.installments.last.endingBalance, 0);
    },
  );

  test('permite editar y eliminar una venta con solo pago inicial registrado', () async {
    final now = DateTime(2026, 3, 26);

    await clientRepository.save(
      Client(
        fullName: 'Elena Castro',
        documentId: '001-0000000-8',
        phone: '8095550180',
        address: 'Jardines del Este',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'H',
        lotNumber: '03',
        area: 190,
        price: 800000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'H',
        lotNumber: '04',
        area: 195,
        price: 950000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final lots = await lotRepository.fetchAll();
    final firstLot = lots.firstWhere((lot) => lot.lotNumber == '03');
    final secondLot = lots.firstWhere((lot) => lot.lotNumber == '04');

    final saleId = await salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: firstLot.id!,
        userId: 1,
        saleDate: now,
        salePrice: 810000,
        downPaymentPercentage: 10,
        requiredInitialPayment: 81000,
        initialPaymentPaid: 81000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    await salesRepository.updateSale(
      saleId,
      SaleDraft(
        clientId: client.id!,
        lotId: secondLot.id!,
        userId: 1,
        saleDate: now.add(const Duration(days: 1)),
        salePrice: 975000,
        downPaymentPercentage: 8,
        requiredInitialPayment: 78000,
        initialPaymentPaid: 81000,
        monthlyInterest: 2,
        installmentCount: 18,
      ),
    );

    final detail = await salesRepository.fetchDetail(saleId);
    expect(detail, isNotNull);
    expect(detail!.sale.lotId, secondLot.id);
    expect(detail.sale.salePrice, 975000);
    expect(detail.sale.downPaymentPercentage, 8);
    expect(detail.sale.status, 'activa');
    expect(detail.sale.installmentCount, 18);
    expect(detail.installments, hasLength(18));

    final releasedLot = await lotRepository.findById(firstLot.id!);
    final soldLot = await lotRepository.findById(secondLot.id!);
    expect(releasedLot!.status, 'disponible');
    expect(soldLot!.status, 'vendido');

    await salesRepository.deleteSale(saleId);

    expect(await salesRepository.fetchDetail(saleId), isNull);
    final restoredLot = await lotRepository.findById(secondLot.id!);
    expect(restoredLot!.status, 'disponible');
  });

  test('no permite editar una venta con pagos registrados', () async {
    final now = DateTime(2026, 3, 26);

    await clientRepository.save(
      Client(
        fullName: 'Rosa Martinez',
        documentId: '001-0000000-9',
        phone: '8095550190',
        address: 'Villa Progreso',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'J',
        lotNumber: '01',
        area: 170,
        price: 700000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final lot = (await lotRepository.fetchAll()).single;

    final saleId = await salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: lot.id!,
        userId: 1,
        saleDate: now,
        salePrice: lot.price,
        downPaymentPercentage: 10,
        requiredInitialPayment: 70000,
        initialPaymentPaid: 70000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    await paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: now.add(const Duration(days: 1)),
        amountPaid: 50000,
        paymentMethod: 'efectivo',
      ),
    );

    expect(
      () => salesRepository.updateSale(
        saleId,
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: 720000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 72000,
          initialPaymentPaid: 72000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'permite editar una venta con solo pagos iniciales y actualiza el metodo',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Ana de los Santos',
          documentId: '001-0000100-1',
          phone: '8095551112',
          address: 'Los Prados',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'M',
          lotNumber: '09',
          area: 205,
          price: 950000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).singleWhere(
        (item) => item.documentId == '001-0000100-1',
      );

      final lot = (await lotRepository.fetchAll()).singleWhere(
        (item) => item.lotNumber == '09',
      );

      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 95000,
          initialPaymentPaid: 95000,
          initialPaymentMethod: 'efectivo',
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      await salesRepository.updateSale(
        saleId,
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: 975000,
          downPaymentPercentage: 9,
          requiredInitialPayment: 87750,
          initialPaymentPaid: 95000,
          initialPaymentMethod: 'transferencia',
          monthlyInterest: 1.5,
          installmentCount: 18,
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.sale.salePrice, 975000);
      expect(detail.sale.downPaymentPercentage, 9);
      expect(detail.sale.installmentCount, 18);
      expect(detail.initialPaymentMethod, 'transferencia');

      final db = await appDatabase.database;
      final paymentRows = await db.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      );
      expect(paymentRows, hasLength(1));
      expect(paymentRows.single['tipo_pago'], 'abono_inicial');
      expect(paymentRows.single['metodo_pago'], 'transferencia');
    },
  );

  test(
    'pago antes del vencimiento mantiene la cuota fija y recalcula la tabla futura',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Luisa Ortega',
          documentId: '001-0000000-4',
          phone: '8095550120',
          address: 'Residencial Norte',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'E',
          lotNumber: '05',
          area: 180,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final beforePaymentDetail = await salesRepository.fetchDetail(saleId);
      final originalFirstInstallment = beforePaymentDetail!.installments.first;

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 3, 27),
          amountPaid: 50000,
          paymentMethod: 'transferencia',
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.sale.pendingBalance, 850000);
      expect(detail.installments.first.paidAmount, 0);
      expect(detail.installments.first.openingBalance, 850000);
      expect(
        detail.installments.first.totalAmount,
        originalFirstInstallment.totalAmount,
      );

      final recalculatedFixedAmount = detail.installments.first.totalAmount;
      for (var index = 0; index < detail.installments.length; index++) {
        final installment = detail.installments[index];
        if (index < detail.installments.length - 1) {
          expect(installment.totalAmount, recalculatedFixedAmount);
        } else {
          expect(
            installment.totalAmount,
            lessThanOrEqualTo(recalculatedFixedAmount),
          );
        }
        if (index == 0) {
          continue;
        }

        final previousInstallment = detail.installments[index - 1];
        expect(installment.openingBalance, previousInstallment.endingBalance);
        expect(
          installment.interestAmount,
          lessThan(previousInstallment.interestAmount),
        );
        if (index < detail.installments.length - 1) {
          expect(
            installment.principalAmount,
            greaterThan(previousInstallment.principalAmount),
          );
        }
      }
      expect(detail.installments.last.endingBalance, 0);

      final db = await appDatabase.database;
      final paymentRows = await db.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      );
      expect(paymentRows, hasLength(2));
      expect(paymentRows.first['tipo_pago'], 'abono_inicial');
      expect(paymentRows.last['tipo_pago'], 'abono_capital');
      expect(paymentRows.last['monto_pagado'], 50000.0);
    },
  );

  test(
    'pago en cuota vencida cubre cuota primero y excedente va a capital',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Carlos Mendez',
          documentId: '001-0000000-5',
          phone: '8095550130',
          address: 'Los Rios',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'F',
          lotNumber: '11',
          area: 210,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).single;
      final lot = (await lotRepository.fetchAll()).single;
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final beforePaymentDetail = await salesRepository.fetchDetail(saleId);
      final firstInstallment = beforePaymentDetail!.installments.first;
      final paymentAmount = _roundCurrency(
        firstInstallment.totalAmount + 10000,
      );

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: firstInstallment.dueDate,
          amountPaid: paymentAmount,
          paymentMethod: 'efectivo',
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.installments.first.status, 'pagada');
      expect(
        detail.installments.first.paidAmount,
        firstInstallment.totalAmount,
      );
      expect(
        detail.installments[1].totalAmount,
        firstInstallment.totalAmount,
      );
      expect(
        detail.sale.pendingBalance,
        _roundCurrency(900000 - firstInstallment.principalAmount - 10000),
      );

      final db = await appDatabase.database;
      final paymentRows = await db.query(
        DatabaseSchema.paymentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      );
      expect(paymentRows, hasLength(3));
      expect(paymentRows.first['tipo_pago'], 'abono_inicial');
      expect(paymentRows[1]['tipo_pago'], 'cuota');
      expect(paymentRows.last['tipo_pago'], 'abono_capital');
      expect(paymentRows.last['monto_pagado'], 10000.0);
      expect(paymentRows[1]['referencia'], isNotNull);
      expect(paymentRows[1]['referencia'], paymentRows.last['referencia']);
    },
  );

  test(
    'abono directo a capital suficiente reduce el plazo activo sin bajar la cuota',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Ana Capital',
          documentId: '001-0000001-8',
          phone: '8095550311',
          address: 'Villa Esperanza',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'Z',
          lotNumber: '01',
          area: 200,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).last;
      final lot = (await lotRepository.fetchAll()).last;
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final beforeDetail = await salesRepository.fetchDetail(saleId);
      final originalFixedAmount = beforeDetail!.installments.first.totalAmount;

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: DateTime(2026, 3, 27),
          amountPaid: 100000,
          paymentMethod: 'transferencia',
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.installments.length, lessThan(12));
      expect(detail.installments.first.totalAmount, originalFixedAmount);
      expect(detail.installments.first.openingBalance, 800000);
      expect(detail.sale.pendingBalance, 800000);
      expect(detail.installments.last.endingBalance, 0);
    },
  );

  test(
    'pago mixto con excedente alto a capital reduce el plazo futuro manteniendo la cuota',
    () async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Luis Mixto',
          documentId: '001-0000001-9',
          phone: '8095550312',
          address: 'Villa Aurora',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await lotRepository.save(
        Lot(
          blockNumber: 'Z',
          lotNumber: '02',
          area: 220,
          price: 1000000,
          status: 'disponible',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final client = (await clientRepository.fetchAll()).last;
      final lot = (await lotRepository.fetchAll()).last;
      final saleId = await salesRepository.createSale(
        SaleDraft(
          clientId: client.id!,
          lotId: lot.id!,
          userId: 1,
          saleDate: now,
          salePrice: lot.price,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final beforeDetail = await salesRepository.fetchDetail(saleId);
      final firstInstallment = beforeDetail!.installments.first;

      await paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: firstInstallment.dueDate,
          amountPaid: _roundCurrency(firstInstallment.totalAmount + 100000),
          paymentMethod: 'efectivo',
        ),
      );

      final detail = await salesRepository.fetchDetail(saleId);
      expect(detail, isNotNull);
      expect(detail!.installments.length, lessThan(12));
      expect(detail.installments.first.status, 'pagada');
      expect(detail.installments[1].totalAmount, firstInstallment.totalAmount);
      expect(detail.installments.last.endingBalance, 0);
    },
  );

  test('recibo agrupa una operacion mixta y genera pdf', () async {
    final now = DateTime(2026, 3, 26);

    await clientRepository.save(
      Client(
        fullName: 'Julia Rosario',
        documentId: '001-0000001-1',
        phone: '8095550200',
        address: 'Mirador Sur',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'K',
        lotNumber: '08',
        area: 215,
        price: 1000000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final lot = (await lotRepository.fetchAll()).single;
    final saleId = await salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: lot.id!,
        userId: 1,
        saleDate: now,
        salePrice: lot.price,
        downPaymentPercentage: 10,
        requiredInitialPayment: 100000,
        initialPaymentPaid: 100000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    final detail = await salesRepository.fetchDetail(saleId);
    final firstInstallment = detail!.installments.first;
    final mixedAmount = _roundCurrency(firstInstallment.totalAmount + 7500);

    await paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: firstInstallment.dueDate,
        amountPaid: mixedAmount,
        paymentMethod: 'efectivo',
      ),
    );

    final db = await appDatabase.database;
    final paymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );

    final firstPaymentId = paymentRows[1]['id'] as int;
    final receipt = await receiptRepository.fetchReceiptByPaymentId(
      firstPaymentId,
    );

    expect(receipt, isNotNull);
    expect(receipt!.payments, hasLength(2));
    expect(receipt.totalAmount, mixedAmount);
    expect(receipt.paymentConcept, contains('Cuota #1'));
    expect(receipt.paymentConcept, contains('Abono a capital'));

    final pdfBytes = await ReceiptPdfBuilder.build(receipt);
    expect(pdfBytes, isNotEmpty);
  });

  test('rechaza sobrepago y no deja movimientos parciales', () async {
    final now = DateTime(2026, 3, 26);

    await clientRepository.save(
      Client(
        fullName: 'Mario Feliz',
        documentId: '001-0000001-2',
        phone: '8095550210',
        address: 'Villa Aura',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'L',
        lotNumber: '02',
        area: 180,
        price: 500000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final lot = (await lotRepository.fetchAll()).single;
    final saleId = await salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: lot.id!,
        userId: 1,
        saleDate: now,
        salePrice: lot.price,
        downPaymentPercentage: 10,
        requiredInitialPayment: 50000,
        initialPaymentPaid: 50000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    await expectLater(
      () => paymentsRepository.registerPayment(
        PaymentDraft(
          saleId: saleId,
          paymentDate: now,
          amountPaid: 1000000,
          paymentMethod: 'efectivo',
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final db = await appDatabase.database;
    final paymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
    );
    expect(paymentRows, hasLength(1));
    expect(paymentRows.single['tipo_pago'], 'abono_inicial');

    final detail = await salesRepository.fetchDetail(saleId);
    expect(detail, isNotNull);
    expect(detail!.sale.pendingBalance, 450000);
    expect(detail.installments.every((item) => item.paidAmount == 0), isTrue);
  });

  test('carga la informacion real de la empresa en el recibo de pago', () async {
    final now = DateTime(2026, 3, 28);
    final companyRepository = CompanyRepository(await appDatabase.database);
    final db = await appDatabase.database;

    await db.insert(DatabaseSchema.usersTable, {
      'nombre': 'Cajera de Prueba',
      'email': 'cajera.prueba@sistema.local',
      'password_hash': 'hash-temporal',
      'password_reset_required': 0,
      'rol': 'vendedor',
      'activo': 1,
      'telefono': '8095550404',
      'fecha_creacion': now.toIso8601String(),
      'fecha_actualizacion': now.toIso8601String(),
      'password_updated_at': now.toIso8601String(),
    });

    await companyRepository.saveCompanyInfo(
      CompanyInfo(
        nombre: 'Empresa Real RD',
        telefono: '809-555-0202',
        direccion: 'Autopista Duarte Km 10',
        logoBytesBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2foAAAAASUVORK5CYII=',
        fechaCreacion: now,
        fechaActualizacion: now,
      ),
    );

    await clientRepository.save(
      Client(
        fullName: 'Rosa Mendoza Garcia',
        documentId: '999-0000000006-6',
        phone: '8095550202',
        address: 'Santiago',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'TC',
        lotNumber: '11',
        area: 200,
        price: 500000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final sellerId = await sellerRepository.insert(
      Seller(
        name: 'Gloria Ortega',
        phone: '8095550303',
        documentId: '001-1111111-1',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final client = (await clientRepository.fetchAll()).single;
    final lot = (await lotRepository.fetchAll()).single;
    final saleId = await salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: lot.id!,
        userId: 1,
        sellerId: sellerId,
        saleDate: now,
        salePrice: lot.price,
        downPaymentPercentage: 10,
        requiredInitialPayment: 50000,
        initialPaymentPaid: 50000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    await paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        paymentDate: now,
        amountPaid: 1000,
        paymentMethod: 'efectivo',
        registeredByUserId: 2,
      ),
    );

    final paymentRows = await db.query(
      DatabaseSchema.paymentsTable,
      where: 'venta_id = ?',
      whereArgs: [saleId],
      orderBy: 'id DESC',
      limit: 1,
    );

    final receipt = await receiptRepository.fetchReceiptByPaymentId(
      paymentRows.single['id'] as int,
    );

    expect(receipt, isNotNull);
    expect(receipt!.company.nombre, 'Empresa Real RD');
    expect(paymentRows.single['usuario_id'], 2);
    expect(receipt.receivedBy, 'Cajera de Prueba');
    expect(receipt.company.telefono, '809-555-0202');
    expect(receipt.company.direccion, 'Autopista Duarte Km 10');
    expect(receipt.company.logoBytesBase64, isNotEmpty);
    expect(receipt.currentOutstandingBalance, closeTo(449000, 0.001));
    expect(receipt.remainingFinancedBalance, closeTo(449000, 0.001));
    expect(receipt.remainingInitialBalance, 0);
    expect(receipt.totalPaidAccumulated, closeTo(51000, 0.001));
    expect(receipt.installmentsPaid, 0);
    expect(receipt.installmentsRemaining, 12);
    expect(receipt.nextInstallmentNumber, 1);
    expect(receipt.nextInstallmentDueDate, isNotNull);
    expect(receipt.nextInstallmentAmount, greaterThan(0));
    expect(receipt.accountStatusLabel, 'Al dia');
  });

  test('lista solo las ventas asociadas al vendedor seleccionado', () async {
    final now = DateTime(2026, 3, 27);

    final sellerId = await sellerRepository.insert(
      Seller(
        name: 'Pedro Vendedor',
        phone: '8095550101',
        documentId: '001-1234567-8',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final otherSellerId = await sellerRepository.insert(
      Seller(
        name: 'Laura Vendedora',
        phone: '8295550102',
        documentId: '001-1234567-9',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await clientRepository.save(
      Client(
        fullName: 'Cliente Uno',
        documentId: '001-0000000-1',
        phone: '8095551111',
        address: 'Dirección 1',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await clientRepository.save(
      Client(
        fullName: 'Cliente Dos',
        documentId: '001-0000000-2',
        phone: '8095552222',
        address: 'Dirección 2',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await lotRepository.save(
      Lot(
        blockNumber: 'A',
        lotNumber: '10',
        area: 200,
        price: 500000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await lotRepository.save(
      Lot(
        blockNumber: 'B',
        lotNumber: '11',
        area: 220,
        price: 550000,
        status: 'disponible',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final clients = await clientRepository.fetchAll();
    final lots = await lotRepository.fetchAll();

    await salesRepository.createSale(
      SaleDraft(
        clientId: clients.first.id!,
        lotId: lots.first.id!,
        userId: 1,
        sellerId: sellerId,
        saleDate: now,
        salePrice: 500000,
        downPaymentPercentage: 10,
        requiredInitialPayment: 50000,
        initialPaymentPaid: 50000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    await salesRepository.createSale(
      SaleDraft(
        clientId: clients.last.id!,
        lotId: lots.last.id!,
        userId: 1,
        sellerId: otherSellerId,
        saleDate: now,
        salePrice: 550000,
        downPaymentPercentage: 10,
        requiredInitialPayment: 55000,
        initialPaymentPaid: 55000,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );

    final sellerSales = await salesRepository.fetchBySellerId(sellerId);

    expect(sellerSales, hasLength(1));
    expect(sellerSales.single.clientName, 'Cliente Dos');
    expect(sellerSales.single.lotDisplayCode, 'MA-S10');
  });
}

double _roundCurrency(double value) {
  return (value * 100).roundToDouble() / 100;
}
