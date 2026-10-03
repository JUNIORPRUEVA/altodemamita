import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../../clients/data/client_repository.dart';
import '../../clients/domain/client.dart';
import '../../lots/data/lot_repository.dart';
import '../../lots/domain/lot.dart';
import '../../settings/data/settings_repository.dart';
import '../data/sales_repository.dart';
import '../data/seller_repository.dart';
import '../domain/sale_defaults.dart';
import '../domain/sale_detail.dart';
import '../domain/sale_draft.dart';
import '../domain/sale_summary.dart';
import '../domain/seller.dart';

/// Última lista de ventas VÁLIDA del proceso, fuera de la pantalla.
///
/// POR QUÉ EXISTE
/// `app_shell` reconstruye la página al navegar, así que `SalesPage` crea un
/// `SalesController` nuevo cada vez: sin esto, volver a Ventas resetea la lista
/// a vacío y la pantalla queda en skeleton esperando a SQLite (que puede estar
/// tomado por el writer del sync durante 1-2 minutos).
///
/// Guarda las listas por alcance y conserva la lista completa como fallback:
/// al entrar con busqueda/filtro se puede pintar algo inmediato sin esperar I/O.
class SalesListMemoryCache {
  SalesListMemoryCache._();

  static final Map<String, List<SaleSummary>> _itemsByScope =
      <String, List<SaleSummary>>{};

  /// Lista memorizada para ese alcance (`''` = lista completa sin filtros).
  static List<SaleSummary> forScope(String scope) =>
      _itemsByScope[scope] ?? const [];

  static bool hasForScope(String scope) =>
      (_itemsByScope[scope] ?? const []).isNotEmpty;

  static void store(String scope, List<SaleSummary> items) {
    _itemsByScope[scope] = List<SaleSummary>.unmodifiable(items);
  }

  /// Se usa al cerrar sesión: la lista de un usuario no debe verse en otro.
  static void clear() {
    _itemsByScope.clear();
  }

  @visibleForTesting
  static void debugReset() => clear();
}

/// Ultimo detalle completo visto durante el proceso.
///
/// Complementa el cache SQLite: abrir un detalle repetido no debe tocar red ni
/// disco para pintar la primera vista. El refresh autoritativo sigue corriendo
/// en background y reemplaza estos datos si hay cambios.
class SalesDetailMemoryCache {
  SalesDetailMemoryCache._();

  static final Map<int, SaleDetail> _itemsBySaleId = <int, SaleDetail>{};

  static SaleDetail? get(int saleId) => _itemsBySaleId[saleId];

  static void store(SaleDetail detail) {
    final saleId = detail.sale.id;
    if (saleId == null || saleId <= 0) {
      return;
    }
    _itemsBySaleId[saleId] = detail;
  }

  static void remove(int saleId) {
    _itemsBySaleId.remove(saleId);
  }

  /// Se usa al cerrar sesión: detalles de un usuario no deben verse en otro.
  static void clear() {
    _itemsBySaleId.clear();
  }

  @visibleForTesting
  static void debugReset() => clear();
}

/// Controlador del modulo Ventas con UX cache-first / stale-while-revalidate.
///
/// Reglas P0:
/// - NUNCA destruir el ultimo estado valido porque empieza un refresh.
/// - Un refresh fallido conserva la lista visible (estado no bloqueante).
/// - La pantalla fatal de error SOLO aplica cuando no hay ningun dato usable y
///   la carga autoritativa inicial fallo.
/// - "No hay ventas" SOLO se muestra tras una respuesta autoritativa exitosa
///   que confirme vacio (o busqueda sin resultados).
/// - Una respuesta tardia (generation vieja) NUNCA pisa datos mas nuevos.
class SalesController extends ChangeNotifier {
  SalesController({
    required SalesRepository salesRepository,
    required ClientRepository clientRepository,
    required LotRepository lotRepository,
    required SellerRepository sellerRepository,
    required SettingsRepository settingsRepository,
  }) : _salesRepository = salesRepository,
       _clientRepository = clientRepository,
       _lotRepository = lotRepository,
       _sellerRepository = sellerRepository,
       _settingsRepository = settingsRepository;

  final SalesRepository _salesRepository;
  final ClientRepository _clientRepository;
  final LotRepository _lotRepository;
  final SellerRepository _sellerRepository;
  final SettingsRepository _settingsRepository;

  /// Carga inicial en curso SIN datos visibles aun (skeleton, jamas vacio).
  bool isLoading = false;

  /// Refresh de la misma consulta en curso CON datos visibles (no bloquea).
  bool isRefreshing = false;

  /// Datos visibles; el ultimo refresh autoritativo fallo (aviso no bloqueante).
  bool refreshFailed = false;

  /// La busqueda (query != '') fallo sin resultados que mostrar.
  bool searchFailed = false;

  bool isSaving = false;

  /// Ultima consulta solicitada ('' = lista completa).
  String currentQuery = '';

  /// Error fatal: solo cuando NO hay datos visibles y la carga por defecto
  /// (lista completa) fallo. Nunca se asigna si ya hay datos en pantalla.
  FriendlyErrorMessage? loadError;

  String? lastSaveErrorMessage;

  List<SaleSummary> sales = const [];
  List<Client> clients = const [];
  List<Lot> availableLots = const [];
  List<Seller> sellers = const [];
  SaleDefaults defaults = const SaleDefaults(
    downPaymentPercentage: 10,
    monthlyInterest: 1,
    installmentCount: 12,
  );

  bool _isDisposed = false;
  int _generation = 0;

  /// Consulta a la que corresponden realmente los datos de [sales].
  String _loadedQuery = '__none__';

  bool get isDisposed => _isDisposed;

  /// Filtro de clasificacion autoritativa. `null` = sin filtro.
  static const String fullyPaidFilter = 'fully_paid';
  static const Object _unchangedSettlementFilter = Object();

  String? _settlementFilter;
  String? get settlementFilter => _settlementFilter;
  bool get isFullyPaidFilter => _settlementFilter == fullyPaidFilter;

  /// Clave de alcance: consulta + filtro de clasificacion.
  String get _scopeKey => '$currentQuery|${_settlementFilter ?? ''}';

  /// True cuando la lista visible pertenece a la consulta actual.
  bool get hasVisibleData => sales.isNotEmpty && _loadedQuery == _scopeKey;

  Future<void> load({String? query, String? settlementFilter}) async {
    await _performLoad(query: query, settlementFilter: settlementFilter);
  }

  /// Activa o desactiva el filtro "Venta definitiva" preservando la busqueda.
  Future<void> toggleFullyPaidFilter() async {
    await _performLoad(
      settlementFilter: isFullyPaidFilter ? null : fullyPaidFilter,
    );
  }

  Future<void> _performLoad({
    String? query,
    Object? settlementFilter = _unchangedSettlementFilter,
  }) async {
    if (_isDisposed) {
      return;
    }
    final generation = ++_generation;
    if (query != null) {
      currentQuery = query;
    }
    if (!identical(settlementFilter, _unchangedSettlementFilter)) {
      _settlementFilter = settlementFilter as String?;
    }
    final scope = _scopeKey;
    final isUnfilteredScope = currentQuery.isEmpty && _settlementFilter == null;
    var hasLocalPreview = false;

    // ── Arranque visual ────────────────────────────────────────────────
    loadError = null;
    searchFailed = false;

    // Seed SINCRONO desde la última lista válida del proceso: al volver a
    // Ventas o al buscar, la pantalla pinta YA y el backend confirma despues.
    // PROHIBIDO el patrón clear-list + loading=true al reentrar.
    if (_loadedQuery != scope) {
      final memo = SalesListMemoryCache.forScope(scope).isNotEmpty
          ? SalesListMemoryCache.forScope(scope)
          : SalesListMemoryCache.forScope('');
      if (memo.isNotEmpty) {
        sales = SalesListMemoryCache.hasForScope(scope)
            ? memo
            : _salesRepository.filterSummaries(
                memo,
                query: currentQuery,
                settlementFilter: _settlementFilter,
              );
        _loadedQuery = scope;
        hasLocalPreview = true;
      }
    }

    final hasCurrentScope = _loadedQuery == scope;
    if (hasCurrentScope || hasLocalPreview) {
      // REFRESHING_WITH_DATA/PREVIEW: conservar lo visible (incluido vacio
      // local de busqueda) y refrescar en segundo plano.
      isLoading = false;
      isRefreshing = false;
      refreshFailed = false;
    } else {
      // LOADING_WITHOUT_DATA: skeleton (nunca "No hay ventas" durante carga).
      isLoading = true;
      isRefreshing = false;
      refreshFailed = false;
    }
    _notifyIfActive();

    // ── Cache-first bootstrap desde SQLite ─────────────────────────────
    if (!hasCurrentScope && !hasLocalPreview) {
      final cached = await _salesRepository.searchCachedList(
        query: currentQuery,
        settlementFilter: _settlementFilter,
      );
      if (_isDisposed || generation != _generation) {
        return;
      }
      if (cached.isNotEmpty ||
          currentQuery.isNotEmpty ||
          _settlementFilter != null) {
        sales = cached;
        _loadedQuery = scope;
        if (isUnfilteredScope && cached.isNotEmpty) {
          SalesListMemoryCache.store('', cached);
        }
        isLoading = false;
        isRefreshing = false;
        _notifyIfActive();
      }
    }

    // ── Fetch autoritativo (lista) + soporte en paralelo ───────────────
    final supportFuture = _refreshSupportData(generation);
    List<SaleSummary>? listResult;
    Object? listError;
    try {
      listResult = await _salesRepository.fetchAll(
        query: currentQuery,
        settlementFilter: _settlementFilter,
      );
    } catch (error) {
      listError = error;
    }
    if (_isDisposed || generation != _generation) {
      return;
    }

    if (listResult != null) {
      sales = currentQuery.trim().isEmpty
          ? listResult
          : _mergeBackendWithLocalPending(listResult, sales);
      _loadedQuery = scope;
      if (isUnfilteredScope) {
        SalesListMemoryCache.store('', listResult);
      }
      if (listResult.isNotEmpty) {
        SalesListMemoryCache.store(scope, sales);
      }
      searchFailed = false;
      refreshFailed = false;
      isLoading = false;
      isRefreshing = false;
      _notifyIfActive();
    } else {
      // ERROR_WITH_DATA: conservar lista; ERROR_WITHOUT_DATA solo fatal real.
      final stillVisible = _loadedQuery == scope && sales.isNotEmpty;
      isLoading = false;
      isRefreshing = false;
      if (stillVisible) {
        refreshFailed = true;
      } else if (currentQuery.isNotEmpty) {
        searchFailed = true;
      } else {
        loadError = _noDataLoadFailure(listError);
      }
      _notifyIfActive();
    }

    // Espera el soporte (clientes/solares/vendedores/parametros) para que el
    // flujo termine con el formulario listo; jamas falla la carga de la lista.
    await supportFuture;
    if (_isDisposed || generation != _generation) {
      return;
    }
    _notifyIfActive();
  }

  List<SaleSummary> _mergeBackendWithLocalPending(
    List<SaleSummary> backend,
    List<SaleSummary> localPreview,
  ) {
    if (localPreview.isEmpty) {
      return backend;
    }
    final byId = <int>{for (final sale in backend) sale.id};
    final merged = [...backend];
    for (final sale in localPreview) {
      if (!sale.isPendingSync || byId.contains(sale.id)) {
        continue;
      }
      byId.add(sale.id);
      merged.add(sale);
    }
    return List<SaleSummary>.unmodifiable(merged);
  }

  Future<void> _refreshSupportData(int generation) async {
    if (_isDisposed) {
      return;
    }
    try {
      final settingsFuture = _settingsRepository.fetchByKeysWithDefaults({
        SettingsRepository.saleDefaultDownPaymentKey: '10',
        SettingsRepository.saleDefaultMonthlyInterestKey: '1',
        SettingsRepository.saleDefaultInstallmentCountKey: '12',
      });
      final settings = await _guard(settingsFuture);
      final clients = await _guard(_clientRepository.fetchAll());
      final lots = await _guard(_lotRepository.fetchAvailable());
      final sellers = await _guard(_sellerRepository.getAll());
      if (_isDisposed || generation != _generation) {
        return;
      }
      if (clients != null) {
        this.clients = clients;
      }
      if (lots != null) {
        availableLots = lots;
      }
      if (sellers != null) {
        this.sellers = sellers;
      }
      if (settings != null) {
        defaults = SaleDefaults(
          downPaymentPercentage: _parseDouble(
            settings[SettingsRepository.saleDefaultDownPaymentKey]?.value,
            fallback: 10,
          ),
          monthlyInterest: _parseDouble(
            settings[SettingsRepository.saleDefaultMonthlyInterestKey]?.value,
            fallback: 1,
          ),
          installmentCount: _parseInt(
            settings[SettingsRepository.saleDefaultInstallmentCountKey]?.value,
            fallback: 12,
          ),
        );
      }
    } catch (_) {
      // El soporte del formulario es best-effort: conserva el ultimo estado
      // conocido y nunca derriba la lista de ventas.
    }
  }

  /// Devuelve [null] si la futura fallo (nunca lanza).
  Future<T?> _guard<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  FriendlyErrorMessage _noDataLoadFailure(Object? error) {
    final resolved = FriendlyErrorMessages.unexpected(error);
    final title = resolved.title.toLowerCase();
    final noConnection =
        title.contains('conexion') ||
        title.contains('servidor') ||
        title.contains('internet');
    if (noConnection) {
      return const FriendlyErrorMessage(
        title: 'Ventas no disponibles por ahora',
        message: 'No pudimos actualizar Ventas porque no hay conexión.',
        details:
            'Tus datos están seguros. Revisa la conexión a internet y vuelve a intentarlo.',
        suggestions: [
          'Verifica tu conexión a internet.',
          'Usa Reintentar cuando tengas conexión.',
        ],
      );
    }
    return FriendlyErrorMessage(
      title: 'No pudimos cargar Ventas',
      message:
          'No pudimos cargar las ventas en este momento. Tus datos están seguros.',
      details: resolved.details,
      suggestions: [
        'Usa Reintentar para volver a intentar.',
        ...resolved.suggestions.take(1),
      ],
    );
  }

  Future<int?> createSale(SaleDraft draft) async {
    if (_isDisposed) {
      return null;
    }
    isSaving = true;
    loadError = null;
    lastSaveErrorMessage = null;
    _notifyIfActive();
    try {
      final saleId = await _salesRepository.createSale(draft);
      await load(query: currentQuery);
      return saleId;
    } catch (error, stack) {
      debugPrint('[SALES][CREATE] ERROR $error');
      debugPrintStack(stackTrace: stack);
      lastSaveErrorMessage = FriendlyErrorMessages.forOperation(
        'guardar la venta',
        error,
        module: 'ventas',
      );
      return null;
    } finally {
      isSaving = false;
      _notifyIfActive();
    }
  }

  Future<String?> updateSale(int saleId, SaleDraft draft) async {
    if (_isDisposed) {
      return null;
    }
    isSaving = true;
    _notifyIfActive();
    try {
      await _salesRepository.updateSale(saleId, draft);
      await load(query: currentQuery);
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'actualizar la venta',
        error,
        module: 'ventas',
      );
    } finally {
      isSaving = false;
      _notifyIfActive();
    }
  }

  Future<String?> deleteSale(int saleId) async {
    if (_isDisposed) {
      return null;
    }
    isSaving = true;
    _notifyIfActive();
    try {
      await _salesRepository.deleteSale(saleId);
      SalesDetailMemoryCache.remove(saleId);
      _removeDeletedSaleFromView(saleId);
      unawaited(_reloadAfterDeleteInBackground());
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'eliminar la venta',
        error,
        module: 'ventas',
      );
    } finally {
      isSaving = false;
      _notifyIfActive();
    }
  }

  void _removeDeletedSaleFromView(int saleId) {
    sales = sales.where((sale) => sale.id != saleId).toList(growable: false);
  }

  Future<void> _reloadAfterDeleteInBackground() async {
    if (_isDisposed) {
      return;
    }
    try {
      await _performLoad(query: currentQuery);
    } catch (_) {
      // La eliminacion local ya se aplico; un reload posterior converge.
    } finally {
      _notifyIfActive();
    }
  }

  Future<SaleDetail?> fetchDetail(int saleId) {
    return _salesRepository.fetchDetail(saleId).then((detail) {
      if (detail != null) {
        SalesDetailMemoryCache.store(detail);
      }
      return detail;
    });
  }

  Future<SaleDetail?> fetchCachedDetail(int saleId) async {
    final memoryDetail = SalesDetailMemoryCache.get(saleId);
    if (memoryDetail != null) {
      return memoryDetail;
    }
    final cachedDetail = await _salesRepository.fetchCachedDetail(saleId);
    if (cachedDetail != null) {
      SalesDetailMemoryCache.store(cachedDetail);
    }
    return cachedDetail;
  }

  double _parseDouble(String? value, {required double fallback}) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? fallback;
  }

  int _parseInt(String? value, {required int fallback}) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return int.tryParse(value.trim()) ?? fallback;
  }

  void _notifyIfActive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
