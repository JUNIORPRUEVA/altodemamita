import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../data/payments_repository.dart';
import '../domain/payment_draft.dart';
import '../domain/payment_sale_context.dart';
import '../domain/payment_sale_option.dart';
import '../domain/payment_work_queue.dart';

class PaymentsController extends ChangeNotifier {
  PaymentsController({required PaymentsRepository paymentsRepository})
    : _paymentsRepository = paymentsRepository;

  final PaymentsRepository _paymentsRepository;
  bool _isDisposed = false;

  bool isLoading = false;
  bool isSaving = false;
  bool isSelectedContextLoading = false;
  FriendlyErrorMessage? loadError;

  /// Con datos visibles y un refresh fallido (aviso no bloqueante).
  bool refreshFailed = false;

  /// Refresh de la misma vista en curso CON datos visibles (no bloquea).
  bool isRefreshing = false;
  String defaultPaymentMethod = 'efectivo';
  List<PaymentSaleOption> activeSales = const [];
  PaymentWorkQueue? workQueue;
  PaymentSaleContext? selectedContext;
  int? selectedSaleId;
  int _loadGeneration = 0;

  Future<void> load({int? preferredSaleId}) async {
    final generation = ++_loadGeneration;
    loadError = null;
    refreshFailed = false;
    if (workQueue == null && activeSales.isEmpty) {
      // Cache-first: mostrar la ultima cola valida antes de la red.
      final cachedQueue = await _paymentsRepository.fetchCachedWorkQueue();
      if (_isDisposed || generation != _loadGeneration) {
        return;
      }
      if (cachedQueue != null && cachedQueue.entries.isNotEmpty) {
        workQueue = cachedQueue;
        activeSales = _salesFromWorkQueue(cachedQueue);
      }
    }
    final hasVisibleData = workQueue != null || activeSales.isNotEmpty;
    isLoading = !hasVisibleData;
    isRefreshing = hasVisibleData;
    if (!hasVisibleData) {
      activeSales = const [];
      selectedContext = null;
      selectedSaleId = null;
    }
    notifyListeners();

    try {
      final defaultMethodFuture = _paymentsRepository
          .fetchDefaultPaymentMethod();
      final workQueueFuture = _paymentsRepository.usesBackendMode
          ? _paymentsRepository.fetchWorkQueue()
          : Future<PaymentWorkQueue?>.value(null);

      defaultPaymentMethod = await defaultMethodFuture;
      if (_isDisposed) {
        return;
      }

      workQueue = await workQueueFuture;
      if (_isDisposed || generation != _loadGeneration) {
        return;
      }

      if (workQueue != null) {
        activeSales = _salesFromWorkQueue(workQueue!);
      } else {
        activeSales = await _paymentsRepository.fetchActiveSales();
      }
      if (_isDisposed) {
        return;
      }

      if (activeSales.isEmpty) {
        selectedSaleId = null;
        selectedContext = null;
      } else {
        // La lista ya esta disponible: dejamos de bloquear el modulo y
        // cargamos el detalle financiero de la venta en segundo plano.
        selectedSaleId = _resolvePreferredSaleId(preferredSaleId);
        isLoading = false;
        isSelectedContextLoading = true;
        notifyListeners();
        selectedContext = await _paymentsRepository.fetchSaleContext(
          selectedSaleId!,
        );
        if (_isDisposed || generation != _loadGeneration) {
          return;
        }
      }
    } catch (error) {
      if (workQueue != null || activeSales.isNotEmpty) {
        refreshFailed = true;
      } else {
        loadError = FriendlyErrorMessages.moduleLoad('pagos', error);
      }
    } finally {
      if (!_isDisposed && generation == _loadGeneration) {
        isSelectedContextLoading = false;
        isLoading = false;
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectSale(int saleId) async {
    final generation = ++_loadGeneration;
    selectedSaleId = saleId;
    selectedContext = null;
    isSelectedContextLoading = true;
    notifyListeners();

    try {
      loadError = null;
      selectedContext = await _paymentsRepository.fetchSaleContext(saleId);
      if (_isDisposed || generation != _loadGeneration) {
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
      if (!_isDisposed && generation == _loadGeneration) {
        isSelectedContextLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> reloadWorkQueue({String state = 'collectible'}) async {
    if (!_paymentsRepository.usesBackendMode) {
      return;
    }
    final generation = ++_loadGeneration;
    isLoading = workQueue == null;
    isRefreshing = workQueue != null;
    loadError = null;
    notifyListeners();

    try {
      final nextQueue = await _paymentsRepository.fetchWorkQueue(state: state);
      if (_isDisposed || generation != _loadGeneration || nextQueue == null) {
        return;
      }
      workQueue = nextQueue;
      activeSales = _salesFromWorkQueue(nextQueue);
      if (activeSales.isNotEmpty &&
          (selectedSaleId == null ||
              !activeSales.any((sale) => sale.saleId == selectedSaleId))) {
        selectedSaleId = activeSales.first.saleId;
        isSelectedContextLoading = true;
        notifyListeners();
        selectedContext = await _paymentsRepository.fetchSaleContext(
          selectedSaleId!,
        );
      }
    } catch (error) {
      if (workQueue != null || activeSales.isNotEmpty) {
        refreshFailed = true;
      } else {
        loadError = FriendlyErrorMessages.moduleLoad('pagos', error);
      }
    } finally {
      if (!_isDisposed && generation == _loadGeneration) {
        isLoading = false;
        isSelectedContextLoading = false;
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  List<PaymentSaleOption> _salesFromWorkQueue(PaymentWorkQueue queue) {
    final byId = <int, PaymentSaleOption>{};
    for (final entry in queue.entries) {
      byId[entry.sale.saleId] = entry.sale;
    }
    return byId.values.toList(growable: false);
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
