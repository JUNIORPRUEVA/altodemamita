import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/business/installment_status.dart';
import 'package:sistema_solares/features/sales/domain/sale_calculator.dart';

void main() {
  final businessDate = DateTime(2026, 9, 15, 12);

  test('cuota futura, vence hoy y vencio ayer usan dia de negocio', () {
    expect(
      InstallmentStatusResolver.effectiveStatus(
        dueDate: DateTime(2026, 9, 16, 15, 11),
        totalAmount: 1000,
        paidAmount: 0,
        businessDate: businessDate,
      ),
      'pendiente',
    );
    expect(
      InstallmentStatusResolver.effectiveStatus(
        dueDate: DateTime(2026, 9, 15, 15, 11),
        totalAmount: 1000,
        paidAmount: 0,
        businessDate: businessDate,
      ),
      'pendiente',
    );
    expect(
      InstallmentStatusResolver.effectiveStatus(
        dueDate: DateTime(2026, 9, 14, 15, 11),
        totalAmount: 1000,
        paidAmount: 0,
        businessDate: businessDate,
      ),
      'vencida',
    );
  });

  test('cuota pagada vencida no se marca atrasada', () {
    expect(
      InstallmentStatusResolver.effectiveStatus(
        storedStatus: 'pagada',
        dueDate: DateTime(2026, 8, 15),
        totalAmount: 1000,
        paidAmount: 1000,
        businessDate: businessDate,
      ),
      'pagada',
    );
  });

  test('cuota parcial futura y parcial vencida se separan correctamente', () {
    expect(
      InstallmentStatusResolver.effectiveStatus(
        storedStatus: 'parcial',
        dueDate: DateTime(2026, 9, 20),
        totalAmount: 1000,
        paidAmount: 250,
        businessDate: businessDate,
      ),
      'parcial',
    );
    expect(
      InstallmentStatusResolver.effectiveStatus(
        storedStatus: 'parcial',
        dueDate: DateTime(2026, 8, 15),
        totalAmount: 1000,
        paidAmount: 250,
        businessDate: businessDate,
      ),
      'vencida',
    );
  });

  test('resumen no mezcla atrasadas con pendientes futuras', () {
    final summary = InstallmentStatusResolver.summarize([
      InstallmentStatusInput(
        dueDate: DateTime(2026, 8, 15),
        totalAmount: 1000,
        paidAmount: 1000,
      ),
      InstallmentStatusInput(
        dueDate: DateTime(2026, 8, 15),
        totalAmount: 1000,
        paidAmount: 0,
      ),
      InstallmentStatusInput(
        dueDate: DateTime(2026, 9, 20),
        totalAmount: 1000,
        paidAmount: 250,
      ),
      InstallmentStatusInput(
        dueDate: DateTime(2026, 10, 20),
        totalAmount: 1000,
        paidAmount: 0,
      ),
    ], businessDate: businessDate);

    expect(summary.total, 4);
    expect(summary.paid, 1);
    expect(summary.overdue, 1);
    expect(summary.partial, 1);
    expect(summary.pending, 1);
  });

  test('caso Iluminada deriva cuotas desde saleDate corregida', () {
    final schedule = SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: DateTime(2026, 7, 15, 15, 11),
      financedBalance: 504000,
      monthlyInterest: 1,
      installmentCount: 120,
      createdAt: DateTime(2026, 7, 15, 15, 11),
      statusAsOf: businessDate,
    );

    expect(schedule, hasLength(120));
    expect(schedule[0].dueDate, DateTime(2026, 8, 15, 15, 11));
    expect(schedule[1].dueDate, DateTime(2026, 9, 15, 15, 11));
    expect(schedule[0].status, 'vencida');
    expect(schedule[1].status, 'pendiente');
  });

  test('meses 28/29/30/31 y leap year conservan regla de dia', () {
    expect(
      SaleCalculator.buildInstallmentSchedule(
        saleId: 1,
        saleDate: DateTime(2026, 1, 31),
        financedBalance: 3000,
        monthlyInterest: 0,
        installmentCount: 1,
        createdAt: DateTime(2026, 1, 31),
      ).first.dueDate,
      DateTime(2026, 2, 28),
    );
    expect(
      SaleCalculator.buildInstallmentSchedule(
        saleId: 1,
        saleDate: DateTime(2028, 1, 31),
        financedBalance: 3000,
        monthlyInterest: 0,
        installmentCount: 1,
        createdAt: DateTime(2028, 1, 31),
      ).first.dueDate,
      DateTime(2028, 2, 29),
    );
  });

  test('America Santo Domingo evita adelantar el dia en frontera UTC', () {
    expect(
      InstallmentStatusResolver.isPastDue(
        dueDate: DateTime.utc(2026, 9, 15, 15, 11),
        businessDate: DateTime.utc(2026, 9, 16, 3, 30),
      ),
      false,
    );
  });
}
