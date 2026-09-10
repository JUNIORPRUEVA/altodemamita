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
  String _loadedQuery = '';

  bool get isDisposed => _isDisposed;

  /// Filtro de clasificacion autoritativa. `null` = sin filtro.
  static const String fullyPaidFilter = 'fully_paid';

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

  Future<void> _performLoad({String? query, String? settlementFilter}) async {
    if (_isDisposed) {
      return;
    }
    final generation = ++_generation;
    if (query != null) {
      currentQuery = query;
    }
    if (settlementFilter != null || query != null) {
      _settlementFilter = settlementFilter;
    }
    final scope = _scopeKey;
    final isUnfilteredScope = currentQuery.isEmpty && _settlementFilter == null;

    // ── Arranque visual ────────────────────────────────────────────────
    loadError = null;
    searchFailed = false;
    final hadVisible = _loadedQuery == scope && sales.isNotEmpty;
    if (hadVisible) {
      // REFRESHING_WITH_DATA: conservar lista y refrescar en segundo plano.
      isLoading = false;
      isRefreshing = true;
      refreshFailed = false;
    } else {
      // LOADING_WITHOUT_DATA: skeleton (nunca "No hay ventas" durante carga).
      isLoading = true;
      isRefreshing = false;
      refreshFailed = false;
    }
    _notifyIfActive();

    // ── Cache-first bootstrap (solo lista completa sin filtros) ────────
    if (!hadVisible && isUnfilteredScope) {
      final cached = await _salesRepository.fetchCachedList();
      if (_isDisposed || generation != _generation) {
        return;
      }
      if (cached.isNotEmpty) {
        sales = cached;
        _loadedQuery = scope;
        isLoading = false;
        isRefreshing = true;
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
      sales = listResult;
      _loadedQuery = scope;
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
    return _salesRepository.fetchDetail(saleId);
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
