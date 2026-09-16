import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/business/installment_status.dart';
import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/sales/domain/sale_calculator.dart';

/// FASE 8 / 13-15 del hardening P0.
///
/// - Grupo 1: el dia de negocio se resuelve SIEMPRE en America/Santo_Domingo y no
///   depende de la zona horaria del equipo (UTC, UTC-3, UTC-4, UTC-5...).
/// - Grupo 2: el calendario esta anclado en `saleDate`; un inicial pagado en otro
///   mes NO mueve las cuotas (regresion del incidente P0).
void main() {
  group('Dia de negocio America/Santo_Domingo', () {
    test('un instante UTC se resuelve al reloj de RD (UTC-4 fijo)', () {
      // 2026-09-16 03:30Z == 2026-09-15 23:30 en Republica Dominicana.
      expect(
        InstallmentStatusResolver.businessDateKey(DateTime.utc(2026, 9, 16, 3, 30)),
        '2026-09-15',
      );
      expect(
        InstallmentStatusResolver.businessDateKey(
          DateTime.parse('2026-09-16T03:30:00Z'),
        ),
        '2026-09-15',
      );
      expect(
        InstallmentStatusResolver.businessDateKey(
          DateTime.parse('2026-09-16T04:00:00Z'),
        ),
        '2026-09-16',
      );
    });

    test('un valor naive conserva su hora de pared (no depende del equipo)', () {
      // Los valores que la app captura y persiste no llevan zona horaria:
      // representan hora de pared de RD y se usan tal cual.
      expect(
        InstallmentStatusResolver.businessDateKey(DateTime(2026, 8, 15, 15, 11)),
        '2026-08-15',
      );
      expect(
        InstallmentStatusResolver.businessDateKey(DateTime(2026, 9, 16, 0, 0)),
        '2026-09-16',
      );
    });

    test('el dia de negocio cambia a las 04:00Z (20:00 RD), no a las 00:00Z', () {
      const cases = <String, String>{
        '2026-09-15T23:59:00Z': '2026-09-15', // 19:59 RD
        '2026-09-16T00:00:00Z': '2026-09-15', // 20:00 RD (UTC ya cambio de dia)
        '2026-09-16T01:00:00Z': '2026-09-15', // 21:00 RD
        '2026-09-16T03:59:00Z': '2026-09-15', // 23:59 RD
        '2026-09-16T04:00:00Z': '2026-09-16', // 00:00 RD
        '2026-09-16T04:01:00Z': '2026-09-16', // 00:01 RD
      };
      cases.forEach((instant, expected) {
        expect(
          InstallmentStatusResolver.currentBusinessDateKey(DateTime.parse(instant)),
          expected,
          reason: 'instante $instant',
        );
      });
    });

    test('una cuota que vence el 15 no esta vencida hasta el dia de negocio 16', () {
      final due = DateTime.parse('2026-09-15T15:11:00Z'); // 11:11 RD del 15
      for (final instant in const [
        '2026-09-15T23:59:00Z', // 19:59 RD
        '2026-09-16T00:00:00Z', // 20:00 RD — el bug UTC la marcaba vencida aqui
        '2026-09-16T01:00:00Z', // 21:00 RD
        '2026-09-16T03:59:00Z', // 23:59 RD
      ]) {
        expect(
          InstallmentStatusResolver.isPastDue(
            dueDate: due,
            businessDate: DateTime.parse(instant),
          ),
          isFalse,
          reason: 'no debe estar vencida a las $instant',
        );
      }
      expect(
        InstallmentStatusResolver.isPastDue(
          dueDate: due,
          businessDate: DateTime.parse('2026-09-16T04:00:00Z'),
        ),
        isTrue,
      );
    });
  });

  group('REGRESION P0: calendario anclado a saleDate (120 cuotas)', () {
    // Equivalente contractual del incidente: venta 2026-07-15, inicial pagado
    // 2026-08-15, 120 cuotas, dia de negocio 2026-09-16 (RD).
    final saleDate = DateTime(2026, 7, 15, 15, 11);
    final businessDate = DateTime.parse('2026-09-16T12:00:00Z');

    List<Installment> buildSchedule() => SaleCalculator.buildInstallmentSchedule(
      saleId: 1,
      saleDate: saleDate,
      financedBalance: 504000,
      monthlyInterest: 1,
      installmentCount: 120,
      createdAt: saleDate,
    );

    InstallmentSummaryCounts summarize(List<Installment> installments) {
      return InstallmentStatusResolver.summarize(
        installments.map(
          (item) => InstallmentStatusInput(
            dueDate: item.dueDate,
            totalAmount: item.totalAmount,
            paidAmount: item.paidAmount,
            remainingAmount: item.remainingAmount,
            storedStatus: item.status,
          ),
        ),
        businessDate: businessDate,
      );
    }

    test('cuota 1 = saleDate + 1 mes y cuota 120 = saleDate + 120 meses', () {
      final schedule = buildSchedule();
      expect(schedule.length, 120);

      final first = schedule.first.dueDate;
      expect([first.year, first.month, first.day], [2026, 8, 15]);
      expect([first.hour, first.minute], [15, 11]);

      final second = schedule[1].dueDate;
      expect([second.year, second.month, second.day], [2026, 9, 15]);

      final last = schedule.last.dueDate;
      expect([last.year, last.month, last.day], [2036, 7, 15]);
    });

    test('0 pagadas / 2 vencidas / 118 pendientes con el inicial pagado en agosto', () {
      final summary = summarize(buildSchedule());
      expect(summary.total, 120);
      expect(summary.paid, 0);
      expect(summary.overdue, 2);
      expect(summary.partial, 0);
      expect(summary.pending, 118);
    });

    test('FASE 14/15: la fecha del inicial no altera el calendario', () {
      // El generador local no recibe la fecha de activacion: solo `saleDate`.
      // Se congela esa garantia para el mismo dia (FASE 14) y un mes despues
      // (FASE 15, el caso real del incidente).
      final schedule = buildSchedule();
      final dueDates = schedule.map((item) => item.dueDate).toList();
      expect(dueDates.first.month, 8, reason: 'FASE 14: inicial el mismo dia');
      expect(dueDates[1].month, 9, reason: 'FASE 15: inicial el 2026-09-01');

      // La inicial del incidente fue el 2026-08-15; ninguna cuota debe caer en
      // septiembre-diciembre desplazada: la primera es agosto.
      expect(dueDates.first.isBefore(dueDates[1]), isTrue);
      expect(
        dueDates.every((date) => date.day == 15),
        isTrue,
        reason: 'todas las cuotas conservan el dia contractual',
      );
    });
  });
}
