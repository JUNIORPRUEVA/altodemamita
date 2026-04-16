import 'package:flutter/foundation.dart';

import '../../../../core/resilience/friendly_error_messages.dart';
import '../../data/receipt_repository.dart';
import '../../domain/receipt.dart';

class ReceiptController extends ChangeNotifier {
  final ReceiptRepository _receiptRepository;

  Receipt? _receipt;
  bool _isLoading = false;
  FriendlyErrorMessage? _loadError;

  ReceiptController({
    required ReceiptRepository receiptRepository,
  }) : _receiptRepository = receiptRepository;

  // Getters
  Receipt? get receipt => _receipt;
  bool get isLoading => _isLoading;
  FriendlyErrorMessage? get loadError => _loadError;
  bool get hasReceipt => _receipt != null;

  /// Carga un recibo específico por ID de pago
  Future<void> loadReceipt(int paymentId) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      _receipt = await _receiptRepository.fetchReceiptByPaymentId(paymentId);
      if (_receipt == null) {
        _loadError = FriendlyErrorMessages.moduleLoad(
          'recibo de pago',
          StateError('receipt_not_found'),
        );
      }
    } catch (error) {
      _loadError = FriendlyErrorMessages.moduleLoad('recibo de pago', error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpia el estado del controlador
  void clear() {
    _receipt = null;
    _loadError = null;
    _isLoading = false;
    notifyListeners();
  }
}
