import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/system/system_config_service.dart';
import '../../features/auth/domain/user_model.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/clients/data/client_repository.dart';
import '../../features/clients/presentation/clients_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/global_search/presentation/global_search_page.dart';
import '../../features/installments/data/installments_repository.dart';
import '../../features/installments/presentation/installments_page.dart';
import '../../features/lots/data/lot_repository.dart';
import '../../features/lots/presentation/lots_page.dart';
import '../../features/payments/data/payments_repository.dart';
import '../../features/payments/presentation/payments_page.dart';
import '../../features/sales/data/sales_repository.dart';
import '../../features/sales/data/seller_repository.dart';
import '../../features/sales/presentation/sales_page.dart';
import '../../features/sales/presentation/sellers_page.dart';
import '../../features/settings/data/company_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../models/sync/sync_connection_status.dart';
import '../../repositories/installments_sync_repository.dart';
import '../../repositories/payments_sync_repository.dart';
import '../../repositories/products_sync_repository.dart';
import '../../repositories/sales_sync_repository.dart';
import '../../repositories/users_sync_repository.dart';
import '../../services/realtime_sync_service.dart';
import '../../services/sync/sync_conflict_service.dart';
import '../../services/sync/sync_manager.dart';
import '../../services/sync/sync_queue_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/widgets/base_layout.dart';
import 'app_module.dart';

const List<AppModule> _primarySidebarModules = [
  AppModule.dashboard,
  AppModule.sales,
  AppModule.globalSearch,
  AppModule.payments,
];

const List<AppModule> _administrationSidebarModules = [
  AppModule.clients,
  AppModule.lots,
  AppModule.installments,
  AppModule.sellers,
  AppModule.settings,
];

const double _sidebarCollapsedWidth = 96;
const double _sidebarExpandedWidth = 288;
const double _sidebarSafeExpandedContentWidth = 240;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _sidebarExpandedPreferenceKey = 'shell.sidebar.expanded';
  static const _sidebarAdministrationPreferenceKey =
      'shell.sidebar.administration.expanded';

  final SyncQueueService _syncQueueService = SyncQueueService.instance;
  late final ClientRepository _clientRepository = ClientRepository(
    syncQueueService: _syncQueueService,
  );
  late final LotRepository _lotRepository = LotRepository(
    syncQueueService: _syncQueueService,
  );
  late final SalesRepository _salesRepository = SalesRepository(
    syncQueueService: _syncQueueService,
  );
  final SellerRepository _sellerRepository = SellerRepository();
  final InstallmentsRepository _installmentsRepository =
      InstallmentsRepository();
  late final PaymentsRepository _paymentsRepository = PaymentsRepository(
    syncQueueService: _syncQueueService,
  );
  final SettingsRepository _settingsRepository = SettingsRepository();
  final ProductsSyncRepository _productsSyncRepository =
      ProductsSyncRepository();
  final UsersSyncRepository _usersSyncRepository = UsersSyncRepository();
  final SalesSyncRepository _salesSyncRepository = SalesSyncRepository();
  final InstallmentsSyncRepository _installmentsSyncRepository =
      InstallmentsSyncRepository();
  final PaymentsSyncRepository _paymentsSyncRepository =
      PaymentsSyncRepository();
  late final SyncService _syncService = SyncService(
    repositories: [
      _usersSyncRepository,
      _clientRepository,
      _productsSyncRepository,
      _sellerRepository,
      _salesSyncRepository,
      _installmentsSyncRepository,
      _paymentsSyncRepository,
    ],
    syncQueueService: _syncQueueService,
    onCloudSessionExpired: _handleCloudSessionExpired,
  );
  late final RealtimeSyncService _realtimeSyncService = RealtimeSyncService(
    syncService: _syncService,
  );

  final SyncConflictService _syncConflictService = SyncConflictService();
  late final SyncManager _syncManager = SyncManager(
    syncService: _syncService,
    syncQueueService: _syncQueueService,
    realtimeSyncService: _realtimeSyncService,
    syncConflictService: _syncConflictService,
  );

  AppModule _selectedModule = AppModule.dashboard;
  String _companyDisplayName = 'Sistema Solares';
  bool _isSidebarExpanded = false;
  bool _isAdministrationMenuExpanded = false;
  int? _selectedInstallmentsSaleId;
  int? _selectedPaymentsSaleId;
  bool _cloudSessionExpiredHandled = false;

  @override
  void initState() {
    super.initState();
    _restoreNavigationPreferences();
    _loadCompanyDisplayName();
    _syncQueueService.setCloudSessionExpiredHandler(_handleCloudSessionExpired);
    _syncManager.addListener(_handleSyncManagerChanged);
    unawaited(_syncManager.start());
  }

  @override
  void dispose() {
    _syncQueueService.setCloudSessionExpiredHandler(null);
    _syncManager.removeListener(_handleSyncManagerChanged);
    _syncManager.dispose();
    _syncConflictService.dispose();
    _realtimeSyncService.dispose();
    _syncQueueService.dispose();
    _syncService.dispose();
    super.dispose();
  }

  void _handleSyncManagerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _restoreNavigationPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    final nextSidebarExpanded =
        preferences.getBool(_sidebarExpandedPreferenceKey) ?? false;
    final nextAdministrationExpanded =
        preferences.getBool(_sidebarAdministrationPreferenceKey) ?? false;

    if (_isSidebarExpanded == nextSidebarExpanded &&
        _isAdministrationMenuExpanded == nextAdministrationExpanded) {
      return;
    }

    setState(() {
      _isSidebarExpanded = nextSidebarExpanded;
      _isAdministrationMenuExpanded = nextAdministrationExpanded;
    });
  }

  Future<void> _persistNavigationPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _sidebarExpandedPreferenceKey,
      _isSidebarExpanded,
    );
    await preferences.setBool(
      _sidebarAdministrationPreferenceKey,
      _isAdministrationMenuExpanded,
    );
  }

  Future<void> _loadCompanyDisplayName() async {
    final settings = await _settingsRepository.fetchByKeysWithDefaults({
      SettingsRepository.businessNameKey:
          SettingsRepository.defaultSettings[SettingsRepository
              .businessNameKey] ??
          'Sistema Solares',
    });
    final database = await AppDatabase.instance.database;
    final companyRepository = CompanyRepository(database);
    final companyInfo = await companyRepository.getCompanyInfo();
    final settingsName =
        settings[SettingsRepository.businessNameKey]?.value.trim() ?? '';
    final companyName = companyInfo?.nombre.trim() ?? '';
    final resolvedName = companyName.isNotEmpty
        ? companyName
        : (settingsName.isNotEmpty ? settingsName : 'Sistema Solares');

    if (!mounted) {
      return;
    }

    if (_companyDisplayName == resolvedName) {
      return;
    }

    setState(() {
      _companyDisplayName = resolvedName;
    });
  }

  List<AppModule> _accessibleModules(AuthProvider auth) {
    final modules = AppModule.values
        .where((module) => auth.canReadModule(module.permissionKey))
        .toList();
    if (modules.isEmpty) {
      return const [AppModule.dashboard];
    }
    return modules;
  }

  AppModule _resolveSelectedModule(List<AppModule> accessibleModules) {
    if (accessibleModules.contains(_selectedModule)) {
      return _selectedModule;
    }
    return accessibleModules.first;
  }

  void _openModule(AppModule module) {
    setState(() {
      _selectedModule = module;
      if (module != AppModule.installments) {
        _selectedInstallmentsSaleId = null;
      }
      if (module != AppModule.payments) {
        _selectedPaymentsSaleId = null;
      }
    });
  }

  void _openInstallments(int? saleId) {
    setState(() {
      _selectedModule = AppModule.installments;
      _selectedInstallmentsSaleId = saleId;
    });
  }

  void _openPayments(int? saleId) {
    setState(() {
      _selectedModule = AppModule.payments;
      _selectedPaymentsSaleId = saleId;
    });
  }

  Future<void> _toggleSidebar() async {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
    await _persistNavigationPreferences();
  }

  Future<void> _toggleAdministrationMenu() async {
    setState(() {
      _isAdministrationMenuExpanded = !_isAdministrationMenuExpanded;
    });
    await _persistNavigationPreferences();
  }

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

    if (!mounted) {
      return;
    }

    await context.read<AuthProvider>().refreshCurrentUser();
  }

  Future<void> _signOut() async {
    final authProvider = context.read<AuthProvider>();
    await _syncManager.stop(reason: 'Sesion cerrada.');
    await authProvider.signOut();
  }

  Future<void> _handleCloudSessionExpired(String reason) async {
    if (_cloudSessionExpiredHandled) {
      return;
    }
    _cloudSessionExpiredHandled = true;
    final authProvider = context.read<AuthProvider>();
    // Detener sync indicando claramente que se necesita vincular credenciales.
    await _syncManager.stop(
      reason:
          'Sesion de nube expirada. Inicia sesion en linea nuevamente para '
          'reactivar la sincronizacion.',
    );
    if (!mounted) {
      return;
    }
    // Marcar la sesión de nube como expirada SIN cerrar la sesión local.
    // El usuario permanece autenticado localmente; solo la sync está bloqueada.
    // El sync status badge ya muestra el error de conexión al usuario.
    authProvider.markCloudSessionExpired();
  }

  Future<void> _runSync({bool showFeedback = true}) async {
    if (context.read<SystemConfigService>().isReadOnly) {
      return;
    }

    if (_syncManager.state.isSyncing) {
      return;
    }

    final report = await _syncManager.syncNow();

    if (!mounted) {
      return;
    }

    if (!showFeedback) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(report.summary)));
  }

  /// Abre el diálogo para vincular la sesión local con la nube cuando el
  /// usuario creó su cuenta sin conexión y ahora necesita un JWT de sync.
  Future<void> _connectToCloud() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloudLinkDialog(
        onSuccess: () async {
          if (!mounted) return;
          // Resetear flags de sesión expirada para que futuros vencimientos
          // sean manejados correctamente.
          _cloudSessionExpiredHandled = false;
          _syncService.resetCloudSession();
          // Reiniciar el sync manager para que tome el nuevo JWT.
          await _syncManager.stop(reason: null);
          await _syncManager.start();
        },
      ),
    );
  }

  /// Retorna true si los errores de sync indican que se necesitan credenciales
  /// de nube, para mostrar el botón "Vincular".
  /// Cubre: 401 Unauthorized, sin JWT, sin URL, error de conexión (cuando
  /// hay JWT guardado inválido que causó el error).
  bool _needsCloudLink(List<String> errors) {
    if (errors.isEmpty) return false;
    final msg = errors.first.toLowerCase();
    return msg.contains('sesion en linea') ||
        msg.contains('sesión en línea') ||
        msg.contains('reautenticarse') ||
        msg.contains('credencial actual') ||
        msg.contains('error de conexion') ||
        msg.contains('error de conexión') ||
        msg.contains('sin jwt') ||
        msg.contains('unauthorized');
  }

  Widget _buildCurrentPage(AppModule module) {
    switch (module) {
      case AppModule.dashboard:
        return DashboardPage(
          clientRepository: _clientRepository,
          lotRepository: _lotRepository,
          salesRepository: _salesRepository,
          installmentsRepository: _installmentsRepository,
        );
      case AppModule.sales:
        return SalesPage(
          salesRepository: _salesRepository,
          clientRepository: _clientRepository,
          lotRepository: _lotRepository,
          sellerRepository: _sellerRepository,
          settingsRepository: _settingsRepository,
        );
      case AppModule.globalSearch:
        return GlobalSearchPage(
          clientRepository: _clientRepository,
          lotRepository: _lotRepository,
          salesRepository: _salesRepository,
          installmentsRepository: _installmentsRepository,
          onOpenClients: () => _openModule(AppModule.clients),
          onOpenLots: () => _openModule(AppModule.lots),
          onOpenSales: () => _openModule(AppModule.sales),
          onOpenInstallments: _openInstallments,
          onOpenPayments: _openPayments,
        );
      case AppModule.clients:
        return ClientsPage(repository: _clientRepository);
      case AppModule.lots:
        return LotsPage(repository: _lotRepository);
      case AppModule.payments:
        return PaymentsPage(
          paymentsRepository: _paymentsRepository,
          initialSaleId: _selectedPaymentsSaleId,
        );
      case AppModule.installments:
        return InstallmentsPage(saleId: _selectedInstallmentsSaleId);
      case AppModule.sellers:
        return SellersPage(
          repository: _sellerRepository,
          salesRepository: _salesRepository,
        );
      case AppModule.settings:
        return SettingsPage(onCompanyInfoChanged: _loadCompanyDisplayName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isReadOnly = context.watch<SystemConfigService>().isReadOnly;
    final syncState = _syncManager.state;
    final accessibleModules = _accessibleModules(auth);
    final resolvedModule = _resolveSelectedModule(accessibleModules);
    final primaryModules = _primarySidebarModules
        .where(accessibleModules.contains)
        .toList();
    final administrationModules = _administrationSidebarModules
        .where(accessibleModules.contains)
        .toList();
    final currentPage = KeyedSubtree(
      key: ValueKey(
        Object.hash(
          resolvedModule,
          _selectedInstallmentsSaleId,
          _selectedPaymentsSaleId,
        ),
      ),
      child: ShellLayoutScope(child: _buildCurrentPage(resolvedModule)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;
        final user = auth.currentUser;

        if (!isDesktop) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_companyDisplayName),
              centerTitle: true,
              toolbarHeight: 46,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: _SyncStatusBadge(
                      isSyncing: syncState.isSyncing,
                      connectionStatus: syncState.connectionStatus,
                      hasErrors: syncState.currentErrors.isNotEmpty,
                      pendingCount: syncState.pendingCount,
                      unresolvedConflictCount:
                          syncState.unresolvedConflictCount,
                      compact: true,
                    ),
                  ),
                ),
                if (user != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Center(
                      child: _HeaderProfileButton(onTap: _openProfile),
                    ),
                  ),
                IconButton(
                  tooltip: 'Cerrar sesion',
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
            drawer: Drawer(
              child: _ShellNavigation(
                selectedModule: resolvedModule,
                primaryModules: primaryModules,
                administrationModules: administrationModules,
                isCollapsed: false,
                isAdministrationMenuExpanded: true,
                allowCollapse: false,
                onSelectModule: (module) {
                  Navigator.of(context).pop();
                  _openModule(module);
                },
                onToggleCollapse: null,
                onToggleAdministrationMenu: null,
              ),
            ),
            body: Column(
              children: [
                Expanded(child: currentPage),
                _ShellFooter(companyName: _companyDisplayName),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF0F3F8),
          body: SafeArea(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: _isSidebarExpanded
                      ? _sidebarExpandedWidth
                      : _sidebarCollapsedWidth,
                  child: ClipRect(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0D2844), Color(0xFF071829)],
                        ),
                      ),
                      child: _ShellNavigation(
                        selectedModule: resolvedModule,
                        primaryModules: primaryModules,
                        administrationModules: administrationModules,
                        isCollapsed: !_isSidebarExpanded,
                        isAdministrationMenuExpanded:
                            _isAdministrationMenuExpanded,
                        allowCollapse: true,
                        onSelectModule: _openModule,
                        onToggleCollapse: _toggleSidebar,
                        onToggleAdministrationMenu: _toggleAdministrationMenu,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFE4EAF2),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 20,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _ShellHeader(
                              selectedModule: resolvedModule,
                              currentUser: user,
                              isSyncing: syncState.isSyncing,
                              connectionStatus: syncState.connectionStatus,
                              currentErrors: syncState.currentErrors,
                              pendingCount: syncState.pendingCount,
                              unresolvedConflictCount:
                                  syncState.unresolvedConflictCount,
                              onTriggerSync: isReadOnly
                                  ? () async {}
                                  : _runSync,
                              onOpenProfile: _openProfile,
                              onConnectToCloud:
                                  _needsCloudLink(syncState.currentErrors)
                                  ? _connectToCloud
                                  : null,
                            ),
                            Expanded(child: currentPage),
                            _ShellFooter(companyName: _companyDisplayName),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.selectedModule,
    required this.currentUser,
    required this.isSyncing,
    required this.connectionStatus,
    required this.currentErrors,
    required this.pendingCount,
    required this.unresolvedConflictCount,
    required this.onTriggerSync,
    required this.onOpenProfile,
    this.onConnectToCloud,
  });

  final AppModule selectedModule;
  final UserModel? currentUser;
  final bool isSyncing;
  final SyncConnectionStatus connectionStatus;
  final List<String> currentErrors;
  final int pendingCount;
  final int unresolvedConflictCount;
  final Future<void> Function() onTriggerSync;
  final Future<void> Function() onOpenProfile;
  final Future<void> Function()? onConnectToCloud;

  @override
  Widget build(BuildContext context) {
    final user = currentUser;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border(bottom: BorderSide(color: Color(0xFFECEFF3), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      selectedModule.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF0D2640),
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Sistema Solares',
                      style: TextStyle(
                        color: const Color(0xFF0D2640).withValues(alpha: 0.32),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _SyncStatusBadge(
                  isSyncing: isSyncing,
                  connectionStatus: connectionStatus,
                  hasErrors: currentErrors.isNotEmpty,
                  pendingCount: pendingCount,
                  unresolvedConflictCount: unresolvedConflictCount,
                ),
              ),
              if (user != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      user.nombre,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D2640),
                      ),
                    ),
                    Text(
                      user.role.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0D2640).withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                _HeaderProfileButton(onTap: onOpenProfile),
              ],
            ],
          ),
          if (currentErrors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SyncAlertBanner(
              message: currentErrors.first,
              onRetry: onConnectToCloud != null ? null : (isSyncing ? null : onTriggerSync),
              onConnectToCloud: onConnectToCloud,
            ),
          ] else if (unresolvedConflictCount > 0) ...[
            const SizedBox(height: 10),
            _SyncAlertBanner(
              message:
                  'Hay $unresolvedConflictCount conflicto(s) de sincronización por resolver.',
            ),
          ],
        ],
      ),
    );
  }
}

class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge({
    required this.isSyncing,
    required this.connectionStatus,
    required this.hasErrors,
    required this.pendingCount,
    required this.unresolvedConflictCount,
    this.compact = false,
  });

  final bool isSyncing;
  final SyncConnectionStatus connectionStatus;
  final bool hasErrors;
  final int pendingCount;
  final int unresolvedConflictCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    late final IconData icon;

    if (hasErrors) {
      color = const Color(0xFFD9534F);
      label = 'Error';
      icon = Icons.error_rounded;
    } else if (unresolvedConflictCount > 0) {
      color = const Color(0xFFE2A400);
      label = 'Conflictos';
      icon = Icons.warning_amber_rounded;
    } else if (isSyncing ||
        pendingCount > 0 ||
        connectionStatus != SyncConnectionStatus.connected) {
      color = const Color(0xFFE2A400);
      label = 'Pendiente';
      icon = Icons.schedule_rounded;
    } else {
      color = const Color(0xFF2BB673);
      label = 'Sincronizado';
      icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 15, color: color),
          SizedBox(width: compact ? 5 : 7),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0D2640),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncAlertBanner extends StatelessWidget {
  const _SyncAlertBanner({
    required this.message,
    this.onRetry,
    this.onConnectToCloud,
  });

  final String message;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onConnectToCloud;

  @override
  Widget build(BuildContext context) {
    final canRetry = onRetry != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0C36D)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFF9A5B00),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6E4300),
              ),
            ),
          ),
          if (onConnectToCloud != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => unawaited(onConnectToCloud!()),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6E4300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Vincular'),
            ),
          ] else if (canRetry) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => unawaited(onRetry!()),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6E4300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShellNavigation extends StatelessWidget {
  const _ShellNavigation({
    required this.selectedModule,
    required this.primaryModules,
    required this.administrationModules,
    required this.isCollapsed,
    required this.isAdministrationMenuExpanded,
    required this.allowCollapse,
    required this.onSelectModule,
    required this.onToggleCollapse,
    required this.onToggleAdministrationMenu,
  });

  final AppModule selectedModule;
  final List<AppModule> primaryModules;
  final List<AppModule> administrationModules;
  final bool isCollapsed;
  final bool isAdministrationMenuExpanded;
  final bool allowCollapse;
  final ValueChanged<AppModule> onSelectModule;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onToggleAdministrationMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textTheme = Theme.of(context).textTheme;
        final selectedInAdministration = administrationModules.contains(
          selectedModule,
        );
        final toggleCollapse = onToggleCollapse ?? () {};
        final toggleAdministrationMenu = onToggleAdministrationMenu ?? () {};
        final effectiveCollapsed =
            isCollapsed ||
            constraints.maxWidth < _sidebarSafeExpandedContentWidth;

        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  effectiveCollapsed ? 14 : 18,
                  18,
                  effectiveCollapsed ? 14 : 18,
                  16,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
                ),
                child: effectiveCollapsed
                    ? Center(
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF59B6FF), Color(0xFF1B5BA8)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF4B9EE8,
                                ).withValues(alpha: 0.32),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.wb_sunny_rounded,
                            size: 21,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF59B6FF), Color(0xFF1B5BA8)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF4B9EE8,
                                  ).withValues(alpha: 0.32),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.wb_sunny_rounded,
                              size: 21,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Sistema Solares',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Navegación ejecutiva',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0x8AFFFFFF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (allowCollapse) ...[
                            const SizedBox(width: 10),
                            _SidebarCompactAction(
                              icon: Icons.keyboard_double_arrow_left_rounded,
                              tooltip: 'Ocultar menú',
                              onTap: toggleCollapse,
                            ),
                          ],
                        ],
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    effectiveCollapsed ? 10 : 12,
                    16,
                    effectiveCollapsed ? 10 : 12,
                    14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (allowCollapse && effectiveCollapsed) ...[
                        Align(
                          alignment: Alignment.center,
                          child: _SidebarCompactAction(
                            icon: Icons.keyboard_double_arrow_right_rounded,
                            tooltip: 'Mostrar menú completo',
                            onTap: toggleCollapse,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (!effectiveCollapsed)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 10),
                          child: Text(
                            'DESTACADOS',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.34),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final module in primaryModules) ...[
                              _SidebarItem(
                                module: module,
                                isSelected: module == selectedModule,
                                textTheme: textTheme,
                                isCollapsed: effectiveCollapsed,
                                isPrimary: true,
                                onTap: () => onSelectModule(module),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (administrationModules.isNotEmpty) ...[
                              SizedBox(height: effectiveCollapsed ? 12 : 16),
                              if (!effectiveCollapsed)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 8,
                                    bottom: 10,
                                  ),
                                  child: Text(
                                    'ADMINISTRACIÓN',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.34,
                                      ),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.8,
                                    ),
                                  ),
                                ),
                              _AdministrationMenu(
                                modules: administrationModules,
                                selectedModule: selectedModule,
                                textTheme: textTheme,
                                isCollapsed: effectiveCollapsed,
                                isExpanded: isAdministrationMenuExpanded,
                                onToggle: toggleAdministrationMenu,
                                onSelectModule: onSelectModule,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!effectiveCollapsed)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF5BAEE8,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 20,
                                  color: Color(0xFF83CAFF),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Acceso rápido',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Resumen, buscador, ventas y pagos primero.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0x91FFFFFF),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: effectiveCollapsed
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.spaceBetween,
                        children: [
                          if (!effectiveCollapsed)
                            Expanded(
                              child: Text(
                                selectedInAdministration
                                    ? 'Administración activa'
                                    : 'Módulo listo',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.44),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          _SidebarCompactAction(
                            icon: Icons.logout_rounded,
                            tooltip: 'Cerrar sesión',
                            onTap: () async {
                              await context.read<AuthProvider>().signOut();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdministrationMenu extends StatelessWidget {
  const _AdministrationMenu({
    required this.modules,
    required this.selectedModule,
    required this.textTheme,
    required this.isCollapsed,
    required this.isExpanded,
    required this.onToggle,
    required this.onSelectModule,
  });

  final List<AppModule> modules;
  final AppModule selectedModule;
  final TextTheme textTheme;
  final bool isCollapsed;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<AppModule> onSelectModule;

  @override
  Widget build(BuildContext context) {
    final isSelected = modules.contains(selectedModule);

    if (isCollapsed) {
      return _PremiumTooltip(
        message: 'Administración',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: isSelected
                ? const Color(0xFF143B61)
                : Colors.white.withValues(alpha: 0.03),
            child: InkWell(
              onTap: onToggle,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isSelected
                        ? const Color(0xFF5BAEE8).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF83CAFF).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                    color: Color(0xFF9AD6FF),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: const Color(0xFF5BAEE8).withValues(alpha: 0.14),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 19,
                        color: Color(0xFF8ED2FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Administración',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Clientes, solares, cuotas y configuración',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0x96FFFFFF),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  const Divider(color: Color(0x14FFFFFF), height: 1),
                  const SizedBox(height: 8),
                  for (final module in modules) ...[
                    _SidebarItem(
                      module: module,
                      isSelected: module == selectedModule,
                      textTheme: textTheme,
                      isCollapsed: false,
                      isPrimary: false,
                      compactLeadingInset: 8,
                      onTap: () => onSelectModule(module),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.module,
    required this.isSelected,
    required this.textTheme,
    required this.isCollapsed,
    required this.isPrimary,
    required this.onTap,
    this.compactLeadingInset = 0,
  });

  final AppModule module;
  final bool isSelected;
  final TextTheme textTheme;
  final bool isCollapsed;
  final bool isPrimary;
  final VoidCallback onTap;
  final double compactLeadingInset;

  static const _accent = Color(0xFF5BAEE8);

  @override
  Widget build(BuildContext context) {
    final item = ClipRRect(
      borderRadius: BorderRadius.circular(isCollapsed ? 16 : 14),
      child: Material(
        color: isSelected
            ? const Color(0xFF163554)
            : isPrimary
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.white.withValues(alpha: 0.05),
          splashColor: Colors.white.withValues(alpha: 0.07),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 0 : 10 + compactLeadingInset,
              vertical: isCollapsed ? 9 : (isPrimary ? 10 : 9),
            ),
            child: isCollapsed
                ? Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: isSelected && isPrimary
                            ? const LinearGradient(
                                colors: [Color(0xFF5EB8FF), Color(0xFF2B72C8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected
                            ? _accent.withValues(alpha: 0.16)
                            : Colors.white.withValues(
                                alpha: isPrimary ? 0.09 : 0.06,
                              ),
                        border: Border.all(
                          color: isSelected
                              ? _accent.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.25),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        module.icon,
                        size: 20,
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: isPrimary ? 38 : 36,
                        height: isPrimary ? 38 : 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: isSelected && isPrimary
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF5EB8FF),
                                    Color(0xFF2B72C8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected
                              ? _accent.withValues(alpha: 0.18)
                              : Colors.white.withValues(
                                  alpha: isPrimary ? 0.09 : 0.06,
                                ),
                          border: Border.all(
                            color: isSelected
                                ? _accent.withValues(alpha: 0.35)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Icon(
                          module.icon,
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.74),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.78),
                            fontWeight: isSelected || isPrimary
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: isPrimary ? 14.2 : 13.2,
                            letterSpacing: 0.15,
                          ),
                          child: Text(module.label),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? _accent : Colors.transparent,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: _accent.withValues(alpha: 0.60),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!isCollapsed) {
      return item;
    }

    return _PremiumTooltip(message: module.label, child: item);
  }
}

class _PremiumTooltip extends StatelessWidget {
  const _PremiumTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(left: 18),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF102C47),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SidebarCompactAction extends StatelessWidget {
  const _SidebarCompactAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          splashColor: Colors.white.withValues(alpha: 0.07),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderProfileButton extends StatelessWidget {
  const _HeaderProfileButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Mi perfil',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF12385F), Color(0xFF0A2037)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4EAF2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellFooter extends StatelessWidget {
  const _ShellFooter({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Color(0xFFE8EDF4))),
      ),
      child: Text(
        '© 2026 $companyName · Todos los derechos reservados',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFFABB5C3),
          fontWeight: FontWeight.w400,
          fontSize: 10.5,
          letterSpacing: 0.1,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogo para vincular la sesión local con la nube (obtener JWT de sync)
// cuando el usuario configuró el sistema sin internet y ahora quiere sincronizar.
// ---------------------------------------------------------------------------
class _CloudLinkDialog extends StatefulWidget {
  const _CloudLinkDialog({required this.onSuccess});

  final Future<void> Function() onSuccess;

  @override
  State<_CloudLinkDialog> createState() => _CloudLinkDialogState();
}

class _CloudLinkDialogState extends State<_CloudLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthProvider>();
    final error = await auth.connectToCloud(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
      return;
    }

    setState(() => _isLoading = false);
    Navigator.of(context).pop();
    await widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.cloud_sync_rounded, color: Color(0xFF0D2844), size: 22),
          SizedBox(width: 10),
          Text(
            'Vincular con la nube',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tu cuenta fue creada sin conexión a internet. Ingresa las credenciales del administrador de la nube para activar la sincronización.',
                style: TextStyle(fontSize: 13, color: Color(0xFF50607A)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo o usuario de la nube',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña de la nube',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE57373)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.link_rounded, size: 18),
          label: const Text('Vincular'),
        ),
      ],
    );
  }
}
