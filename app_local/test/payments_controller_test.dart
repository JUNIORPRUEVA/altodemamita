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

  test(
    'selectSale muestra contexto cacheado mientras refresca en segundo plano',
    () async {
      final fetchGate = Completer<void>();
      final controller = PaymentsController(
        paymentsRepository: FakePaymentsRepository(
          fetchContextGate: fetchGate,
          cachedContextOverride: FakePaymentsRepository.cachedContext,
        ),
      );

      final selectionFuture = controller.selectSale(1);
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedSaleId, 1);
      expect(controller.selectedContext, FakePaymentsRepository.cachedContext);
      expect(controller.isSelectedContextLoading, isTrue);

      fetchGate.complete();
      await selectionFuture;

      expect(controller.selectedContext, FakePaymentsRepository.remoteContext);
      expect(controller.isSelectedContextLoading, isFalse);
    },
  );

  test(
    'selectSale usa vista previa de busqueda antes del contexto remoto',
    () async {
      final fetchGate = Completer<void>();
      final previewSale = FakePaymentsRepository.searchPreviewSale;
      final controller = PaymentsController(
        paymentsRepository: FakePaymentsRepository(fetchContextGate: fetchGate),
      );

      final selectionFuture = controller.selectSale(
        previewSale.saleId,
        previewSale: previewSale,
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedSaleId, previewSale.saleId);
      expect(controller.selectedContext?.sale, previewSale);
      expect(controller.isSelectedContextLoading, isTrue);

      fetchGate.complete();
      await selectionFuture;

      expect(controller.selectedContext, FakePaymentsRepository.remoteContext);
      expect(controller.isSelectedContextLoading, isFalse);
    },
  );
}

class FakePaymentsRepository extends PaymentsRepository {
  FakePaymentsRepository({
    this.loadGate,
    this.registerGate,
    this.deleteGate,
    this.fetchContextGate,
    this.cachedContextOverride,
  });

  final Completer<void>? loadGate;
  final Completer<void>? registerGate;
  final Completer<void>? deleteGate;
  final Completer<void>? fetchContextGate;
  final PaymentSaleContext? cachedContextOverride;

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

  static const PaymentSaleContext remoteContext = PaymentSaleContext(
    sale: _sale,
    monthlyInterest: 1,
    installments: [],
    history: [],
  );
  static const PaymentSaleContext cachedContext = PaymentSaleContext(
    sale: _sale,
    monthlyInterest: 0.5,
    installments: [],
    history: [],
  );
  static const PaymentSaleOption searchPreviewSale = PaymentSaleOption(
    saleId: 9001,
    clientId: 7001,
    clientName: 'Cliente buscado',
    clientDocumentId: '001-0000000-9',
    clientPhone: '8095550102',
    lotDisplayCode: 'M9-S1',
    pendingBalance: 10000,
    requiredInitialPayment: 5000,
    paidInitialPayment: 5000,
    pendingInitialPayment: 0,
    status: 'activa',
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
  Future<PaymentSaleContext?> fetchCachedSaleContext(int saleId) async =>
      cachedContextOverride;

  @override
  Future<PaymentSaleContext?> fetchSaleContext(int saleId) async {
    final gate = fetchContextGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    return remoteContext;
  }

  @override
  Future<void> registerPayment(PaymentDraft draft) async {
    final gate = registerGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
  }

  @override
  Future<void> deletePayment(
    int paymentId, {
    String? reason,
    String? adminAuthorizationId,
  }) async {
    final gate = deleteGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
  }
}
