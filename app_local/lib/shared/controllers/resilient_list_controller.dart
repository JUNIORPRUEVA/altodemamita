import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';

/// Controlador base cache-first / stale-while-revalidate para listados de
/// modulos (clientes, solares, vendedores, etc.).
///
/// Replica la UX del modulo Ventas (P0):
/// - Muestra de inmediato la ultima lista valida (snapshot) si existe.
/// - Un refresh de la misma consulta NUNCA vacia la lista visible.
/// - Un refresh fallido con datos visibles = estado no bloqueante.
/// - La pantalla fatal SOLO aplica sin datos y con fallo de la carga inicial.
/// - "Vacio" SOLO se muestra tras una respuesta exitosa que lo confirme.
/// - Proteccion por generacion: una respuesta tardia no pisa datos nuevos.
class ResilientListController<T> extends ChangeNotifier {
  ResilientListController({
    required String moduleLabel,
    required Future<List<T>> Function(String query) fetch,
    Future<List<T>> Function()? fetchCache,
    List<T> Function(List<T> items, String query)? filterCache,
  }) : _moduleLabel = moduleLabel,
       _fetch = fetch,
       _fetchCache = fetchCache,
       _filterCache = filterCache;

  final String _moduleLabel;
  final Future<List<T>> Function(String query) _fetch;
  final Future<List<T>> Function()? _fetchCache;
  final List<T> Function(List<T> items, String query)? _filterCache;
  static final Map<String, _ListMemorySnapshot<Object?>> _lastGoodByScope = {};

  /// Carga inicial en curso SIN datos visibles (skeleton, jamas vacio).
  bool isLoading = false;

  /// Refresh de la misma consulta en curso CON datos visibles (no bloquea).
  bool isRefreshing = false;

  /// Datos visibles; el ultimo refresh autoritativo fallo (aviso no bloqueante).
  bool refreshFailed = false;

  /// La busqueda (query != '') fallo sin resultados que mostrar.
  bool searchFailed = false;

  /// Ultima consulta solicitada ('' = lista completa).
  String currentQuery = '';

  /// Error fatal: solo sin datos visibles y con fallo de la carga por defecto.
  FriendlyErrorMessage? loadError;

  /// Datos visibles actuales (corresponden a [_loadedQuery]).
  List<T> items = const [];

  bool _isDisposed = false;
  int _generation = 0;
  String _loadedQuery = '';

  bool get isDisposed => _isDisposed;
  String get _memoryKey => '${T.toString()}::$_moduleLabel::$currentQuery';

  /// True cuando la lista visible pertenece a la consulta actual.
  bool get hasVisibleData => items.isNotEmpty && _loadedQuery == currentQuery;

  Future<void> load({String? query}) async {
    if (_isDisposed) {
      return;
    }
    final generation = ++_generation;
    if (query != null) {
      currentQuery = query;
    }
    final scope = currentQuery;

    loadError = null;
    searchFailed = false;
    final hadVisible = _loadedQuery == scope && items.isNotEmpty;
    final memoryApplied = _restoreLastGood(scope);
    if (hadVisible) {
      isLoading = false;
      isRefreshing = false;
      refreshFailed = false;
    } else if (memoryApplied) {
      isLoading = false;
      isRefreshing = false;
      refreshFailed = false;
    } else {
      isLoading = true;
      isRefreshing = false;
      refreshFailed = false;
    }
    _notifyIfActive();

    // Cache-first bootstrap. Si el repositorio sabe filtrar el snapshot,
    // tambien se usa para busquedas: primer resultado local, red en background.
    if (!hadVisible && _fetchCache != null) {
      List<T>? cached;
      try {
        final rawCached = await _fetchCache();
        cached = scope.isEmpty || _filterCache == null
            ? rawCached
            : _filterCache(rawCached, scope);
      } catch (_) {
        cached = null;
      }
      if (_isDisposed || generation != _generation) {
        return;
      }
      if (cached != null && cached.isNotEmpty) {
        items = cached;
        _loadedQuery = scope;
        isLoading = false;
        isRefreshing = false;
        _rememberLastGood(scope, cached);
        _notifyIfActive();
      } else if (scope.isNotEmpty && _filterCache != null) {
        items = const [];
        _loadedQuery = scope;
        isLoading = false;
        isRefreshing = false;
        _notifyIfActive();
      }
    }

    List<T>? result;
    Object? error;
    try {
      result = await _fetch(scope);
    } catch (e) {
      error = e;
    }
    if (_isDisposed || generation != _generation) {
      return;
    }

    if (result != null) {
      items = result;
      _loadedQuery = scope;
      _rememberLastGood(scope, result);
      searchFailed = false;
      refreshFailed = false;
      isLoading = false;
      isRefreshing = false;
      _notifyIfActive();
    } else {
      final stillVisible = _loadedQuery == scope && items.isNotEmpty;
      isLoading = false;
      isRefreshing = false;
      if (stillVisible) {
        refreshFailed = true;
      } else if (scope.isNotEmpty) {
        searchFailed = true;
      } else {
        loadError = _noDataLoadFailure(error);
      }
      _notifyIfActive();
    }
  }

  /// Quita un item visible tras una eliminacion exitosa (sin recargar todo).
  void removeItemById(int Function(T item) idOf, int id) {
    items = items.where((item) => idOf(item) != id).toList(growable: false);
    _rememberLastGood(currentQuery, items);
    _notifyIfActive();
  }

  bool _restoreLastGood(String scope) {
    final snapshot = _lastGoodByScope[_memoryKey];
    if (snapshot == null || snapshot.items.isEmpty) {
      return false;
    }
    items = snapshot.items.cast<T>().toList(growable: false);
    _loadedQuery = scope;
    return true;
  }

  void _rememberLastGood(String scope, List<T> value) {
    if (_isDisposed || value.isEmpty) {
      return;
    }
    _lastGoodByScope['${T.toString()}::$_moduleLabel::$scope'] =
        _ListMemorySnapshot<Object?>(value.cast<Object?>());
  }

  FriendlyErrorMessage _noDataLoadFailure(Object? error) {
    final resolved = FriendlyErrorMessages.unexpected(error);
    final title = resolved.title.toLowerCase();
    final noConnection =
        title.contains('conexion') ||
        title.contains('servidor') ||
        title.contains('internet');
    if (noConnection) {
      return FriendlyErrorMessage(
        title: '$_moduleLabel no disponible por ahora',
        message: 'No pudimos actualizar $_moduleLabel porque no hay conexión.',
        details:
            'Tus datos están seguros. Revisa la conexión a internet y vuelve a intentarlo.',
        suggestions: const [
          'Verifica tu conexión a internet.',
          'Usa Reintentar cuando tengas conexión.',
        ],
      );
    }
    return FriendlyErrorMessage(
      title: 'No pudimos cargar $_moduleLabel',
      message:
          'No pudimos cargar $_moduleLabel en este momento. Tus datos están seguros.',
      details: resolved.details,
      suggestions: [
        'Usa Reintentar para volver a intentar.',
        ...resolved.suggestions.take(1),
      ],
    );
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

class _ListMemorySnapshot<T> {
  const _ListMemorySnapshot(this.items);

  final List<T> items;
}
