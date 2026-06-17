import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../data/payments_repository.dart';
import '../domain/payment_draft.dart';
import '../domain/payment_sale_context.dart';
import '../domain/payment_sale_option.dart';

class PaymentsController extends ChangeNotifier {
  PaymentsController({required PaymentsRepository paymentsRepository})
    : _paymentsRepository = paymentsRepository;

  final PaymentsRepository _paymentsRepository;
  bool _isDisposed = false;

  bool isLoading = false;
  bool isSaving = false;
  FriendlyErrorMessage? loadError;
  String defaultPaymentMethod = 'efectivo';
  List<PaymentSaleOption> activeSales = const [];
  PaymentSaleContext? selectedContext;
  int? selectedSaleId;

  Future<void> load({int? preferredSaleId}) async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      defaultPaymentMethod = await _paymentsRepository
          .fetchDefaultPaymentMethod();
      if (_isDisposed) {
        return;
      }

      activeSales = await _paymentsRepository.fetchActiveSales();
      if (_isDisposed) {
        return;
      }

      if (activeSales.isEmpty) {
        selectedSaleId = null;
        selectedContext = null;
      } else {
        selectedSaleId = _resolvePreferredSaleId(preferredSaleId);
        selectedContext = await _paymentsRepository.fetchSaleContext(
          selectedSaleId!,
        );
        if (_isDisposed) {
          return;
        }
      }
    } catch (error) {
      loadError = FriendlyErrorMessages.moduleLoad('pagos', error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectSale(int saleId) async {
    selectedSaleId = saleId;
    notifyListeners();

    try {
      loadError = null;
      selectedContext = await _paymentsRepository.fetchSaleContext(saleId);
      if (_isDisposed) {
        return;
      }
    } catch (error) {
      selectedContext = null;
      loadError = FriendlyErrorMessages.recoverable(
        action: 'cargar la venta seleccionada',
        module: 'pagos',
        error: error,
      );
    } finally {
      notifyListeners();
    }
  }

  Future<String?> registerPayment(PaymentDraft draft) async {
    isSaving = true;
    notifyListeners();

    try {
      await _paymentsRepository.registerPayment(draft);
      if (_isDisposed) {
        return null;
      }

      await load(preferredSaleId: draft.saleId);
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'registrar el pago',
        error,
        module: 'pagos',
      );
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> deletePayment({
    required int paymentId,
    int? preferredSaleId,
  }) async {
    isSaving = true;
    notifyListeners();

    try {
      await _paymentsRepository.deletePayment(paymentId);
      if (_isDisposed) {
        return null;
      }

      await load(preferredSaleId: preferredSaleId ?? selectedSaleId);
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'anular el pago',
        error,
        module: 'pagos',
      );
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  int _resolvePreferredSaleId(int? preferredSaleId) {
    if (preferredSaleId != null &&
        activeSales.any((sale) => sale.saleId == preferredSaleId)) {
      return preferredSaleId;
    }

    if (selectedSaleId != null &&
        activeSales.any((sale) => sale.saleId == selectedSaleId)) {
      return selectedSaleId!;
    }

    return activeSales.first.saleId;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
