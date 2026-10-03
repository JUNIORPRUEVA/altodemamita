import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../data/payments_repository.dart';
import '../domain/payment_draft.dart';
import '../domain/payment_sale_context.dart';
import '../domain/payment_sale_option.dart';
import '../domain/payment_work_queue.dart';
import '../domain/settlement_quote.dart';

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
  final Map<int, PaymentSaleContext> _contextCache =
      <int, PaymentSaleContext>{};
  static PaymentWorkQueue? _lastGoodWorkQueue;
  static List<PaymentSaleOption> _lastGoodActiveSales =
      const <PaymentSaleOption>[];
  static PaymentSaleContext? _lastGoodSelectedContext;
  static int? _lastGoodSelectedSaleId;
  int _loadGeneration = 0;

  /// Resultados de la busqueda autoritativa (PostgreSQL) del modulo Pagos.
  ///
  /// Es independiente de la work queue y de la primera pagina: una venta con
  /// cuotas futuras, solo-inicial o saldada tambien aparece aqui.
  List<PaymentSaleOption> searchResults = const [];
  bool isSearching = false;
  FriendlyErrorMessage? searchError;
  int _searchGeneration = 0;
  static const Duration _searchTimeout = Duration(seconds: 8);

  /// Busca ventas en el backend (autoridad) por nombre, cedula, telefono,
  /// solar o referencia. Protegida con generation token contra respuestas
  /// fuera de orden.
  Future<void> searchSales(String query) async {
    final trimmed = query.trim();
    final generation = ++_searchGeneration;

    if (trimmed.length < 2) {
      searchResults = const [];
      isSearching = false;
      searchError = null;
      notifyListeners();
      return;
    }

    final localMatches = _localSearchMatches(trimmed);

    isSearching = true;
    searchResults = localMatches;
    searchError = null;
    notifyListeners();

    try {
      final results = await _paymentsRepository
          .searchSales(trimmed)
          .timeout(_searchTimeout);
      if (_isDisposed || generation != _searchGeneration) {
        return;
      }
      searchResults = _mergeSearchResults(localMatches, results);
    } catch (error) {
      if (_isDisposed || generation != _searchGeneration) {
        return;
      }
      searchResults = localMatches;
      searchError = localMatches.isEmpty
          ? FriendlyErrorMessages.recoverable(
              action: 'buscar la venta',
              module: 'pagos',
              error: error,
            )
          : null;
    } finally {
      if (!_isDisposed && generation == _searchGeneration) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchGeneration++;
    searchResults = const [];
    isSearching = false;
    searchError = null;
    notifyListeners();
  }

  Future<void> load({int? preferredSaleId}) async {
    final generation = ++_loadGeneration;
    loadError = null;
    refreshFailed = false;
    if (workQueue == null && activeSales.isEmpty) {
      if (_lastGoodWorkQueue != null || _lastGoodActiveSales.isNotEmpty) {
        workQueue = _lastGoodWorkQueue;
        activeSales = _lastGoodActiveSales;
        selectedContext = _lastGoodSelectedContext;
        selectedSaleId = preferredSaleId ?? _lastGoodSelectedSaleId;
        if (selectedContext != null) {
          _contextCache[selectedContext!.sale.saleId] = selectedContext!;
        }
        isLoading = false;
        isRefreshing = false;
        isSelectedContextLoading = false;
        notifyListeners();
      } else {
        isLoading = true;
        isRefreshing = false;
        isSelectedContextLoading = false;
        notifyListeners();
      }
      // Cache-first: mostrar la ultima cola valida antes de la red.
      final cachedQueue = await _paymentsRepository.fetchCachedWorkQueue();
      if (_isDisposed || generation != _loadGeneration) {
        return;
      }
      if (cachedQueue != null && cachedQueue.entries.isNotEmpty) {
        workQueue = cachedQueue;
        activeSales = _salesFromWorkQueue(cachedQueue);
        selectedSaleId = _resolvePreferredSaleId(preferredSaleId);
        isLoading = false;
        isRefreshing = false;
        _seedSelectedContextFromMemory(selectedSaleId!);
        _rememberLastGoodState();
        notifyListeners();

        isSelectedContextLoading = selectedContext == null;
        await _seedSelectedContextFromCache(selectedSaleId!, generation);
        if (!_isDisposed && generation == _loadGeneration) {
          isSelectedContextLoading = false;
          _rememberLastGoodState();
          notifyListeners();
        }
      }
    }
    final hasVisibleData = workQueue != null || activeSales.isNotEmpty;
    isLoading = !hasVisibleData;
    isRefreshing = false;
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
        if (selectedContext != null) {
          activeSales = [selectedContext!.sale];
          selectedSaleId = selectedContext!.sale.saleId;
        } else {
          selectedSaleId = null;
          selectedContext = null;
        }
      } else {
        // La lista ya esta disponible: dejamos de bloquear el modulo y
        // cargamos el detalle financiero de la venta en segundo plano.
        selectedSaleId = _resolvePreferredSaleId(preferredSaleId);
        isLoading = false;
        isSelectedContextLoading = true;
        await _seedSelectedContextFromCache(selectedSaleId!, generation);
        notifyListeners();
        final context = await _paymentsRepository.fetchSaleContext(
          selectedSaleId!,
        );
        if (_isDisposed || generation != _loadGeneration) {
          return;
        }
        if (context != null) {
          selectedContext = context;
          _contextCache[selectedSaleId!] = context;
        }
      }
      _rememberLastGoodState();
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

  Future<void> selectSale(int saleId, {PaymentSaleOption? previewSale}) async {
    final generation = ++_loadGeneration;
    _cancelSearch();
    selectedSaleId = saleId;
    isSelectedContextLoading = true;
    await _seedSelectedContextFromCache(saleId, generation);
    if (!_isDisposed &&
        generation == _loadGeneration &&
        selectedContext == null &&
        previewSale != null) {
      selectedContext = PaymentSaleContext(
        sale: previewSale,
        monthlyInterest: 0,
        installments: const [],
        history: const [],
      );
    }
    notifyListeners();

    try {
      loadError = null;
      final context = await _paymentsRepository.fetchSaleContext(saleId);
      if (_isDisposed || generation != _loadGeneration) {
        return;
      }
      selectedContext = context;
      if (context != null) {
        _contextCache[saleId] = context;
        _rememberLastGoodState();
      }
    } catch (error) {
      if (selectedContext?.sale.saleId != saleId) {
        selectedContext = null;
      }
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

  void _cancelSearch() {
    _searchGeneration++;
    searchResults = const [];
    isSearching = false;
    searchError = null;
  }

  List<PaymentSaleOption> _localSearchMatches(String query) {
    final normalizedQuery = _normalizeSearchValue(query);
    final lowerQuery = query.toLowerCase();
    final source = activeSales.isNotEmpty ? activeSales : _lastGoodActiveSales;

    return source
        .where((sale) {
          final haystack = [
            sale.clientName,
            sale.clientPhone,
            sale.clientDocumentId,
            sale.lotDisplayCode,
            '#${sale.saleId}',
          ].join(' ').toLowerCase();
          final normalizedHaystack = _normalizeSearchValue(
            [
              sale.clientPhone,
              sale.clientDocumentId,
              sale.lotDisplayCode,
              '${sale.saleId}',
            ].join(' '),
          );
          return haystack.contains(lowerQuery) ||
              (normalizedQuery.isNotEmpty &&
                  normalizedHaystack.contains(normalizedQuery));
        })
        .toList(growable: false);
  }

  List<PaymentSaleOption> _mergeSearchResults(
    List<PaymentSaleOption> localMatches,
    List<PaymentSaleOption> remoteResults,
  ) {
    final merged = <PaymentSaleOption>[];
    final seenSaleIds = <int>{};
    for (final sale in [...localMatches, ...remoteResults]) {
      if (seenSaleIds.add(sale.saleId)) {
        merged.add(sale);
      }
    }
    return merged;
  }

  String _normalizeSearchValue(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }

  Future<void> reloadWorkQueue({String state = 'collectible'}) async {
    if (!_paymentsRepository.usesBackendMode) {
      return;
    }
    final generation = ++_loadGeneration;
    if (workQueue == null && activeSales.isEmpty) {
      if (_lastGoodWorkQueue != null || _lastGoodActiveSales.isNotEmpty) {
        workQueue = _lastGoodWorkQueue;
        activeSales = _lastGoodActiveSales;
        selectedSaleId ??= _lastGoodSelectedSaleId;
        selectedContext = _lastGoodSelectedContext;
      }
    }
    isLoading = workQueue == null && activeSales.isEmpty;
    isRefreshing = false;
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
      _rememberLastGoodState();
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

      await _refreshAfterFinancialChange(draft.saleId);
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

  Future<({SettlementQuote? quote, String? error})> fetchSettlementQuote(
    int saleId,
  ) async {
    try {
      final quote = await _paymentsRepository.fetchSettlementQuote(saleId);
      return (quote: quote, error: null);
    } catch (error) {
      return (
        quote: null,
        error: FriendlyErrorMessages.forOperation(
          'calcular la liquidacion total',
          error,
          module: 'pagos',
        ),
      );
    }
  }

  Future<String?> settleSale({
    required int saleId,
    required SettlementQuote quote,
    required String paymentMethod,
  }) async {
    isSaving = true;
    notifyListeners();

    try {
      await _paymentsRepository.settleSale(
        saleId: saleId,
        quote: quote,
        paymentMethod: paymentMethod,
      );
      if (_isDisposed) {
        return null;
      }
      await _refreshAfterFinancialChange(saleId);
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'saldar la deuda total',
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
    String? reason,
    String? adminAuthorizationId,
  }) async {
    isSaving = true;
    notifyListeners();

    try {
      await _paymentsRepository.deletePayment(
        paymentId,
        reason: reason,
        adminAuthorizationId: adminAuthorizationId,
      );
      if (_isDisposed) {
        return null;
      }

      await _refreshAfterFinancialChange(preferredSaleId ?? selectedSaleId);
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

  /// Solicita al backend una autorizacion administrativa de un solo uso para
  /// anular un pago. Devuelve `authorizationId` o el mensaje de error.
  Future<({String? authorizationId, String? error})> requestAdminAuthorization({
    required int paymentId,
    required String email,
    required String password,
  }) async {
    try {
      final authorizationId = await _paymentsRepository
          .authorizePaymentCancellation(
            paymentId: paymentId,
            email: email,
            password: password,
          );
      return (authorizationId: authorizationId, error: null);
    } catch (error) {
      return (
        authorizationId: null,
        error: FriendlyErrorMessages.forOperation(
          'solicitar la autorizacion del administrador',
          error,
          module: 'pagos',
        ),
      );
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

  Future<void> _seedSelectedContextFromCache(int saleId, int generation) async {
    if (_seedSelectedContextFromMemory(saleId)) {
      return;
    }
    final cachedContext = await _paymentsRepository.fetchCachedSaleContext(
      saleId,
    );
    if (_isDisposed || generation != _loadGeneration) {
      return;
    }
    if (cachedContext != null) {
      selectedContext = cachedContext;
      _contextCache[saleId] = cachedContext;
    } else {
      selectedContext = null;
    }
  }

  bool _seedSelectedContextFromMemory(int saleId) {
    final memoryContext = _contextCache[saleId];
    if (memoryContext != null) {
      selectedContext = memoryContext;
      return true;
    }
    final lastContext = _lastGoodSelectedContext;
    if (lastContext != null && lastContext.sale.saleId == saleId) {
      selectedContext = lastContext;
      _contextCache[saleId] = lastContext;
      return true;
    }
    return false;
  }

  Future<void> _refreshAfterFinancialChange(int? saleId) async {
    if (saleId == null) {
      await load(preferredSaleId: selectedSaleId);
      return;
    }
    final generation = ++_loadGeneration;
    selectedSaleId = saleId;
    isSelectedContextLoading = true;
    isRefreshing = false;
    notifyListeners();

    try {
      final contextFuture = _paymentsRepository.fetchSaleContext(saleId);
      final queueFuture = _paymentsRepository.usesBackendMode
          ? _paymentsRepository.fetchWorkQueue()
          : Future<PaymentWorkQueue?>.value(null);

      final context = await contextFuture;
      if (_isDisposed || generation != _loadGeneration) {
        return;
      }
      selectedContext = context;
      if (context != null) {
        _contextCache[saleId] = context;
      }

      final nextQueue = await queueFuture;
      if (_isDisposed || generation != _loadGeneration) {
        return;
      }
      if (nextQueue != null) {
        workQueue = nextQueue;
        activeSales = _salesFromWorkQueue(nextQueue);
        if (context != null &&
            !activeSales.any((sale) => sale.saleId == context.sale.saleId)) {
          activeSales = [context.sale, ...activeSales];
        }
      } else {
        activeSales = await _paymentsRepository.fetchActiveSales();
      }
      _rememberLastGoodState();
    } catch (error) {
      refreshFailed = true;
    } finally {
      if (!_isDisposed && generation == _loadGeneration) {
        isLoading = false;
        isSelectedContextLoading = false;
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  void _rememberLastGoodState() {
    _lastGoodWorkQueue = workQueue;
    _lastGoodActiveSales = activeSales;
    _lastGoodSelectedContext = selectedContext;
    _lastGoodSelectedSaleId = selectedSaleId;
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
