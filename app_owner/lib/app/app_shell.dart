import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/services/api_client.dart';
import '../core/models/owner_snapshot.dart';
import '../widgets/owner_drawer.dart';
import '../widgets/error_view.dart';
import '../widgets/error_banner.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/clients/clients_page.dart';
import '../features/lots/lots_page.dart';
import '../features/sales/sales_page.dart';
import '../features/payments/payments_page.dart';
import '../features/installments/installments_page.dart';
import '../features/sellers/sellers_page.dart';
import 'app_colors.dart';
import 'responsive.dart';
import 'safe_area_padding.dart';

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
  }
}

/// Main navigation shell for the Owner app.
///
/// Responsive: uses [NavigationBar] on mobile, [NavigationRail] on tablet/desktop.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final ApiClient _api = const ApiClient(baseUrl);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  OwnerSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  OwnerModule _selected = OwnerModule.dashboard;
  Timer? _timer;

  // Filter state for Dashboard
  String _filterLabel = 'Hoy';

  // Search notifier for module pages
  final ValueNotifier<bool> _searchNotifier = ValueNotifier<bool>(false);
  // Trigger notifier for opening filter sheet from AppBar menu
  final ValueNotifier<int> _filterTriggerNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      ownerRefreshInterval,
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchNotifier.dispose();
    _filterTriggerNotifier.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final snapshot = await _api.fetchSnapshot();
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
    setState(() => _selected = module);
  }

  void _toggleSearch() {
    _searchNotifier.value = !_searchNotifier.value;
  }

  /// Returns true when the current module is the Dashboard.
  bool get _isDashboard => _selected == OwnerModule.dashboard;

  void _openFilterSheet() {
    // Trigger the filter sheet in the current module page via notifier
    _filterTriggerNotifier.value++;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(context, isDesktop, isMobile),
      drawer: isMobile ? _buildDrawer() : null,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Side navigation for tablet/desktop
            if (!isMobile) _buildNavigationRail(),
            // Main content area
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isDesktop,
    bool isMobile,
  ) {
    return AppBar(
      // --- Leading: drawer button on mobile (only on Dashboard) ---
      leading: isMobile
          ? (_isDashboard
                ? _MenuButton(
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  )
                : _BackButton(
                    onPressed: () => _selectModule(OwnerModule.dashboard),
                  ))
          : null,

      // --- Title ---
      title: _isDashboard
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Panel',
                  style: TextStyle(
                    fontSize: isMobile ? 20 : 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Resumen rápido del negocio',
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                    color: AppColors.textSecondary,
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
        if (!_isDashboard)
          IconButton(
            onPressed: _toggleSearch,
            icon: Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            tooltip: 'Buscar',
            splashRadius: 22,
          ),
        // Filter button only on Dashboard
        if (_isDashboard)
          PopupMenuButton<String>(
            tooltip: 'Filtrar',
            icon: Icon(
              Icons.tune_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            onSelected: (value) {
              setState(() => _filterLabel = value);
              debugPrint('Filtro seleccionado: $value');
            },
            itemBuilder: (_) => [
              _filterItem('Hoy', Icons.today_outlined),
              _filterItem('Ayer', Icons.navigate_before_outlined),
              _filterItem('Esta semana', Icons.date_range_outlined),
              _filterItem('Este mes', Icons.calendar_month_outlined),
              _filterItem('Personalizado', Icons.calendar_today_outlined),
            ],
          ),
        // More options menu (for non-Dashboard modules)
        if (!_isDashboard)
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
          IconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            color: AppColors.textSecondary,
            splashRadius: 22,
          ),
        const SizedBox(width: 4),
      ],

      // --- Styling ---
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: AppColors.border, width: 0.5),
      ),
    );
  }

  PopupMenuItem<String> _filterItem(String label, IconData icon) {
    return PopupMenuItem<String>(
      value: label,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accentBlue),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (label == _filterLabel)
            Icon(Icons.check, size: 18, color: AppColors.accentBlue),
        ],
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
    return NavigationRail(
      selectedIndex: OwnerModule.values.indexOf(_selected),
      onDestinationSelected: (index) {
        _selectModule(OwnerModule.values[index]);
      },
      labelType: NavigationRailLabelType.all,
      backgroundColor: AppColors.surface,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.real_estate_agent, size: 32),
            const SizedBox(height: 4),
            Text(
              'Owner',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      destinations: OwnerModule.values.map((module) {
        return NavigationRailDestination(
          icon: Icon(moduleIcon(module)),
          label: Text(module.title),
        );
      }).toList(),
    );
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return ErrorView(error: _error, onRetry: () => _refresh());
    }
    final snapshot = _snapshot!;
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Constrain content width on wide screens for readability
          final contentWidth = constraints.maxWidth > 900
              ? 900.0
              : constraints.maxWidth;
          return SingleChildScrollView(
            padding: safeScrollPadding(context),
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    if (_error != null) ErrorBanner(error: _error),
                    _buildPageContent(snapshot),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageContent(OwnerSnapshot snapshot) {
    return switch (_selected) {
      OwnerModule.dashboard => DashboardPage(
        snapshot: snapshot,
        onOpenModule: _selectModule,
        filterLabel: _filterLabel,
      ),
      OwnerModule.clients => ClientsPage(
        items: snapshot.clients,
        searchNotifier: _searchNotifier,
      ),
      OwnerModule.lots => LotsPage(
        items: snapshot.lots,
        searchNotifier: _searchNotifier,
      ),
      OwnerModule.sales => SalesPage(
        items: snapshot.sales,
        searchNotifier: _searchNotifier,
        filterTriggerNotifier: _filterTriggerNotifier,
        allInstallments: snapshot.installments,
        allPayments: snapshot.payments,
        allClients: snapshot.clients,
        allSellers: snapshot.sellers,
      ),
      OwnerModule.installments => InstallmentsPage(
        items: snapshot.installments,
        searchNotifier: _searchNotifier,
      ),
      OwnerModule.payments => PaymentsPage(
        items: snapshot.payments,
        searchNotifier: _searchNotifier,
      ),
      OwnerModule.sellers => SellersPage(
        items: snapshot.sellers,
        searchNotifier: _searchNotifier,
      ),
    };
  }
}

/// Elegant menu button for opening the drawer on mobile.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.menu_rounded,
              size: 22,
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
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              size: 24,
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
    };
  }
}
