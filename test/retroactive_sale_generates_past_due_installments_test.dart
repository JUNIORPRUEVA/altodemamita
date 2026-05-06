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
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/repositories/installments_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';
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
  late PaymentsRepository paymentsRepository;
  late InstallmentsSyncRepository installmentsSyncRepository;
  late SyncQueueService syncQueueService;
  var sequence = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'retroactive_sale_installments_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    syncQueueService = SyncQueueService.test(
      appDatabase: appDatabase,
      conflictService: SyncConflictService(appDatabase: appDatabase),
    );
    clientRepository = ClientRepository(appDatabase: appDatabase);
    lotRepository = LotRepository(appDatabase: appDatabase);
    salesRepository = SalesRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );
    paymentsRepository = PaymentsRepository(
      appDatabase: appDatabase,
      syncQueueService: syncQueueService,
    );
    installmentsSyncRepository = InstallmentsSyncRepository(
      appDatabase: appDatabase,
    );
  });

  tearDown(() async {
    syncQueueService.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<int> createSale({
    required DateTime saleDate,
    bool initialIsApartado = false,
    double initialPaymentPaid = 100000,
    DateTime? initialPaymentDeadline,
  }) async {
    sequence += 1;
    await clientRepository.save(
      Client(
        fullName: 'Cliente Retroactivo $sequence',
        documentId: '001-7777${sequence.toString().padLeft(5, '0')}-1',
        phone: '809555000$sequence',
        createdAt: saleDate,
        updatedAt: saleDate,
      ),
    );
    await lotRepository.save(
      Lot(
        blockNumber: 'R',
        lotNumber: sequence.toString().padLeft(2, '0'),
        area: 200,
        price: 1000000,
        status: 'disponible',
        createdAt: saleDate,
        updatedAt: saleDate,
      ),
    );

    final client = (await clientRepository.fetchAll()).last;
    final lot = (await lotRepository.fetchAll()).last;

    return salesRepository.createSale(
      SaleDraft(
        clientId: client.id!,
        lotId: lot.id!,
        userId: 1,
        saleDate: saleDate,
        salePrice: 1000000,
        downPaymentPercentage: 10,
        requiredInitialPayment: 100000,
        initialPaymentPaid: initialPaymentPaid,
        initialPaymentDeadline: initialPaymentDeadline,
        initialIsApartado: initialIsApartado,
        monthlyInterest: 1,
        installmentCount: 12,
      ),
    );
  }

  Future<List<Map<String, Object?>>> installmentRows(int saleId) async {
    final db = await appDatabase.database;
    return db.query(
      DatabaseSchema.installmentsTable,
      where: 'venta_id = ? AND deleted_at IS NULL',
      whereArgs: [saleId],
      orderBy: 'numero_cuota ASC',
    );
  }

  test('retroactive_sale_generates_past_due_installments_test', () async {
    final today = DateTime.now();
    final retroactiveDate = DateTime(today.year, today.month - 5, today.day);

    final saleId = await createSale(saleDate: retroactiveDate);
    final rows = await installmentRows(saleId);

    expect(rows, hasLength(12));
    expect(rows.where((row) => row['estado'] == 'vencida'), isNotEmpty);
    expect(
      rows.where((row) => row['estado'] == 'vencida').every((row) {
        final dueDate = DateTime.parse(row['fecha_vencimiento'] as String);
        return DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
        ).isBefore(DateTime(today.year, today.month, today.day));
      }),
      isTrue,
    );
  });

  test('retroactive_sale_keeps_future_installments_pending_test', () async {
    final today = DateTime.now();
    final saleId = await createSale(saleDate: today);
    final rows = await installmentRows(saleId);

    expect(rows, hasLength(12));
    expect(rows.every((row) => row['estado'] == 'pendiente'), isTrue);
  });

  test('retroactive_sale_allows_paying_overdue_installments_test', () async {
    final today = DateTime.now();
    final saleId = await createSale(
      saleDate: DateTime(today.year, today.month - 5, today.day),
    );
    final beforeRows = await installmentRows(saleId);
    final firstOverdue = beforeRows.firstWhere(
      (row) => row['estado'] == 'vencida',
    );
    final amount = (firstOverdue['monto_cuota'] as num).toDouble();

    await paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        amountPaid: amount,
        paymentDate: today,
        paymentMethod: 'efectivo',
      ),
    );

    final afterRows = await installmentRows(saleId);
    final paidRow = afterRows.firstWhere(
      (row) => row['id'] == firstOverdue['id'],
    );
    final saleRow = (await (await appDatabase.database).query(
      DatabaseSchema.salesTable,
      columns: ['saldo_pendiente'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    )).single;

    expect(paidRow['estado'], 'pagada');
    expect((paidRow['monto_pagado'] as num).toDouble(), amount);
    expect((saleRow['saldo_pendiente'] as num).toDouble(), lessThan(900000));
  });

  test(
    'retroactive_sale_does_not_mark_down_payment_as_paid_if_only_reserved_test',
    () async {
      final today = DateTime.now();
      final saleId = await createSale(
        saleDate: DateTime(today.year, today.month - 5, today.day),
        initialIsApartado: true,
        initialPaymentPaid: 10000,
        initialPaymentDeadline: today.add(const Duration(days: 10)),
      );
      final db = await appDatabase.database;
      final saleRow = (await db.query(
        DatabaseSchema.salesTable,
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      )).single;

      expect((saleRow['monto_inicial_pagado'] as num).toDouble(), 0);
      expect((saleRow['monto_apartado_pagado'] as num).toDouble(), 10000);
      expect(saleRow['estado'], 'apartado');
      expect(await installmentRows(saleId), isEmpty);
    },
  );

  test(
    'retroactive_sale_offline_sync_keeps_installment_statuses_test',
    () async {
      final today = DateTime.now();
      final saleId = await createSale(
        saleDate: DateTime(today.year, today.month - 5, today.day),
      );

      final localStatuses = (await installmentRows(
        saleId,
      )).map((row) => row['estado']).toList(growable: false);
      final syncPayloadStatuses =
          (await installmentsSyncRepository.getPendingRecords())
              .map((row) => row['status'])
              .toList(growable: false);

      expect(syncPayloadStatuses, localStatuses);
      expect(syncPayloadStatuses, contains('vencida'));
    },
  );

  test(
    'editing_retroactive_sale_does_not_duplicate_installments_test',
    () async {
      final today = DateTime.now();
      final saleDate = DateTime(today.year, today.month - 5, today.day);
      final saleId = await createSale(saleDate: saleDate);

      await salesRepository.updateSale(
        saleId,
        SaleDraft(
          clientId: (await clientRepository.fetchAll()).last.id!,
          lotId: (await lotRepository.fetchAll()).last.id!,
          userId: 1,
          saleDate: saleDate.subtract(const Duration(days: 7)),
          salePrice: 1000000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      );

      final rows = await installmentRows(saleId);
      final numbers = rows.map((row) => row['numero_cuota']).toSet();
      expect(rows, hasLength(12));
      expect(numbers, hasLength(12));
    },
  );

  test('changing_sale_date_with_payments_is_blocked_or_warned_test', () async {
    final today = DateTime.now();
    final saleDate = DateTime(today.year, today.month - 5, today.day);
    final saleId = await createSale(saleDate: saleDate);
    final firstOverdue = (await installmentRows(
      saleId,
    )).firstWhere((row) => row['estado'] == 'vencida');

    await paymentsRepository.registerPayment(
      PaymentDraft(
        saleId: saleId,
        amountPaid: (firstOverdue['monto_cuota'] as num).toDouble(),
        paymentDate: today,
        paymentMethod: 'efectivo',
      ),
    );

    final clientId = (await clientRepository.fetchAll()).last.id!;
    final lotId = (await lotRepository.fetchAll()).last.id!;

    expect(
      () => salesRepository.updateSale(
        saleId,
        SaleDraft(
          clientId: clientId,
          lotId: lotId,
          userId: 1,
          saleDate: saleDate.subtract(const Duration(days: 7)),
          salePrice: 1000000,
          downPaymentPercentage: 10,
          requiredInitialPayment: 100000,
          initialPaymentPaid: 100000,
          monthlyInterest: 1,
          installmentCount: 12,
        ),
      ),
      throwsStateError,
    );

    expect(await installmentRows(saleId), hasLength(12));
  });
}
