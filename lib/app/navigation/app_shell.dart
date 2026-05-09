import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/config/app_flags.dart';
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
import '../../repositories/company_profiles_sync_repository.dart';
import '../../repositories/installments_sync_repository.dart';
import '../../repositories/payments_sync_repository.dart';
import '../../repositories/permissions_sync_repository.dart';
import '../../repositories/products_sync_repository.dart';
import '../../repositories/role_permissions_sync_repository.dart';
import '../../repositories/roles_sync_repository.dart';
import '../../repositories/sales_sync_repository.dart';
import '../../repositories/users_sync_repository.dart';
import '../../repositories/user_roles_sync_repository.dart';
import '../../services/realtime_sync_service.dart';
import '../../services/cloud_reset_service.dart';
import '../../services/sync/sync_conflict_service.dart';
import '../../services/sync/sync_config_repository.dart';
import '../../services/sync/sync_manager.dart';
import '../../services/sync/sync_queue_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/widgets/base_layout.dart';
import '../../shared/widgets/dangerous_action_confirm_dialog.dart';
import 'app_module.dart';
import 'sync_visual_state.dart';

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
];

const double _sidebarCollapsedWidth = 96;
const double _sidebarExpandedWidth = 288;
const double _sidebarSafeExpandedContentWidth = 240;

bool _shellTooltipsEnabled() => !Platform.isWindows;

bool _hasOverlay(BuildContext context) =>
    Overlay.maybeOf(context, rootOverlay: true) != null;

Widget _safeTooltip({
  required BuildContext context,
  required Widget child,
  required String message,
}) {
  if (!_shellTooltipsEnabled() || !_hasOverlay(context)) {
    return child;
  }

  return Tooltip(message: message, child: child);
}

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
  final RolesSyncRepository _rolesSyncRepository = RolesSyncRepository();
  final UserRolesSyncRepository _userRolesSyncRepository =
      UserRolesSyncRepository();
  final RolePermissionsSyncRepository _rolePermissionsSyncRepository =
      RolePermissionsSyncRepository();
  final PermissionsSyncRepository _permissionsSyncRepository =
      PermissionsSyncRepository();
  final CompanyProfilesSyncRepository _companyProfilesSyncRepository =
      CompanyProfilesSyncRepository();
  final SalesSyncRepository _salesSyncRepository = SalesSyncRepository();
  final InstallmentsSyncRepository _installmentsSyncRepository =
      InstallmentsSyncRepository();
  final PaymentsSyncRepository _paymentsSyncRepository =
      PaymentsSyncRepository();
  late final SyncService _syncService = SyncService(
    repositories: [
      _usersSyncRepository,
      _rolesSyncRepository,
      _userRolesSyncRepository,
      _rolePermissionsSyncRepository,
      _permissionsSyncRepository,
      _companyProfilesSyncRepository,
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
  bool _hasInternet = true;
  int _internetProbeFailures = 0;
  StreamSubscription<List<ConnectivityResult>>? _internetSubscription;
  Timer? _sidebarAutoCollapseTimer;
  AuthProvider? _authProvider;
  bool _lastAuthIsAuthenticated = false;
  bool _lastAuthIsOnline = false;

  @override
  void initState() {
    super.initState();
    _restoreNavigationPreferences();
    _loadCompanyDisplayName();
    _internetSubscription = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(_refreshInternetStatus());
    });
    unawaited(_refreshInternetStatus());
    _syncQueueService.setCloudSessionExpiredHandler(_handleCloudSessionExpired);
    _syncManager.addListener(_handleSyncManagerChanged);
    unawaited(_syncManager.start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAuthProvider = context.read<AuthProvider>();
    if (identical(_authProvider, nextAuthProvider)) {
      return;
    }

    _authProvider?.removeListener(_handleAuthProviderChanged);
    _authProvider = nextAuthProvider;
    _lastAuthIsAuthenticated = nextAuthProvider.isAuthenticated;
    _lastAuthIsOnline = nextAuthProvider.isOnline;
    _authProvider?.addListener(_handleAuthProviderChanged);
  }

  @override
  void dispose() {
    _sidebarAutoCollapseTimer?.cancel();
    _sidebarAutoCollapseTimer = null;
    unawaited(_internetSubscription?.cancel());
    _internetSubscription = null;
    _syncQueueService.setCloudSessionExpiredHandler(null);
    _authProvider?.removeListener(_handleAuthProviderChanged);
    _authProvider = null;
    _syncManager.removeListener(_handleSyncManagerChanged);
    _syncManager.dispose();
    _syncConflictService.dispose();
    _realtimeSyncService.dispose();
    _syncQueueService.dispose();
    _syncService.dispose();
    super.dispose();
  }

  void _handleAuthProviderChanged() {
    final auth = _authProvider;
    if (auth == null || !mounted) {
      return;
    }

    final becameAuthenticated =
        !_lastAuthIsAuthenticated && auth.isAuthenticated;
    final recoveredOnline = !_lastAuthIsOnline && auth.isOnline;
    _lastAuthIsAuthenticated = auth.isAuthenticated;
    _lastAuthIsOnline = auth.isOnline;

    if (!auth.isAuthenticated) {
      return;
    }

    if (becameAuthenticated || recoveredOnline) {
      unawaited(_resumeSyncPipelineAfterAuth());
    }
  }

  Future<void> _resumeSyncPipelineAfterAuth() async {
    _syncService.resetCloudSession();
    await _syncManager.start();
    await _syncQueueService.syncPending();
  }

  void _handleSyncManagerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _refreshInternetStatus() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasNetworkInterface = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasNetworkInterface) {
        _internetProbeFailures = 0;
        _setInternetStatus(false);
        return;
      }

      final lookup = await InternetAddress.lookup(
        'one.one.one.one',
      ).timeout(const Duration(seconds: 2));
      _internetProbeFailures = 0;
      _setInternetStatus(
        lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty,
      );
    } on TimeoutException {
      _internetProbeFailures += 1;
      if (_internetProbeFailures >= 2) {
        _setInternetStatus(false);
      }
    } on SocketException {
      _internetProbeFailures += 1;
      if (_internetProbeFailures >= 2) {
        _setInternetStatus(false);
      }
    } catch (_) {
      _internetProbeFailures = 0;
      _setInternetStatus(true);
    }
  }

  void _setInternetStatus(bool value) {
    if (!mounted || _hasInternet == value) {
      return;
    }
    setState(() {
      _hasInternet = value;
    });
  }

  Future<void> _restoreNavigationPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    // Default to collapsed sidebar so the workspace is maximised. The user can
    // manually expand it via the toggle, but it auto-collapses on navigation.
    final nextSidebarExpanded = false;
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
    _syncSidebarAutoCollapseTimer();
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
      // Auto-collapse the sidebar on navigation to keep the layout clean.
      if (_isSidebarExpanded) {
        _isSidebarExpanded = false;
        unawaited(_persistNavigationPreferences());
      }
    });
  }

  void _openInstallments(int? saleId) {
    setState(() {
      _selectedModule = AppModule.installments;
      _selectedInstallmentsSaleId = saleId;
      if (_isSidebarExpanded) {
        _isSidebarExpanded = false;
        unawaited(_persistNavigationPreferences());
      }
    });
  }

  void _openPayments(int? saleId) {
    setState(() {
      _selectedModule = AppModule.payments;
      _selectedPaymentsSaleId = saleId;
      if (_isSidebarExpanded) {
        _isSidebarExpanded = false;
        unawaited(_persistNavigationPreferences());
      }
    });
  }

  Future<void> _toggleSidebar() async {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
    _syncSidebarAutoCollapseTimer();
    await _persistNavigationPreferences();
  }

  void _syncSidebarAutoCollapseTimer() {
    _sidebarAutoCollapseTimer?.cancel();
    _sidebarAutoCollapseTimer = null;

    if (!_isSidebarExpanded) {
      return;
    }

    _sidebarAutoCollapseTimer = Timer(const Duration(minutes: 5), () {
      if (!mounted || !_isSidebarExpanded) {
        return;
      }

      setState(() {
        _isSidebarExpanded = false;
      });
      unawaited(_persistNavigationPreferences());
    });
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

  Future<void> _refreshDeviceAccess({bool claimPrimary = false}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (claimPrimary) {
      // Acción peligrosa: requiere confirmación expresa + contraseña.
      final confirmed = await DangerousActionConfirmDialog.show(
        context,
        title: 'Reclamar esta PC como principal',
        warning:
            'Esta acción es PELIGROSA y puede dañar el sistema si se ejecuta '
            'sin preparación. Antes de continuar:\n\n'
            '• Debes haber contactado al desarrollador para coordinar el '
            'traslado de la PC principal y entender los pasos a seguir.\n'
            '• La otra PC dejará de tener permiso de escritura.\n'
            '• Para que el traslado funcione correctamente, primero hay que '
            'restablecer (reset completo) la app local en la otra PC, de lo '
            'contrario podrías generar conflictos de sincronización y '
            'pérdida de datos.\n'
            '• Si no estás seguro de lo que haces, cancela y consulta antes.',
        confirmLabel: 'Sí, reclamar esta PC',
      );
      if (!mounted || !confirmed) {
        return;
      }

      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PrimaryEditorPasswordDialog(),
      );
      if (!mounted || password == null) {
        return;
      }

      final authService = context.read<AuthProvider>().authService;
      final isValid = await authService.verifyAdminPassword(password: password);
      if (!mounted) {
        return;
      }
      if (!isValid) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Contrasena invalida. Solo un editor principal puede autorizar esta accion.',
            ),
          ),
        );
        return;
      }
    }

    try {
      if (claimPrimary) {
        await SystemConfigService.instance.registerCurrentDevice(
          claimPrimary: true,
        );
      }
      await SystemConfigService.instance.refresh();

      if (!mounted) {
        return;
      }

      final systemConfig = SystemConfigService.instance;
      final message = systemConfig.canWrite
          ? (claimPrimary
                ? 'Esta PC quedo autorizada para escribir.'
                : 'Estado del dispositivo actualizado.')
          : (systemConfig.deviceWriteReason.isEmpty
                ? 'Esta PC sigue sin permiso de escritura.'
                : systemConfig.deviceWriteReason);

      messenger?.showSnackBar(SnackBar(content: Text(message)));

      // Si se acaba de ganar permiso de escritura, forzar sync inmediato
      // para vaciar la cola de items que estaban bloqueados por WRITE_BLOCKED.
      if (systemConfig.canWrite && claimPrimary) {
        unawaited(_syncService.syncNow());
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar el estado de esta PC.'),
        ),
      );
    }
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
    // El usuario permanece autenticado localmente; solo la sync queda pendiente.
    authProvider.markCloudSessionExpired();
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
        return SettingsPage(
          onCompanyInfoChanged: _loadCompanyDisplayName,
          onRunSyncRecovery: _runSyncRecoveryFromSettings,
          onRunPostAuthorizationRecovery:
              _runPostAuthorizationRecoveryFromSettings,
          onResetLocalDeviceIdentity: _resetLocalDeviceIdentityFromSettings,
          onResetBusinessData: _resetBusinessDataFromSettings,
          onResetLocalOnly: _resetLocalOnlyFromSettings,
        );
    }
  }

  Future<String> _runSyncRecoveryFromSettings() async {
    if (!allowManualCloudRestore) {
      return 'Operacion bloqueada: ALLOW_MANUAL_CLOUD_RESTORE=false.';
    }
    if (isProductionMode) {
      return 'Operacion bloqueada: disponible solo en modo developer.';
    }

    // Verificar si el JWT está configurado
    final settings = await SyncConfigRepository().loadSettings();
    if (!settings.isConfigured) {
      if (settings.baseUrl.trim().isEmpty) {
        return 'No hay URL de servidor configurada. Contacta al administrador del sistema.';
      }
      return 'No hay sesion de nube activa (JWT vacio). '
          'Cierra sesion, asegurate de tener internet y vuelve a iniciar sesion '
          'para que el sistema guarde tus credenciales de nube.';
    }

    // Intentar sincronizacion completa (subidas + descargas)
    final report = await _syncService.syncNow(forceFullDownload: true);

    if (report.wasSkipped) {
      return 'Sincronizacion bloqueada: ${report.errorMessage ?? 'razon desconocida'}. '
          'Si el error dice "no autorizada", activa esta PC desde el panel web.';
    }

    if (report.hadConnectivityError) {
      return 'Error de conexion con el servidor. Verifica que el backend este en linea '
          'y que esta PC tenga acceso a internet. '
          '${report.pendingRecords > 0 ? "${report.pendingRecords} registros siguen en espera." : ""}';
    }

    final writeStateMessage = SystemConfigService.instance.canWrite
        ? ''
        : ' Esta PC no esta autorizada para subir datos: activa su ID desde el panel web.';
    return 'Sincronizacion completada. '
        'Subidos: ${report.uploadedRecords}, descargados: ${report.downloadedRecords}'
        '${report.pendingRecords > 0 ? ", pendientes: ${report.pendingRecords}" : ""}'
        '.$writeStateMessage';
  }

  Future<String> _runPostAuthorizationRecoveryFromSettings() async {
    if (!allowManualCloudRestore) {
      return 'Operacion bloqueada: ALLOW_MANUAL_CLOUD_RESTORE=false.';
    }
    if (isProductionMode) {
      return 'Operacion bloqueada: disponible solo en modo developer.';
    }

    final recoverySummary = await _syncService.recoverAfterDeviceAuthorization();
    final downloaded = await _syncService.forceFullDownloadFromCloud();
    return '$recoverySummary Descarga forzada desde la nube: $downloaded registros.';
  }

  Future<String> _resetLocalDeviceIdentityFromSettings() async {
    return _syncService.resetLocalDeviceIdentityForAdmin();
  }

  Future<String> _resetLocalOnlyFromSettings() async {
    final local = await _syncService.resetLocalBusinessDataForAdmin();
    final localSummary = [
      'ventas=${local['sales'] ?? 0}',
      'clientes=${local['clients'] ?? 0}',
      'vendedores=${local['sellers'] ?? 0}',
      'cuotas=${local['installments'] ?? 0}',
      'pagos=${local['payments'] ?? 0}',
      'cola=${local['sync_queue'] ?? 0}',
    ].join(' | ');
    return 'Borrado local completado: $localSummary. La nube NO fue modificada.';
  }

  Future<String> _resetBusinessDataFromSettings() async {
    final cloudResetService = CloudResetService();
    try {
      final cloud = await cloudResetService.resetCloudDatabase();
      final local = await _syncService.resetLocalBusinessDataForAdmin();
      final localSummary = [
        'ventas=${local['sales'] ?? 0}',
        'clientes=${local['clients'] ?? 0}',
        'vendedores=${local['sellers'] ?? 0}',
        'cuotas=${local['installments'] ?? 0}',
        'pagos=${local['payments'] ?? 0}',
        'cola=${local['sync_queue'] ?? 0}',
      ].join(' | ');
      return 'Reseteo nube+local completado. Nube: ${cloud.summary}. Local: $localSummary';
    } on CloudResetException catch (error) {
      throw Exception(
        'Error al borrar la nube: ${error.message}. '
        'Si no tienes conexion usa "Borrar solo esta PC" en su lugar.',
      );
    } on SocketException {
      throw Exception(
        'Sin conexion con el servidor. '
        'Usa "Borrar solo esta PC" para borrar solo el almacenamiento local sin necesitar internet.',
      );
    } finally {
      cloudResetService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final accessibleModules = _accessibleModules(auth);
    final resolvedModule = _resolveSelectedModule(accessibleModules);
    final primaryModules = _primarySidebarModules
        .where(accessibleModules.contains)
        .toList();
    final administrationModules = _administrationSidebarModules
        .where(accessibleModules.contains)
        .toList();
    final canAccessSettings = accessibleModules.contains(AppModule.settings);
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
                if (shouldShowOfflineChip(hasInternet: _hasInternet))
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Center(child: _SyncStatusBadge(compact: true)),
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
                showSettingsAction: canAccessSettings,
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
                _DeviceWriteBlockedBanner(
                  onGoToSettings: canAccessSettings
                      ? () => _openModule(AppModule.settings)
                      : null,
                ),
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
                        showSettingsAction: canAccessSettings,
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
                              hasInternet: _hasInternet,
                              onOpenProfile: _openProfile,
                              onRefreshDeviceAccess: _refreshDeviceAccess,
                            ),
                            _DeviceWriteBlockedBanner(
                              onGoToSettings: canAccessSettings
                                  ? () => _openModule(AppModule.settings)
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
    required this.hasInternet,
    required this.onOpenProfile,
    required this.onRefreshDeviceAccess,
  });

  final AppModule selectedModule;
  final UserModel? currentUser;
  final bool hasInternet;
  final Future<void> Function() onOpenProfile;
  final Future<void> Function({bool claimPrimary}) onRefreshDeviceAccess;

  @override
  Widget build(BuildContext context) {
    final user = currentUser;
    // Note: System config badges and "Reclamar esta PC" moved to the
    // Configuración module to keep the global header clean.

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
              if (shouldShowOfflineChip(hasInternet: hasInternet))
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: _SyncStatusBadge(),
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
          const SizedBox(height: 10),
          // (Antes aquí se mostraban los badges de PC principal / permiso de
          // escritura. Se movieron al módulo de Configuración para reducir
          // ruido en el header global.)
        ],
      ),
    );
  }
}

class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const dotColor = Color(0xFF9A7676);
    const borderColor = Color(0xFFE7DCDD);
    const textColor = Color(0xFF6A5555);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 5 : 7),
          const Text(
            'Sin internet',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryEditorPasswordDialog extends StatefulWidget {
  const _PrimaryEditorPasswordDialog();

  @override
  State<_PrimaryEditorPasswordDialog> createState() =>
      _PrimaryEditorPasswordDialogState();
}

class _PrimaryEditorPasswordDialogState
    extends State<_PrimaryEditorPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _passwordController.text.trim();
    if (value.isEmpty) {
      setState(() {
        _error = 'Ingresa la contrasena del editor principal.';
      });
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_open_rounded),
      title: const Text('Autorizar editor principal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Para habilitar escritura en esta PC, confirma con la contrasena del editor principal.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            autofocus: true,
            obscureText: _obscurePassword,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Contrasena',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Validar y reclamar'),
        ),
      ],
    );
  }
}

class _ShellNavigation extends StatelessWidget {
  const _ShellNavigation({
    required this.selectedModule,
    required this.primaryModules,
    required this.administrationModules,
    required this.showSettingsAction,
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
  final bool showSettingsAction;
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
                      if (effectiveCollapsed)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (showSettingsAction) ...[
                              _SidebarCompactAction(
                                icon: Icons.settings_outlined,
                                tooltip: 'Configuración',
                                onTap: () => onSelectModule(AppModule.settings),
                              ),
                              const SizedBox(height: 8),
                            ],
                            _SidebarCompactAction(
                              icon: Icons.logout_rounded,
                              tooltip: 'Cerrar sesión',
                              onTap: () async {
                                await context.read<AuthProvider>().signOut();
                              },
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              selectedInAdministration
                                  ? 'Administración activa'
                                  : 'Módulo listo',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.44),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (showSettingsAction) ...[
                              _SidebarFooterActionButton(
                                icon: Icons.settings_outlined,
                                label: 'Configuración',
                                onTap: () => onSelectModule(AppModule.settings),
                              ),
                              const SizedBox(height: 6),
                            ],
                            _SidebarFooterActionButton(
                              icon: Icons.logout_rounded,
                              label: 'Cerrar sesión',
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
    final menuChild = _PremiumTooltip(
      message: 'Administración',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: isSelected
              ? const Color(0xFF143B61)
              : Colors.white.withValues(alpha: 0.03),
          child: SizedBox(
            height: 58,
            child: Center(
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

    if (isCollapsed) {
      if (!_hasOverlay(context)) {
        return menuChild;
      }

      return PopupMenuButton<AppModule>(
        tooltip: _shellTooltipsEnabled() ? 'Administración' : '',
        onSelected: onSelectModule,
        color: const Color(0xFF102C47),
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        offset: const Offset(56, 0),
        itemBuilder: (context) => [
          for (final module in modules)
            PopupMenuItem<AppModule>(
              value: module,
              child: Row(
                children: [
                  Icon(
                    module.icon,
                    size: 18,
                    color: module == selectedModule
                        ? const Color(0xFF83CAFF)
                        : Colors.white.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      module.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: module == selectedModule
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: menuChild,
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
                            'Clientes, solares, cuotas y vendedores',
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
    if (!_shellTooltipsEnabled() || !_hasOverlay(context)) {
      return child;
    }

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
    if (!_shellTooltipsEnabled() || !_hasOverlay(context)) {
      return Material(
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
      );
    }

    final action = Material(
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
    );

    return _safeTooltip(context: context, message: tooltip, child: action);
  }
}

class _SidebarFooterActionButton extends StatelessWidget {
  const _SidebarFooterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        splashColor: Colors.white.withValues(alpha: 0.07),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.74)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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
    if (!_shellTooltipsEnabled() || !_hasOverlay(context)) {
      return Material(
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
      );
    }

    final profileButton = Material(
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
    );

    return _safeTooltip(
      context: context,
      message: 'Mi perfil',
      child: profileButton,
    );
  }
}

/// Banner visible que aparece cuando el dispositivo actual no tiene permiso de
/// escritura en la nube (PC secundaria). Guía al usuario hacia Configuración
/// para que pueda reclamar la PC como principal.
class _DeviceWriteBlockedBanner extends StatelessWidget {
  const _DeviceWriteBlockedBanner({this.onGoToSettings});

  final VoidCallback? onGoToSettings;

  @override
  Widget build(BuildContext context) {
    final systemConfig = context.watch<SystemConfigService>();
    final auth = context.watch<AuthProvider>();

    final shouldShow =
        auth.currentUser != null &&
        !systemConfig.isReadOnly &&
        !systemConfig.canWrite &&
        systemConfig.lastDeviceValidatedAt != null;

    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final reason = systemConfig.deviceWriteReason.trim();
    final message = reason.isNotEmpty
        ? reason
      : 'Esta PC no está autorizada para sincronizar. Actívela desde Configuración.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF3CD),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFFCF66), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outlined,
            size: 16,
            color: Color(0xFF92600A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7D4E00),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onGoToSettings != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onGoToSettings,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF92600A),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Ir a Configuración →'),
            ),
          ],
        ],
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
