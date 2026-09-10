import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/services/api_client.dart';
import '../core/services/owner_snapshot_cache.dart';
import '../core/models/owner_snapshot.dart';
import '../widgets/owner_drawer.dart';
import '../widgets/error_view.dart';
import '../widgets/desktop_detail_pane.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/documentation/documentation_page.dart';
import '../features/clients/clients_page.dart';
import '../features/lots/lots_page.dart';
import '../features/sales/sales_page.dart';
import '../features/global_search/global_search_detail_page.dart';
import '../features/global_search/global_search_dialog.dart';
import '../features/global_search/global_search_models.dart';
import '../features/global_search/global_search_results_page.dart';
import '../features/global_search/global_search_service.dart';
import '../features/payments/payments_page.dart';
import '../features/installments/installments_page.dart';
import '../features/sellers/sellers_page.dart';
import 'app_colors.dart';
import 'responsive.dart';

const List<String> _salesFilterOptions = [
  'Todas',
  'Activas',
  'Pendientes',
  'Pagadas',
  'Vencidas',
  'Hoy',
  'Esta semana',
  'Este mes',
];

const Map<OwnerModule, List<String>> _moduleFilterOptions = {
  OwnerModule.clients: ['Todos', 'Con ventas', 'Sin ventas', 'Con deuda'],
  OwnerModule.lots: ['Todos', 'Disponibles', 'Vendidos', 'Apartados'],
  OwnerModule.installments: ['Todas', 'Pendientes', 'Vencidas', 'Pagadas'],
  OwnerModule.sellers: ['Todos', 'Con ventas', 'Sin ventas'],
};

const double _desktopSidebarCollapsedWidth = 96;
const double _desktopSidebarExpandedWidth = 288;
const double _desktopDetailPaneWidth = 560;

/// Map an OwnerModule to its display icon.
IconData moduleIcon(OwnerModule module) {
  switch (module) {
    case OwnerModule.dashboard:
      return Icons.dashboard_outlined;
    case OwnerModule.clients:
      return Icons.people_alt_outlined;
    case OwnerModule.lots:
      return Icons.map_outlined;
    case OwnerModule.sales:
      return Icons.point_of_sale_outlined;
    case OwnerModule.installments:
      return Icons.event_note_outlined;
    case OwnerModule.payments:
      return Icons.payments_outlined;
    case OwnerModule.sellers:
      return Icons.badge_outlined;
    case OwnerModule.documentation:
      return Icons.menu_book_outlined;
  }
}

/// Main navigation shell for the Owner app.
///
/// Responsive: uses [NavigationBar] on mobile, [NavigationRail] on tablet/desktop.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.session, required this.onLogout});

  final AuthSession session;
  final Future<void> Function() onLogout;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final ApiClient _api = ApiClient(
    baseUrl,
    accessToken: widget.session.accessToken,
  );
  final OwnerSnapshotCache _cache = const OwnerSnapshotCache();
  final GlobalSearchService _globalSearch = const GlobalSearchService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _topBarSearchController = TextEditingController();
  final FocusNode _topBarSearchFocus = FocusNode();

  OwnerSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _topBarSearchOpen = false;
  OwnerModule _selected = OwnerModule.dashboard;
  DesktopDetailBuilder? _desktopDetailBuilder;
  Timer? _timer;
  Future<void>? _activeRefresh;

  // Search notifier for module pages
  final ValueNotifier<bool> _searchNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> _salesSearchQuery = ValueNotifier<String>('');
  final ValueNotifier<String> _salesFilter = ValueNotifier<String>('Todas');
  final ValueNotifier<String> _clientsSearchQuery = ValueNotifier<String>('');
  final ValueNotifier<String> _clientsFilter = ValueNotifier<String>('Todos');
  final ValueNotifier<String> _lotsSearchQuery = ValueNotifier<String>('');
  final ValueNotifier<String> _lotsFilter = ValueNotifier<String>('Todos');
  final ValueNotifier<String> _installmentsSearchQuery = ValueNotifier<String>(
    '',
  );
  final ValueNotifier<String> _installmentsFilter = ValueNotifier<String>(
    'Todas',
  );
  final ValueNotifier<String> _sellersSearchQuery = ValueNotifier<String>('');
  final ValueNotifier<String> _sellersFilter = ValueNotifier<String>('Todos');
  // Trigger notifier for opening filter sheet from AppBar menu
  final ValueNotifier<int> _filterTriggerNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedSnapshotThenRefresh();
    _timer = Timer.periodic(
      ownerRefreshInterval,
      (_) => _refresh(silent: true),
    );
  }

  Future<void> _loadCachedSnapshotThenRefresh() async {
    final cachedSnapshot = await _cache.read();
    if (!mounted) return;
    if (cachedSnapshot != null) {
      setState(() {
        _snapshot = cachedSnapshot;
        _loading = false;
        _error = null;
      });
      unawaited(_refresh(silent: true));
      return;
    }
    await _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _topBarSearchController.dispose();
    _topBarSearchFocus.dispose();
    _searchNotifier.dispose();
    _salesSearchQuery.dispose();
    _salesFilter.dispose();
    _clientsSearchQuery.dispose();
    _clientsFilter.dispose();
    _lotsSearchQuery.dispose();
    _lotsFilter.dispose();
    _installmentsSearchQuery.dispose();
    _installmentsFilter.dispose();
    _sellersSearchQuery.dispose();
    _sellersFilter.dispose();
    _filterTriggerNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh(silent: true));
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    final activeRefresh = _activeRefresh;
    if (activeRefresh != null) {
      return activeRefresh;
    }

    if (!silent) {
      setState(() => _loading = true);
    }
    final refresh = _performRefresh();
    _activeRefresh = refresh;
    refresh.whenComplete(() {
      if (identical(_activeRefresh, refresh)) {
        _activeRefresh = null;
      }
    });
    return refresh;
  }

  Future<void> _performRefresh() async {
    try {
      if (_snapshot == null) {
        final dashboardSnapshot = await _api.fetchDashboardSnapshot();
        if (!mounted) return;
        setState(() {
          _snapshot = dashboardSnapshot;
          _error = null;
        });
      }

      final snapshot = await _api.fetchSnapshot();
      unawaited(_cache.write(snapshot));
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectModule(OwnerModule module) {
    setState(() {
      _selected = module;
      _desktopDetailBuilder = null;
      _closeTopBarSearch();
    });
  }

  void _openDesktopDetail(DesktopDetailBuilder builder) {
    setState(() => _desktopDetailBuilder = builder);
  }

  void _closeDesktopDetail() {
    setState(() => _desktopDetailBuilder = null);
  }

  void _toggleSearch() {
    if (_usesTopBarSearch) {
      if (Responsive.isDesktop(context)) {
        _openModuleSearchDialog();
        return;
      }
      setState(() => _topBarSearchOpen = true);
      _topBarSearchFocus.requestFocus();
      return;
    }
    _searchNotifier.value = !_searchNotifier.value;
  }

  void _closeTopBarSearch() {
    _topBarSearchOpen = false;
    _topBarSearchController.clear();
    _activeSearchQuery.value = '';
    _topBarSearchFocus.unfocus();
  }

  /// Returns true when the current module is the Dashboard.
  bool get _isDashboard => _selected == OwnerModule.dashboard;
  bool get _usesTopBarSearch {
    return _selected == OwnerModule.sales ||
        _selected == OwnerModule.clients ||
        _selected == OwnerModule.lots ||
        _selected == OwnerModule.installments ||
        _selected == OwnerModule.sellers;
  }

  ValueNotifier<String> get _activeSearchQuery {
    return switch (_selected) {
      OwnerModule.sales => _salesSearchQuery,
      OwnerModule.clients => _clientsSearchQuery,
      OwnerModule.lots => _lotsSearchQuery,
      OwnerModule.installments => _installmentsSearchQuery,
      OwnerModule.sellers => _sellersSearchQuery,
      _ => _salesSearchQuery,
    };
  }

  ValueNotifier<String> get _activeFilter {
    return switch (_selected) {
      OwnerModule.sales => _salesFilter,
      OwnerModule.clients => _clientsFilter,
      OwnerModule.lots => _lotsFilter,
      OwnerModule.installments => _installmentsFilter,
      OwnerModule.sellers => _sellersFilter,
      _ => _salesFilter,
    };
  }

  List<String> get _activeFilterOptions {
    if (_selected == OwnerModule.sales) return _salesFilterOptions;
    return _moduleFilterOptions[_selected] ?? const [];
  }

  void _openFilterSheet() {
    // Trigger the filter sheet in the current module page via notifier
    _filterTriggerNotifier.value++;
  }

  Future<void> _openModuleSearchDialog() async {
    final query = await showDialog<String?>(
      context: context,
      builder: (_) => _ModuleSearchDialog(
        moduleTitle: _selected.title,
        initialQuery: _activeSearchQuery.value,
      ),
    );
    if (query == null) return;
    _activeSearchQuery.value = query.trim();
  }

  Future<void> _openGlobalSearch() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => const GlobalSearchDialog(),
    );
    if (query == null) return;

    try {
      final needsFullSnapshot =
          _snapshot == null ||
          (_snapshot!.clients.isEmpty &&
              _snapshot!.lots.isEmpty &&
              _snapshot!.sales.isEmpty);
      if (needsFullSnapshot) {
        await _refresh();
      }
      if (!mounted) return;

      _showSearchingDialog();
      await Future<void>.delayed(const Duration(milliseconds: 180));

      final snapshot = _snapshot;
      final results = snapshot == null
          ? const <GlobalSearchResult>[]
          : _globalSearch.search(snapshot, query);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (results.isEmpty) {
        _showNoResults(query);
        return;
      }

      if (results.length == 1) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GlobalSearchDetailPage(result: results.first),
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              GlobalSearchResultsPage(query: query.trim(), results: results),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop();
      _showSearchError();
    }
  }

  void _showSearchingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(width: 14),
                Text(
                  'Buscando información...',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNoResults(String query) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sin resultados'),
          content: Text(
            'No encontramos información relacionada con "$query". Revisa el dato e intenta nuevamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _showSearchError() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('No se pudo buscar'),
          content: const Text(
            'Ocurrió un problema consultando la información. Intenta nuevamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(context, isDesktop, isMobile),
      drawer: isMobile ? _buildDrawer() : null,
      floatingActionButton: _isDashboard
          ? _GlobalSearchFab(onPressed: _openGlobalSearch)
          : null,
      body: SafeArea(
        bottom: false,
        child: DesktopDetailScope(
          enabled: isDesktop,
          open: _openDesktopDetail,
          close: _closeDesktopDetail,
          child: isDesktop
              ? _buildDesktopBody()
              : Row(
                  children: [
                    if (!isMobile) _buildNavigationRail(),
                    Expanded(child: _buildBody()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDesktopBody() {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(
              left: _desktopSidebarCollapsedWidth,
              right: _desktopDetailBuilder == null
                  ? 16
                  : _desktopDetailPaneWidth,
              top: 12,
              bottom: 12,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.045),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _buildBody(),
              ),
            ),
          ),
        ),
        if (_desktopDetailBuilder != null)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: _desktopDetailPaneWidth,
            child: _DesktopDetailPanel(
              onClose: _closeDesktopDetail,
              child: _desktopDetailBuilder!(),
            ),
          ),
        Positioned(top: 0, left: 0, bottom: 0, child: _buildNavigationRail()),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isDesktop,
    bool isMobile,
  ) {
    return AppBar(
      toolbarHeight: isMobile ? 66 : 72,
      // --- Leading: drawer button on mobile (only on Dashboard) ---
      leading: _topBarSearchOpen && _usesTopBarSearch
          ? _SearchCloseButton(
              onPressed: () {
                setState(_closeTopBarSearch);
              },
            )
          : isMobile
          ? (_isDashboard
                ? _MenuButton(
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  )
                : _BackButton(
                    onPressed: () => _selectModule(OwnerModule.dashboard),
                  ))
          : null,

      // --- Title ---
      title: _topBarSearchOpen && _usesTopBarSearch
          ? _TopBarSearchField(
              controller: _topBarSearchController,
              focusNode: _topBarSearchFocus,
              hintText: 'Buscar ${_selected.title.toLowerCase()}...',
              onChanged: (value) => _activeSearchQuery.value = value,
            )
          : _isDashboard
          ? Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: const Icon(
                    Icons.space_dashboard_outlined,
                    size: 20,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Panel',
                        style: TextStyle(
                          fontSize: isMobile ? 20 : 22,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Resumen del negocio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 11.5 : 12,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    moduleIcon(_selected),
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _selected.title,
                  style: TextStyle(
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),

      // --- Actions ---
      actions: [
        // Search button for non-Dashboard modules
        if (!_isDashboard && !_topBarSearchOpen)
          isDesktop
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: _toggleSearch,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Buscar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.borderLight),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _toggleSearch,
                  icon: Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                  tooltip: 'Buscar',
                  splashRadius: 22,
                ),
        if (_usesTopBarSearch && !_topBarSearchOpen)
          PopupMenuButton<String>(
            tooltip: 'Filtrar',
            icon: const Icon(
              Icons.tune_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            onSelected: (value) => _activeFilter.value = value,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.borderLight),
            ),
            itemBuilder: (_) => _activeFilterOptions.map((filter) {
              final selected = _activeFilter.value == filter;
              return PopupMenuItem<String>(
                value: filter,
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      filter,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        // More options menu (for non-Dashboard modules)
        if (!_isDashboard && !_usesTopBarSearch && !_topBarSearchOpen)
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            icon: Icon(
              Icons.more_vert_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            onSelected: (value) {
              switch (value) {
                case 'filter':
                  // Open filter sheet from the current module page
                  _openFilterSheet();
                  break;
                case 'refresh':
                  _refresh();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'filter',
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: AppColors.accentBlue,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Filtrar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: AppColors.accentGreen,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Actualizar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        // Refresh button (only on Dashboard)
        if (_isDashboard)
          _TopBarIconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
          ),
        _TopBarIconButton(
          onPressed: () => unawaited(widget.onLogout()),
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Cerrar sesion',
        ),
        const SizedBox(width: 10),
      ],

      // --- Styling ---
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: AppColors.surface.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: AppColors.borderLight, width: 1),
      ),
    );
  }

  Widget _buildDrawer() {
    return OwnerDrawer(
      selected: _selected,
      onSelected: (module) {
        Navigator.of(context).pop();
        _selectModule(module);
      },
    );
  }

  Widget _buildNavigationRail() {
    return _DesktopSideNav(selected: _selected, onSelected: _selectModule);
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'Preparando la información...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null && _snapshot == null) {
      return ErrorView(error: _error, onRetry: () => _refresh());
    }
    final snapshot = _snapshot!;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Constrain content width on wide screens for readability
        final contentWidth = constraints.maxWidth > 900
            ? 900.0
            : constraints.maxWidth;
        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) _RefreshWarning(onRetry: () => _refresh()),
                Expanded(child: _buildPageContent(snapshot)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageContent(OwnerSnapshot snapshot) {
    if (_loading &&
        _selected != OwnerModule.dashboard &&
        _moduleItems(snapshot, _selected).isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Cargando registros...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return switch (_selected) {
      OwnerModule.dashboard => DashboardPage(
        snapshot: snapshot,
        onOpenModule: _selectModule,
      ),
      OwnerModule.clients => ClientsPage(
        items: snapshot.clients,
        searchQueryNotifier: _clientsSearchQuery,
        filterNotifier: _clientsFilter,
        allSales: snapshot.sales,
        allLots: snapshot.lots,
      ),
      OwnerModule.lots => LotsPage(
        items: snapshot.lots,
        searchQueryNotifier: _lotsSearchQuery,
        filterNotifier: _lotsFilter,
        allSales: snapshot.sales,
        allClients: snapshot.clients,
      ),
      OwnerModule.sales => SalesPage(
        items: snapshot.sales,
        searchQueryNotifier: _salesSearchQuery,
        filterNotifier: _salesFilter,
        allInstallments: snapshot.installments,
        allPayments: snapshot.payments,
        allClients: snapshot.clients,
        allSellers: snapshot.sellers,
        allLots: snapshot.lots,
      ),
      OwnerModule.installments => InstallmentsPage(
        items: snapshot.installments,
        searchQueryNotifier: _installmentsSearchQuery,
        filterNotifier: _installmentsFilter,
      ),
      OwnerModule.payments => PaymentsPage(
        items: snapshot.payments,
        searchNotifier: _searchNotifier,
      ),
      OwnerModule.sellers => SellersPage(
        items: snapshot.sellers,
        searchQueryNotifier: _sellersSearchQuery,
        filterNotifier: _sellersFilter,
        allSales: snapshot.sales,
        allClients: snapshot.clients,
        allLots: snapshot.lots,
      ),
      OwnerModule.documentation => const DocumentationPage(),
    };
  }

  List<Map<String, dynamic>> _moduleItems(
    OwnerSnapshot snapshot,
    OwnerModule module,
  ) {
    return switch (module) {
      OwnerModule.dashboard => const [],
      OwnerModule.clients => snapshot.clients,
      OwnerModule.lots => snapshot.lots,
      OwnerModule.sales => snapshot.sales,
      OwnerModule.installments => snapshot.installments,
      OwnerModule.payments => snapshot.payments,
      OwnerModule.sellers => snapshot.sellers,
      OwnerModule.documentation => const [],
    };
  }
}

class _RefreshWarning extends StatelessWidget {
  const _RefreshWarning({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentAmber.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Mostrando información guardada. Reintentaremos actualizar.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceWarm,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: IconTheme(
                data: const IconThemeData(color: AppColors.primary, size: 21),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopDetailPanel extends StatelessWidget {
  const _DesktopDetailPanel({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          left: BorderSide(color: AppColors.borderLight, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(-8, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: 8,
            right: 10,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              elevation: 2,
              child: IconButton(
                onPressed: onClose,
                tooltip: 'Cerrar detalle',
                icon: const Icon(Icons.close_rounded, size: 19),
                color: AppColors.textSecondary,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSideNav extends StatefulWidget {
  const _DesktopSideNav({required this.selected, required this.onSelected});

  final OwnerModule selected;
  final ValueChanged<OwnerModule> onSelected;

  @override
  State<_DesktopSideNav> createState() => _DesktopSideNavState();
}

class _DesktopSideNavState extends State<_DesktopSideNav> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _expanded = true),
      onExit: (_) => setState(() => _expanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: _expanded
            ? _desktopSidebarExpandedWidth
            : _desktopSidebarCollapsedWidth,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D2844), Color(0xFF071829)],
          ),
          boxShadow: _expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 24,
                    offset: const Offset(8, 0),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          children: [
            _DesktopLogoHeader(expanded: _expanded),
            const SizedBox(height: 14),
            ...customerVisibleModules.map((module) {
              return _SideNavItem(
                module: module,
                selected: widget.selected == module,
                expanded: _expanded,
                onTap: () => widget.onSelected(module),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DesktopLogoHeader extends StatelessWidget {
  const _DesktopLogoHeader({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: expanded ? 76 : 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Image.asset(
              'lib/widgets/assets/logoprincipal.png',
              fit: BoxFit.contain,
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alto de Mamita',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'App Owner',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.module,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final OwnerModule module;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xB8FFFFFF);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 12 : 7,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.transparent,
              ),
            ),
            child: expanded
                ? Row(
                    children: [
                      Icon(moduleIcon(module), color: color, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          module.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xCCFFFFFF),
                            fontSize: 13,
                            height: 1.08,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(moduleIcon(module), color: color, size: 22),
                      const SizedBox(height: 5),
                      Text(
                        module.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xB8FFFFFF),
                          fontSize: 10.8,
                          height: 1.08,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ModuleSearchDialog extends StatefulWidget {
  const _ModuleSearchDialog({
    required this.moduleTitle,
    required this.initialQuery,
  });

  final String moduleTitle;
  final String initialQuery;

  @override
  State<_ModuleSearchDialog> createState() => _ModuleSearchDialogState();
}

class _ModuleSearchDialogState extends State<_ModuleSearchDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buscar en ${widget.moduleTitle.toLowerCase()}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Filtra los registros de esta pantalla.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(_controller.clear),
                          ),
                    hintText: 'Nombre, solar, documento, teléfono...',
                    filled: true,
                    fillColor: AppColors.surfaceWarm,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.borderLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.borderLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    if (widget.initialQuery.trim().isNotEmpty)
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(''),
                        child: const Text('Limpiar'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Buscar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchFab extends StatefulWidget {
  const _GlobalSearchFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_GlobalSearchFab> createState() => _GlobalSearchFabState();
}

class _GlobalSearchFabState extends State<_GlobalSearchFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _rotateAnim = Tween<double>(begin: 0, end: 0.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotateAnim.value,
          child: Transform.scale(scale: _scaleAnim.value, child: child),
        );
      },
      child: Container(
        width: Responsive.isDesktop(context) ? 132 : 58,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: widget.onPressed,
          tooltip: 'Búsqueda global',
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Responsive.isDesktop(context)
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_rounded, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Buscar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : const Icon(Icons.search_rounded, size: 27),
        ),
      ),
    );
  }
}

class _TopBarSearchField extends StatelessWidget {
  const _TopBarSearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        border: InputBorder.none,
        isDense: true,
      ),
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      onChanged: onChanged,
    );
  }
}

class _SearchCloseButton extends StatelessWidget {
  const _SearchCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Cerrar búsqueda',
      icon: const Icon(
        Icons.arrow_back_rounded,
        size: 21,
        color: AppColors.primary,
      ),
    );
  }
}

/// Elegant menu button for opening the drawer on mobile.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 8, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceWarm,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight, width: 1),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.menu_rounded,
              size: 24,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Clean back button for secondary screens on mobile.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 11, bottom: 11),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceWarm,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.borderLight, width: 1),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps an [OwnerModule] to its corresponding page widget.
class ModulePage extends StatelessWidget {
  const ModulePage({
    super.key,
    required this.module,
    required this.snapshot,
    this.onOpenModule,
  });

  final OwnerModule module;
  final OwnerSnapshot snapshot;
  final ValueChanged<OwnerModule>? onOpenModule;

  @override
  Widget build(BuildContext context) {
    return switch (module) {
      OwnerModule.dashboard => DashboardPage(
        snapshot: snapshot,
        onOpenModule: onOpenModule,
      ),
      OwnerModule.clients => ClientsPage(items: snapshot.clients),
      OwnerModule.lots => LotsPage(items: snapshot.lots),
      OwnerModule.sales => SalesPage(items: snapshot.sales),
      OwnerModule.installments => InstallmentsPage(
        items: snapshot.installments,
      ),
      OwnerModule.payments => PaymentsPage(items: snapshot.payments),
      OwnerModule.sellers => SellersPage(items: snapshot.sellers),
      OwnerModule.documentation => const DocumentationPage(),
    };
  }
}
