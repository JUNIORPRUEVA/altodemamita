import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_draft.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_context.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payments_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load no falla si el controller se dispone durante la carga', () async {
    final gate = Completer<void>();
    final controller = PaymentsController(
      paymentsRepository: FakePaymentsRepository(loadGate: gate),
    );

    final loadFuture = controller.load(preferredSaleId: 1);
    controller.dispose();
    gate.complete();

    await expectLater(loadFuture, completes);
  });

  test(
    'registerPayment no falla si el controller se dispone durante el guardado',
    () async {
      final gate = Completer<void>();
      final controller = PaymentsController(
        paymentsRepository: FakePaymentsRepository(registerGate: gate),
      );

      final registerFuture = controller.registerPayment(
        PaymentDraft(
          saleId: 1,
          paymentDate: DateTime(2026, 3, 28),
          amountPaid: 1500,
          paymentMethod: 'efectivo',
        ),
      );

      controller.dispose();
      gate.complete();

      await expectLater(registerFuture, completes);
    },
  );

  test(
    'deletePayment no falla si el controller se dispone durante el guardado',
    () async {
      final gate = Completer<void>();
      final controller = PaymentsController(
        paymentsRepository: FakePaymentsRepository(deleteGate: gate),
      );

      final deleteFuture = controller.deletePayment(
        paymentId: 1,
        preferredSaleId: 1,
      );

      controller.dispose();
      gate.complete();

      await expectLater(deleteFuture, completes);
    },
  );
}

class FakePaymentsRepository extends PaymentsRepository {
  FakePaymentsRepository({this.loadGate, this.registerGate, this.deleteGate});

  final Completer<void>? loadGate;
  final Completer<void>? registerGate;
  final Completer<void>? deleteGate;

  static const PaymentSaleOption _sale = PaymentSaleOption(
    saleId: 1,
    clientId: 1,
    clientName: 'Cliente Demo',
    clientDocumentId: '001-0000000-1',
    clientPhone: '8095550101',
    lotDisplayCode: 'M1-S1',
    pendingBalance: 25000,
    requiredInitialPayment: 5000,
    paidInitialPayment: 5000,
    pendingInitialPayment: 0,
    status: 'activa',
  );

  static const PaymentSaleContext _context = PaymentSaleContext(
    sale: _sale,
    monthlyInterest: 1,
    installments: [],
    history: [],
  );

  @override
  Future<String> fetchDefaultPaymentMethod() async {
    final gate = loadGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    return 'efectivo';
  }

  @override
  Future<List<PaymentSaleOption>> fetchActiveSales() async => const [_sale];

  @override
  Future<PaymentSaleContext?> fetchSaleContext(int saleId) async => _context;

  @override
  Future<void> registerPayment(PaymentDraft draft) async {
    final gate = registerGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
  }

  @override
  Future<void> deletePayment(int paymentId) async {
    final gate = deleteGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
  }
}
