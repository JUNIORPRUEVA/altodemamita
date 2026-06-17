import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';

class PaymentApplicationTestHarness {
  PaymentApplicationTestHarness._({
    required this.tempDir,
    required this.appDatabase,
    required this.salesRepository,
    required this.paymentsRepository,
  });

  final Directory tempDir;
  final AppDatabase appDatabase;
  final SalesRepository salesRepository;
  final PaymentsRepository paymentsRepository;

  static Future<PaymentApplicationTestHarness> create() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'payment_application_test_',
    );
    final dbPath = p.join(tempDir.path, 'test.db');
    final appDatabase = AppDatabase.test(dbPath);
    await appDatabase.initialize();
    return PaymentApplicationTestHarness._(
      tempDir: tempDir,
      appDatabase: appDatabase,
      salesRepository: SalesRepository(appDatabase: appDatabase),
      paymentsRepository: PaymentsRepository(appDatabase: appDatabase),
    );
  }

  Future<void> dispose() async {
    await appDatabase.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }

  Future<int> createFinancedSale({
    DateTime? saleDate,
    double salePrice = 100000,
    double requiredInitialPayment = 10000,
    int installmentCount = 6,
    double monthlyInterest = 1,
  }) async {
    final db = await appDatabase.database;
    final date = saleDate ?? DateTime(2026, 1, 10, 10);

    final clientId = await db.insert(DatabaseSchema.clientsTable, {
      'nombre': 'CLIENTE TEST',
      'cedula': '00000000001',
      'telefono': '8090000001',
      'direccion': 'DIRECCION',
      'fecha_creacion': date.toIso8601String(),
      'fecha_actualizacion': date.toIso8601String(),
    });

    final sellerId = await db.insert(DatabaseSchema.sellersTable, {
      'nombre': 'VENDEDOR TEST',
      'cedula': '10000000001',
      'telefono': '8090000002',
      'fecha_creacion': date.toIso8601String(),
      'fecha_actualizacion': date.toIso8601String(),
    });

    final lotId = await db.insert(DatabaseSchema.lotsTable, {
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1000,
      'estado': 'disponible',
      'fecha_creacion': date.toIso8601String(),
      'fecha_actualizacion': date.toIso8601String(),
    });

    return salesRepository.createSale(
      SaleDraft(
        clientId: clientId,
        lotId: lotId,
        userId: 1,
        sellerId: sellerId,
        saleDate: date,
        salePrice: salePrice,
        downPaymentPercentage: (requiredInitialPayment / salePrice) * 100,
        requiredInitialPayment: requiredInitialPayment,
        initialPaymentPaid: requiredInitialPayment,
        monthlyInterest: monthlyInterest,
        installmentCount: installmentCount,
      ),
    );
  }
}
