import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/data/receipt_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/sales/data/sales_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'fixed_scenario_probe_',
  );
  final dbPath = p.join(tempDir.path, 'probe.db');
  final appDatabase = AppDatabase.test(dbPath);
  await appDatabase.initialize();
  final db = await appDatabase.database;

  final salesRepository = SalesRepository(appDatabase: appDatabase);
  final paymentsRepository = PaymentsRepository(appDatabase: appDatabase);
  final receiptRepository = ReceiptRepository(
    appDatabase: appDatabase,
    paymentsRepository: paymentsRepository,
  );

  final fixedSaleDate = DateTime(2026, 1, 15, 10, 0, 0);
  final clientId = await db.insert(DatabaseSchema.clientsTable, {
    'nombre': 'CLIENTE FIJO',
    'cedula': '00000000001',
    'telefono': '8090000001',
    'direccion': 'DIRECCION FIJA',
    'fecha_creacion': fixedSaleDate.toIso8601String(),
    'fecha_actualizacion': fixedSaleDate.toIso8601String(),
  });

  final sellerId = await db.insert(DatabaseSchema.sellersTable, {
    'nombre': 'VENDEDOR FIJO',
    'cedula': '10000000001',
    'telefono': '8090000002',
    'fecha_creacion': fixedSaleDate.toIso8601String(),
    'fecha_actualizacion': fixedSaleDate.toIso8601String(),
  });

  final lotId = await db.insert(DatabaseSchema.lotsTable, {
    'manzana_numero': 'A',
    'solar_numero': '101',
    'metros_cuadrados': 125.0,
    'precio_por_metro': 5000.0,
    'estado': 'disponible',
    'fecha_creacion': fixedSaleDate.toIso8601String(),
    'fecha_actualizacion': fixedSaleDate.toIso8601String(),
  });

  final saleId = await salesRepository.createSale(
    SaleDraft(
      clientId: clientId,
      lotId: lotId,
      userId: 1,
      sellerId: sellerId,
      saleDate: fixedSaleDate,
      salePrice: 625000,
      downPaymentPercentage: 16,
      requiredInitialPayment: 100000,
      initialPaymentPaid: 100000,
      monthlyInterest: 1,
      installmentCount: 24,
    ),
  );

  final createdContext = await paymentsRepository.fetchSaleContext(saleId);
  final createdSaleRow = (await db.query(
    DatabaseSchema.salesTable,
    where: 'id = ?',
    whereArgs: [saleId],
    limit: 1,
  )).single;
  final createdInstallments = await db.query(
    DatabaseSchema.installmentsTable,
    where: 'venta_id = ? AND deleted_at IS NULL',
    whereArgs: [saleId],
    orderBy: 'numero_cuota ASC',
  );

  final firstInstallment =
      createdContext!.actionableInstallment ??
      (throw StateError('No actionable installment for probe scenario'));

  final partialAmount = (firstInstallment.totalAmount / 2);
  await paymentsRepository.registerPayment(
    PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime(2026, 2, 15, 11, 0, 0),
      amountPaid: partialAmount,
      paymentMethod: 'efectivo',
    ),
  );

  final afterPartialContext = await paymentsRepository.fetchSaleContext(saleId);

  final installmentAfterPartial = (await db.query(
    DatabaseSchema.installmentsTable,
    where: 'id = ?',
    whereArgs: [firstInstallment.id],
    limit: 1,
  )).single;

  final remainingToFullInstallment =
      _toDouble(installmentAfterPartial['monto_cuota']) -
      _toDouble(installmentAfterPartial['monto_pagado']);

  await paymentsRepository.registerPayment(
    PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime(2026, 2, 16, 11, 0, 0),
      amountPaid: remainingToFullInstallment,
      paymentMethod: 'transferencia',
    ),
  );

  final afterFullContext = await paymentsRepository.fetchSaleContext(saleId);

  await paymentsRepository.registerPayment(
    PaymentDraft(
      saleId: saleId,
      paymentDate: DateTime(2026, 2, 20, 11, 0, 0),
      amountPaid: 20000,
      paymentMethod: 'efectivo',
    ),
  );

  await paymentsRepository.fetchSaleContext(saleId);
  final finalSaleRow = (await db.query(
    DatabaseSchema.salesTable,
    where: 'id = ?',
    whereArgs: [saleId],
    limit: 1,
  )).single;

  final finalInstallments = await db.query(
    DatabaseSchema.installmentsTable,
    where: 'venta_id = ? AND deleted_at IS NULL',
    whereArgs: [saleId],
    orderBy: 'numero_cuota ASC',
  );

  final payments = await db.query(
    DatabaseSchema.paymentsTable,
    where: 'venta_id = ? AND deleted_at IS NULL',
    whereArgs: [saleId],
    orderBy: 'id ASC',
  );

  final latestPaymentId = payments.isEmpty
      ? null
      : (payments.last['id'] as int?);
  Map<String, Object?>? receiptSummary;
  if (latestPaymentId != null) {
    final receipt = await receiptRepository.fetchReceiptByPaymentId(
      latestPaymentId,
    );
    if (receipt != null) {
      receiptSummary = {
        'paymentId': receipt.paymentId,
        'receiptNumber': receipt.receiptNumber,
        'saleId': receipt.sale.saleId,
        'clientName': receipt.sale.clientName,
        'lotDisplayCode': receipt.sale.lotDisplayCode,
        'amountPaid': receipt.payment.amountPaid,
        'pendingBalance': receipt.sale.pendingBalance,
        'paidCapitalAmount': receipt.paidCapitalAmount,
        'installmentsPaid': receipt.installmentsPaid,
        'installmentsRemaining': receipt.installmentsRemaining,
      };
    }
  }

  final output = {
    'scenario': {
      'salePrice': 625000,
      'downPayment': 100000,
      'expectedFinanced': 525000,
      'termMonths': 24,
      'saleDate': fixedSaleDate.toIso8601String(),
      'partialPayment': partialAmount,
      'capitalPrepayment': 20000,
    },
    'created': {
      'saleId': saleId,
      'salePrice': _toDouble(createdSaleRow['precio_venta']),
      'downPaymentPaid': _toDouble(createdSaleRow['monto_inicial_pagado']),
      'financedBalance': _toDouble(createdSaleRow['saldo_financiado']),
      'pendingBalance': _toDouble(createdSaleRow['saldo_pendiente']),
      'saleStatus': createdSaleRow['estado'],
      'installmentCount': createdInstallments.length,
      'firstInstallmentAmount': createdInstallments.isEmpty
          ? 0
          : _toDouble(createdInstallments.first['monto_cuota']),
      'firstInstallmentDueDate': createdInstallments.isEmpty
          ? null
          : createdInstallments.first['fecha_vencimiento'],
      'lastInstallmentDueDate': createdInstallments.isEmpty
          ? null
          : createdInstallments.last['fecha_vencimiento'],
    },
    'afterPartial': {
      'pendingBalance': afterPartialContext?.sale.pendingBalance,
      'saleStatus': afterPartialContext?.sale.status,
      'firstInstallmentPaid': _toDouble(
        installmentAfterPartial['monto_pagado'],
      ),
      'firstInstallmentStatus': installmentAfterPartial['estado'],
    },
    'afterFullInstallment': {
      'pendingBalance': afterFullContext?.sale.pendingBalance,
      'saleStatus': afterFullContext?.sale.status,
    },
    'final': {
      'pendingBalance': _toDouble(finalSaleRow['saldo_pendiente']),
      'saleStatus': finalSaleRow['estado'],
      'totalPaid': payments.fold<double>(
        0,
        (sum, row) => sum + _toDouble(row['monto_pagado']),
      ),
      'paymentsCount': payments.length,
      'installmentsCount': finalInstallments.length,
      'first3Installments': finalInstallments.take(3).map((row) {
        return {
          'number': row['numero_cuota'],
          'amount': _toDouble(row['monto_cuota']),
          'paid': _toDouble(row['monto_pagado']),
          'endingBalance': _toDouble(row['saldo_final']),
          'status': row['estado'],
          'dueDate': row['fecha_vencimiento'],
        };
      }).toList(),
      'paymentTypes': payments.map((row) => row['tipo_pago']).toList(),
    },
    'receipt': receiptSummary,
  };

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));

  await appDatabase.close();
  await tempDir.delete(recursive: true);
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString()) ?? 0;
}
