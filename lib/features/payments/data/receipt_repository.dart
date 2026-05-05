import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../installments/domain/installment.dart';
import '../../settings/data/company_repository.dart';
import '../../settings/domain/company_info.dart';
import '../domain/payment_history_item.dart';
import '../domain/receipt.dart';
import 'payments_repository.dart';

class ReceiptRepository {
  ReceiptRepository({
    AppDatabase? appDatabase,
    CompanyRepository? companyRepository,
    PaymentsRepository? paymentsRepository,
    Database? settingsDatabase,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _companyRepository = companyRepository,
       _paymentsRepository = paymentsRepository ?? PaymentsRepository(),
       _settingsDatabase = settingsDatabase;

  final AppDatabase _appDatabase;
  final CompanyRepository? _companyRepository;
  final PaymentsRepository _paymentsRepository;
  final Database? _settingsDatabase;

  /// Obtiene un recibo de pago específico por ID de pago
  Future<Receipt?> fetchReceiptByPaymentId(int paymentId) async {
    try {
      return await _fetchReceiptByPaymentId(paymentId);
    } on DatabaseException catch (error) {
      if (!_isDatabaseClosedError(error)) {
        rethrow;
      }

      await _appDatabase.close();
      return _fetchReceiptByPaymentId(paymentId);
    }
  }

  Future<Receipt?> _fetchReceiptByPaymentId(int paymentId) async {
    final db = await _appDatabase.database;

    final paymentRows = await db.rawQuery(
      '''
      SELECT
        p.*,
        pu.nombre AS pago_usuario_nombre,
        q.numero_cuota
      FROM ${DatabaseSchema.paymentsTable} p
      LEFT JOIN ${DatabaseSchema.usersTable} pu ON pu.id = p.usuario_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
      WHERE p.id = ?
      LIMIT 1
    ''',
      [paymentId],
    );

    if (paymentRows.isEmpty) {
      return null;
    }

    final paymentRow = paymentRows.first;
    final saleId = paymentRow['venta_id'] as int? ?? 0;
    final payment = PaymentHistoryItem.fromMap(paymentRow);
    final paymentReference = (payment.reference ?? '').trim();
    final paymentRegisteredByName =
        (paymentRow['pago_usuario_nombre'] as String? ?? '').trim();

    final saleDetailRows = await db.rawQuery(
      '''
      SELECT
        v.cantidad_cuotas,
        v.interes_mensual,
        s.manzana_numero,
        s.solar_numero,
        u.nombre AS venta_usuario_nombre,
        vnd.nombre AS vendedor_nombre
      FROM ${DatabaseSchema.salesTable} v
      INNER JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      INNER JOIN ${DatabaseSchema.usersTable} u ON u.id = v.usuario_id
      LEFT JOIN ${DatabaseSchema.sellersTable} vnd ON vnd.id = v.vendedor_id
      WHERE v.id = ?
      LIMIT 1
    ''',
      [saleId],
    );
    final saleDetailRow = saleDetailRows.isEmpty ? null : saleDetailRows.first;

    final operationRows = paymentReference.isEmpty
        ? paymentRows
        : await db.rawQuery(
            '''
            SELECT
              p.*,
              pu.nombre AS pago_usuario_nombre,
              q.numero_cuota
            FROM ${DatabaseSchema.paymentsTable} p
            LEFT JOIN ${DatabaseSchema.usersTable} pu ON pu.id = p.usuario_id
            LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
            WHERE p.referencia = ?
            ORDER BY p.id ASC
          ''',
            [paymentReference],
          );
    final operationPayments = operationRows
        .map(PaymentHistoryItem.fromMap)
        .toList(growable: false);

    final saleContext = await _paymentsRepository.fetchSaleContext(saleId);
    if (saleContext == null) {
      return null;
    }

    var company = _companyRepository != null
        ? await _companyRepository.getCompanyInfo()
        : null;

    company ??= await CompanyRepository(db).getCompanyInfo();

    if (company == null && _settingsDatabase != null) {
      final companyRepo = CompanyRepository(_settingsDatabase);
      company = await companyRepo.getCompanyInfo();
    }

    company ??= CompanyInfo(
      nombre: 'Sistema de Solares',
      telefono: null,
      direccion: null,
      logoBytesBase64: null,
      fechaCreacion: DateTime.now(),
      fechaActualizacion: DateTime.now(),
    );

    final paidInstallmentPayment = operationPayments
        .where((item) => item.installmentId != null)
        .cast<PaymentHistoryItem?>()
        .firstWhere((item) => item != null, orElse: () => null);
    final installmentId = paidInstallmentPayment?.installmentId;
    Installment? paidInstallment;
    if (installmentId != null) {
      paidInstallment = saleContext.installments.firstWhere(
        (i) => i.id == installmentId,
        orElse: () => throw StateError('Cuota no encontrada'),
      );
    }

    final paidCapital = operationPayments
        .where((item) => item.paymentType == 'abono_capital')
        .fold<double>(0, (sum, item) => sum + item.amountPaid);

    final paidInstallments = saleContext.installments
        .where((i) => i.status == 'pagada' || i.status == 'ajustada')
        .length;
    final remainingInstallments =
        saleContext.installments.length - paidInstallments;
    final totalPaidAccumulated = saleContext.history.fold<double>(
      0,
      (sum, item) => sum + item.amountPaid,
    );
    final nextInstallment = saleContext.installments.firstWhere(
      (installment) => !_isClosedStatus(installment.status),
      orElse: () => Installment(
        saleId: saleId,
        installmentNumber: 0,
        dueDate: payment.paymentDate,
        openingBalance: 0,
        principalAmount: 0,
        interestAmount: 0,
        totalAmount: 0,
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        endingBalance: 0,
        status: 'pagada',
        createdAt: payment.paymentDate,
        updatedAt: payment.paymentDate,
      ),
    );
    final hasNextInstallment =
        nextInstallment.installmentNumber > 0 &&
        !_isClosedStatus(nextInstallment.status) &&
        nextInstallment.remainingAmount > 0.009;
    final accountStatusLabel = _buildAccountStatus(
      saleContext.sale,
      hasNextInstallment ? nextInstallment : null,
      payment.paymentDate,
    );

    final receiptNumber = _generateReceiptNumber(
      paymentId,
      payment.paymentDate,
    );
    final installmentCount = saleDetailRow?['cantidad_cuotas'] as int? ?? 0;
    final monthlyInterest = _toDouble(saleDetailRow?['interes_mensual']);
    final hasInitialStagePayments = operationPayments.any(
      (item) =>
          item.paymentType == 'apartado' || item.paymentType == 'abono_inicial',
    );
    final conditionsOfPayment = hasInitialStagePayments
        ? 'Pago aplicado al inicial requerido de la venta. El financiamiento solo inicia cuando el inicial queda completado.'
        : installmentCount <= 0
        ? 'Pago registrado sin plan de cuotas asociado.'
      : '$installmentCount cuotas mensuales fijas con interes simple de ${monthlyInterest.toStringAsFixed(2)}% sobre el capital financiado original.';
    final note = hasInitialStagePayments
        ? 'Este recibo corresponde a un pago previo a la activación del financiamiento. El saldo del inicial y el estado de la venta fueron actualizados en el sistema.'
      : 'Conserve este recibo. Cada pago reduce el saldo pendiente del plan sin recalcular el interes pactado ni cambiar la cuota mensual fija.';

    return Receipt(
      paymentId: paymentId,
      receiptNumber: receiptNumber,
      paymentDate: payment.paymentDate,
      sale: saleContext.sale,
      payment: payment,
      payments: operationPayments,
      company: company,
      paidInstallment: paidInstallment,
      paidCapitalAmount: paidCapital > 0 ? paidCapital : null,
      installmentsPaid: paidInstallments,
      installmentsRemaining: remainingInstallments,
      totalPaidAccumulated: _toDouble(totalPaidAccumulated),
      accountStatusLabel: accountStatusLabel,
      nextInstallmentNumber: hasNextInstallment
          ? nextInstallment.installmentNumber
          : null,
      nextInstallmentDueDate: hasNextInstallment
          ? nextInstallment.dueDate
          : null,
      nextInstallmentAmount: hasNextInstallment
          ? nextInstallment.remainingAmount
          : null,
      monthlyInterest: saleContext.monthlyInterest,
      blockNumber: saleDetailRow?['manzana_numero'] as String? ?? '',
      lotNumber: saleDetailRow?['solar_numero'] as String? ?? '',
      installmentCount: installmentCount,
      userName: saleDetailRow?['venta_usuario_nombre'] as String? ?? '',
      paymentRegisteredByName: paymentRegisteredByName,
      sellerName: saleDetailRow?['vendedor_nombre'] as String?,
      conditionsOfPayment: conditionsOfPayment,
      note: note,
    );
  }

  bool _isDatabaseClosedError(DatabaseException error) {
    return error.toString().toLowerCase().contains('database_closed');
  }

  /// Genera un número de recibo único basado en fecha y ID de pago
  String _generateReceiptNumber(int paymentId, DateTime paymentDate) {
    final dateStr = paymentDate.toString().substring(0, 10).replaceAll('-', '');
    return '$dateStr-$paymentId';
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  bool _isClosedStatus(String status) {
    return status == 'pagada' || status == 'ajustada';
  }

  String _buildAccountStatus(
    dynamic sale,
    Installment? nextInstallment,
    DateTime referenceDate,
  ) {
    final totalOutstanding =
        _toDouble(sale.pendingBalance) + _toDouble(sale.pendingInitialPayment);
    if (totalOutstanding <= 0.009) {
      return 'Saldada';
    }

    if (_toDouble(sale.pendingInitialPayment) > 0.009) {
      return _toDouble(sale.paidInitialPayment) > 0.009
          ? 'Inicial parcial'
          : 'Inicial pendiente';
    }

    if (nextInstallment == null) {
      return 'Al dia';
    }

    final referenceDay = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final dueDay = DateTime(
      nextInstallment.dueDate.year,
      nextInstallment.dueDate.month,
      nextInstallment.dueDate.day,
    );

    if (dueDay.isBefore(referenceDay)) {
      return nextInstallment.status == 'parcial'
          ? 'Vencida parcial'
          : 'Vencida';
    }

    if (!dueDay.isAfter(referenceDay)) {
      return nextInstallment.status == 'parcial' ? 'Parcial' : 'Pendiente';
    }

    return nextInstallment.status == 'parcial' ? 'Parcial' : 'Al dia';
  }
}
