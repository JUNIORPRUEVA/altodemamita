import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/domain/authoritative_late_fee.dart';

void main() {
  group('AuthoritativeLateFeeSummary.fromMap', () {
    test('parsea totales y detalle por cuota', () {
      final summary = AuthoritativeLateFeeSummary.fromMap({
        'saleId': 'sale-1',
        'saleSyncId': 'sale-sync-1',
        'asOfDate': '2026-10-28T12:00:00.000Z',
        'policyEnabled': true,
        'grossLateFees': 536.4,
        'collectedLateFees': 520.8,
        'waivedLateFees': 15.6,
        'outstandingLateFees': 0,
        'installments': [
          {
            'installmentSyncId': 'inst-3',
            'installmentNumber': 3,
            'dueDate': '2026-10-06',
            'grossLateFee': 536.4,
            'waivedLateFee': 15.6,
            'collectedLateFee': 520.8,
            'outstandingLateFee': 0,
          },
        ],
      });

      expect(summary.saleId, 'sale-1');
      expect(summary.saleSyncId, 'sale-sync-1');
      expect(summary.grossLateFees, 536.4);
      expect(summary.collectedLateFees, 520.8);
      expect(summary.waivedLateFees, 15.6);
      expect(summary.outstandingLateFees, 0);
      expect(summary.hasWaiver, isTrue);
      expect(summary.installments, hasLength(1));
      expect(summary.installments.first.installmentNumber, 3);
      expect(summary.installments.first.waivedLateFee, 15.6);
    });

    test('tolera numeros serializados como texto y listas ausentes', () {
      final summary = AuthoritativeLateFeeSummary.fromMap({
        'saleId': 'sale-2',
        'grossLateFees': '100.50',
        'waivedLateFees': '0.00',
      });

      expect(summary.grossLateFees, 100.5);
      expect(summary.waivedLateFees, 0);
      expect(summary.hasWaiver, isFalse);
      expect(summary.installments, isEmpty);
    });
  });

  group('outstandingForInstallmentNumber', () {
    final summary = AuthoritativeLateFeeSummary.fromMap({
      'saleId': 'sale-1',
      'installments': [
        {'installmentNumber': 1, 'outstandingLateFee': 10},
        {'installmentNumber': 2, 'outstandingLateFee': 20},
      ],
    });

    test('devuelve el monto de la cuota solicitada', () {
      expect(summary.outstandingForInstallmentNumber(1), 10);
      expect(summary.outstandingForInstallmentNumber(2), 20);
    });

    test('devuelve cero cuando la cuota no esta vencida', () {
      expect(summary.outstandingForInstallmentNumber(5), 0);
      expect(summary.outstandingForInstallmentNumber(null), 0);
    });
  });

  group('resolveCollectibleLateFee', () {
    final authoritative = AuthoritativeLateFeeSummary.fromMap({
      'saleId': 'sale-1',
      'installments': [
        {'installmentNumber': 3, 'outstandingLateFee': 0},
        {'installmentNumber': 4, 'outstandingLateFee': 12.5},
      ],
    });

    test('sin autoridad conserva el calculo local', () {
      expect(
        resolveCollectibleLateFee(
          localLateFee: 125,
          authoritative: null,
          installmentNumber: 3,
        ),
        125,
      );
    });

    test('con autoridad la mora condonada deja de ser cobrable', () {
      expect(
        resolveCollectibleLateFee(
          localLateFee: 125,
          authoritative: authoritative,
          installmentNumber: 3,
        ),
        0,
      );
    });

    test('con autoridad prevalece el monto del backend', () {
      expect(
        resolveCollectibleLateFee(
          localLateFee: 125,
          authoritative: authoritative,
          installmentNumber: 4,
        ),
        12.5,
      );
    });

    test('una cuota no listada por el backend no inventa mora', () {
      expect(
        resolveCollectibleLateFee(
          localLateFee: 125,
          authoritative: authoritative,
          installmentNumber: 9,
        ),
        0,
      );
    });
  });

  group('evaluateLateFeeMutationPolicy', () {
    final summary = AuthoritativeLateFeeSummary.fromMap({
      'saleId': 'sale-1',
      'waivedLateFees': 15.6,
    });

    test('con autoridad disponible se permite y usa el backend', () {
      final policy = evaluateLateFeeMutationPolicy(
        authority: LateFeeAuthority.available(summary),
        knownSaleHasWaiver: true,
      );

      expect(policy.allowMutation, isTrue);
      expect(policy.usesAuthoritativeLateFee, isTrue);
      expect(policy.message, isNull);
    });

    test('sin autoridad y venta con condonacion conocida se bloquea', () {
      final policy = evaluateLateFeeMutationPolicy(
        authority: const LateFeeAuthority.unavailable(reason: 'sin red'),
        knownSaleHasWaiver: true,
      );

      expect(policy.allowMutation, isFalse);
      expect(policy.usesAuthoritativeLateFee, isFalse);
      expect(policy.message, isNotNull);
    });

    test('sin autoridad y venta sin condonacion mantiene el offline actual', () {
      final policy = evaluateLateFeeMutationPolicy(
        authority: const LateFeeAuthority.unavailable(reason: 'sin red'),
        knownSaleHasWaiver: false,
      );

      expect(policy.allowMutation, isTrue);
      expect(policy.usesAuthoritativeLateFee, isFalse);
      expect(policy.message, isNotNull);
    });
  });
}
