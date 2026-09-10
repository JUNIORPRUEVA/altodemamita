import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../shared/sync/row_sync_badge_policy.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../../clients/data/client_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../data/sales_repository.dart';
import '../data/seller_repository.dart';
import '../domain/sale_draft.dart';
import '../domain/sale_summary.dart';
import 'sale_detail_dialog.dart';
import 'sale_form_dialog.dart';
import 'sales_controller.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.salesRepository,
    required this.clientRepository,
    required this.lotRepository,
    required this.sellerRepository,
    required this.settingsRepository,
  });

  final SalesRepository salesRepository;
  final ClientRepository clientRepository;
  final LotRepository lotRepository;
  final SellerRepository sellerRepository;
  final SettingsRepository settingsRepository;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  late final SalesController _controller;
  late final TextEditingController _searchController;
  bool _hasInternet = true;
  int _internetProbeFailures = 0;
  StreamSubscription<List<ConnectivityResult>>? _internetSubscription;

  /// Venta creada en el ultimo submit autoritativo exitoso del modal.
  int? _createdSaleId;

  Future<void> _reloadControllerSafely() async {
    if (!mounted || _controller.isDisposed) {
      return;
    }
    await _controller.load(query: _controller.currentQuery);
  }

  @override
  void initState() {
    super.initState();
    _controller = SalesController(
      salesRepository: widget.salesRepository,
      clientRepository: widget.clientRepository,
      lotRepository: widget.lotRepository,
      sellerRepository: widget.sellerRepository,
      settingsRepository: widget.settingsRepository,
    );
    _searchController = TextEditingController();
    _internetSubscription = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(_refreshInternetStatus());
    });
    unawaited(_refreshInternetStatus());
    _controller.load();
  }

  @override
  void dispose() {
    unawaited(_internetSubscription?.cancel());
    _internetSubscription = null;
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreateSales = auth.canAccess(
      PermissionCatalog.sales,
      PermissionAction.create,
    );
    final canDeleteSales = auth.canAccess(
      PermissionCatalog.sales,
      PermissionAction.delete,
    );
    final canUpdateSales = auth.canAccess(
      PermissionCatalog.sales,
      PermissionAction.update,
    );

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => BaseLayout(
        title: 'Ventas',
        child: Column(
          children: [
            // ── Search bar ──────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;

                  final searchField = SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Buscar por cliente, cédula, solar o estado…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD0D7E4),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD0D7E4),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _runSearch(),
                    ),
                  );

                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: !canCreateSales || _controller.isSaving
                            ? null
                            : _createSale,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          _controller.isSaving ? 'Guardando…' : 'Nueva venta',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: _runSearch,
                        child: const Text(
                          'Buscar',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: _clearSearch,
                        child: const Text(
                          'Limpiar',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchField,
                        const SizedBox(height: 10),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                },
              ),
            ),
            // ── List ──────────────────────────────────────────────────
            Expanded(
              child: _buildBody(
                canCreateSales: canCreateSales,
                canUpdateSales: canUpdateSales,
                canDeleteSales: canDeleteSales,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required bool canCreateSales,
    required bool canUpdateSales,
    required bool canDeleteSales,
  }) {
    final controller = _controller;
    final hasVisible = controller.hasVisibleData;

    // Pantalla fatal REAL: solo cuando NO hay ningun dato visible y la carga
    // autoritativa inicial de la lista completa fallo. Un refresh fallido con
    // datos NUNCA llega aqui (se conserva la lista + aviso no bloqueante).
    if (controller.loadError != null) {
      final failure = controller.loadError!;
      return InlineModuleRecoveryCard(
        title: failure.title,
        message: failure.message,
        details: failure.details,
        suggestions: failure.suggestions,
        onRetry: _retryCurrentLoad,
      );
    }

    if (!hasVisible) {
      // Carga inicial o busqueda nueva SIN datos aun: skeleton, jamas vacio.
      if (controller.isLoading) {
        return const _SalesLoadingView();
      }
      // Busqueda fallida sin resultados que mostrar: aviso recuperable.
      if (controller.searchFailed) {
        return _SalesSearchFailedView(onRetry: _retryCurrentLoad);
      }
      // Vacio confirmado por respuesta autoritativa (solo aqui se muestra).
      if (controller.currentQuery.trim().isNotEmpty) {
        return _SalesEmptySearchView(onClear: _clearSearch);
      }
      return _SalesEmptyView(
        canCreateSales: canCreateSales,
        isSaving: controller.isSaving,
        onCreate: _createSale,
      );
    }

    // Datos visibles -> SIEMPRE se muestra la lista; el refresh (o su fallo)
    // se presenta de forma discreta y no bloquea el modulo.
    return _SalesListPane(
      controller: controller,
      hasInternet: _hasInternet,
      canUpdateSales: canUpdateSales,
      canDeleteSales: canDeleteSales,
      onRefreshRetry: _retryCurrentLoad,
      onOpenDetail: _openDetail,
      onEditSale: _editSale,
      onDeleteSale: _confirmDeleteSale,
    );
  }

  void _retryCurrentLoad() {
    _controller.load(query: _controller.currentQuery);
  }

  Future<void> _createSale() async {
    debugPrint('[SALES][UI] _createSale pressed');
    _createdSaleId = null;
    final draft = await SaleFormDialog.show(
      context,
      clients: _controller.clients,
      availableLots: _controller.availableLots,
      sellers: _controller.sellers,
      defaults: _controller.defaults,
      clientRepository: widget.clientRepository,
      lotRepository: widget.lotRepository,
      sellerRepository: widget.sellerRepository,
      // P0: la venta se crea MIENTRAS el modal permanece abierto y SOLO se
      // cierra cuando el backend confirma el exito. En fallo, el modal queda
      // abierto con los datos intactos y el mensaje de error.
      onSubmit: _submitCreateFromDialog,
      onClientCreated: _reloadControllerSafely,
      onLotCreated: _reloadControllerSafely,
      onSellerCreated: _reloadControllerSafely,
    );
    if (!mounted || draft == null) {
      debugPrint(
        '[SALES][UI] dialog closed or not mounted (mounted=$mounted, draft=${draft != null})',
      );
      return;
    }

    final saleId = _createdSaleId;
    debugPrint(
      '[SALES][UI] create confirmed saleId=$saleId -> fetching detail',
    );
    if (saleId == null) {
      debugPrint('[SALES][UI] no saleId captured after success');
      return;
    }

    final detail = await _controller.fetchDetail(saleId);
    if (!mounted) {
      debugPrint('[SALES][UI] not mounted after fetchDetail');
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Venta creada correctamente. El recibo del inicial quedó disponible.',
        ),
      ),
    );

    if (detail != null) {
      await SaleDetailDialog.show(context, detail);
    }
  }

  /// Ejecuta la creacion autoritativa desde el modal abierto. Devuelve success
  /// solo cuando el backend/PostgreSQL confirma la venta.
  Future<SaleFormSubmitOutcome> _submitCreateFromDialog(
    SaleDraft draft,
    String operationId,
  ) async {
    try {
      debugPrint(
        '[SALES][UI] submit create clientId=${draft.clientId} lotId=${draft.lotId} price=${draft.salePrice} op=$operationId',
      );
      final saleId = await widget.salesRepository.createSale(
        draft,
        operationId: operationId,
      );
      if (!mounted) {
        return const SaleFormSubmitOutcome.success();
      }
      if (saleId <= 0) {
        return const SaleFormSubmitOutcome.failure(
          'El servidor no confirmó la venta creada. Revisa los datos e intenta nuevamente.',
        );
      }
      _createdSaleId = saleId;
      await _reloadControllerSafely();
      return const SaleFormSubmitOutcome.success();
    } on BackendApiException catch (error) {
      debugPrint('[SALES][UI] create backend failure -> ${error.message}');
      return SaleFormSubmitOutcome.failure(
        _submissionFailureMessage(
          creating: true,
          statusCode: error.statusCode,
          serverMessage: error.message,
        ),
      );
    } catch (error) {
      debugPrint('[SALES][UI] create unexpected failure -> $error');
      return SaleFormSubmitOutcome.failure(
        FriendlyErrorMessages.forOperation(
          'crear la venta',
          error,
          module: 'ventas',
        ),
      );
    }
  }

  /// Mapea el error del backend a un mensaje claro y sin detalles tecnicos.
  String _submissionFailureMessage({
    required bool creating,
    required int? statusCode,
    required String serverMessage,
  }) {
    final verb = creating ? 'crear' : 'actualizar';
    final fallback = creating
        ? 'No se pudo crear la venta. Revisa los datos e intenta nuevamente.'
        : 'No se pudo actualizar la venta. Revisa los datos e intenta nuevamente.';
    final normalizedServerMessage = serverMessage.trim();

    if (statusCode == 401) {
      return 'Tu sesión expiró. Cierra la sesión y vuelve a iniciar sesión para continuar.';
    }
    if (statusCode == 403) {
      return creating
          ? 'No tienes permiso para crear ventas.'
          : 'No tienes permiso para editar ventas.';
    }
    if (statusCode == 409) {
      final lower = normalizedServerMessage.toLowerCase();
      if (creating &&
          (lower.contains('solar') ||
              lower.contains('venta') ||
              lower.contains('ya existe') ||
              lower.contains('lot'))) {
        return 'Este solar ya tiene una venta activa. Selecciona otro solar o consulta la venta existente.';
      }
      return normalizedServerMessage.isNotEmpty
          ? normalizedServerMessage
          : 'Ya existe una venta con estos datos. Revisa e intenta nuevamente.';
    }
    if (statusCode == null || statusCode >= 500) {
      return 'No pudimos $verb la venta porque el servidor no respondió. '
          'Tus datos siguen en el formulario; puedes intentar nuevamente.';
    }
    if (normalizedServerMessage.isNotEmpty) {
      return normalizedServerMessage;
    }
    return fallback;
  }

  Future<void> _confirmDeleteSale(SaleSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar venta'),
          content: Text(
            '¿Está seguro que desea eliminar esta venta de ${summary.clientName} para ${summary.lotDisplayCode}?\n\n'
            'Toma en cuenta que con ella se eliminará del sistema todo lo relacionado a dicha venta: cuotas, pagos e iniciales asociados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar venta'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final error = await _controller.deleteSale(summary.id);
    if (!mounted) {
      return;
    }

    _showMessage(error ?? 'Venta eliminada correctamente.');
  }

  Future<void> _editSale(SaleSummary summary) async {
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted) {
      return;
    }
    if (detail == null) {
      _showMessage(
        'No pudimos abrir esta venta para editarla. Actualiza la lista e intenta nuevamente.',
      );
      return;
    }

    final sale = detail.sale;
    final draft = await SaleFormDialog.show(
      context,
      clients: _controller.clients,
      availableLots: _controller.availableLots,
      sellers: _controller.sellers,
      defaults: _controller.defaults,
      clientRepository: widget.clientRepository,
      lotRepository: widget.lotRepository,
      sellerRepository: widget.sellerRepository,
      initialDraft: SaleDraft(
        clientId: sale.clientId,
        lotId: sale.lotId,
        userId: sale.userId,
        sellerId: sale.sellerId,
        saleDate: sale.saleDate,
        salePrice: sale.salePrice,
        downPaymentPercentage: sale.downPaymentPercentage,
        requiredInitialPayment: sale.requiredInitialPayment,
        initialPaymentPaid: sale.paidInitialPayment,
        initialPaymentMethod: detail.initialPaymentMethod,
        minimumReserveAmount: sale.minimumReserveAmount,
        initialPaymentDeadline: sale.initialPaymentDeadline,
        monthlyInterest: sale.monthlyInterest,
        installmentCount: sale.installmentCount,
        status: sale.status,
      ),
      dialogTitle: 'Editar venta',
      submitLabel: 'Guardar cambios',
      // P0: la edicion se ejecuta mientras el modal permanece abierto y solo
      // se cierra cuando el backend confirma la actualizacion.
      onSubmit: (draftToSave, operationId) =>
          _submitUpdateFromDialog(summary.id, draftToSave, operationId),
      onClientCreated: _reloadControllerSafely,
      onLotCreated: _reloadControllerSafely,
      onSellerCreated: _reloadControllerSafely,
    );
    if (!mounted || draft == null) {
      return;
    }

    final updatedDetail = await _controller.fetchDetail(summary.id);
    if (!mounted) {
      return;
    }
    _showMessage('Venta actualizada correctamente.');
    if (updatedDetail != null) {
      await SaleDetailDialog.show(context, updatedDetail);
    }
  }

  Future<SaleFormSubmitOutcome> _submitUpdateFromDialog(
    int saleId,
    SaleDraft draft,
    String operationId,
  ) async {
    try {
      debugPrint(
        '[SALES][UI] submit update saleId=$saleId price=${draft.salePrice} op=$operationId',
      );
      await widget.salesRepository.updateSale(
        saleId,
        draft,
        operationId: operationId,
      );
      if (mounted) {
        await _reloadControllerSafely();
      }
      return const SaleFormSubmitOutcome.success();
    } on BackendApiException catch (error) {
      debugPrint('[SALES][UI] update backend failure -> ${error.message}');
      return SaleFormSubmitOutcome.failure(
        _submissionFailureMessage(
          creating: false,
          statusCode: error.statusCode,
          serverMessage: error.message,
        ),
      );
    } catch (error) {
      debugPrint('[SALES][UI] update unexpected failure -> $error');
      return SaleFormSubmitOutcome.failure(
        FriendlyErrorMessages.forOperation(
          'actualizar la venta',
          error,
          module: 'ventas',
        ),
      );
    }
  }

  Future<void> _openDetail(SaleSummary summary) async {
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted) {
      return;
    }
    if (detail == null) {
      _showMessage(
        'No pudimos abrir el detalle de esta venta. Actualiza la lista e intenta nuevamente.',
      );
      return;
    }

    await SaleDetailDialog.show(context, detail);
  }

  void _runSearch() {
    _controller.load(query: _searchController.text.trim());
  }

  void _clearSearch() {
    _searchController.clear();
    _controller.load(query: '');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}

// ── Estados visuales P0 (cache-first / refresh no bloqueante) ────────────────

/// Carga inicial sin datos: skeleton/loader, jamas "No hay ventas".
class _SalesLoadingView extends StatelessWidget {
  const _SalesLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 16),
          Text('Cargando ventas…'),
        ],
      ),
    );
  }
}

/// Vacio CONFIRMADO por el backend para la lista completa (sin query).
class _SalesEmptyView extends StatelessWidget {
  const _SalesEmptyView({
    required this.canCreateSales,
    required this.isSaving,
    required this.onCreate,
  });

  final bool canCreateSales;
  final bool isSaving;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.point_of_sale_outlined,
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Todavía no hay ventas registradas.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Crea la primera venta para comenzar el seguimiento de iniciales, cuotas y pagos.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (canCreateSales)
                FilledButton.icon(
                  onPressed: isSaving ? null : onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear venta'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Busqueda sin resultados (respuesta autoritativa con query no vacia).
class _SalesEmptySearchView extends StatelessWidget {
  const _SalesEmptySearchView({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 14),
              Text(
                'No se encontraron ventas para tu búsqueda.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close),
                label: const Text('Limpiar búsqueda'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Busqueda fallida sin resultados que mostrar: error recuperable, no fatal.
class _SalesSearchFailedView extends StatelessWidget {
  const _SalesSearchFailedView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                'No pudimos buscar las ventas.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Revisa tu conexión e inténtalo nuevamente. Tus datos están seguros.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista visible SIEMPRE. El refresh (o su fallo) es un aviso no bloqueante.
class _SalesListPane extends StatelessWidget {
  const _SalesListPane({
    required this.controller,
    required this.hasInternet,
    required this.canUpdateSales,
    required this.canDeleteSales,
    required this.onRefreshRetry,
    required this.onOpenDetail,
    required this.onEditSale,
    required this.onDeleteSale,
  });

  final SalesController controller;
  final bool hasInternet;
  final bool canUpdateSales;
  final bool canDeleteSales;
  final VoidCallback onRefreshRetry;
  final ValueChanged<SaleSummary> onOpenDetail;
  final ValueChanged<SaleSummary> onEditSale;
  final ValueChanged<SaleSummary> onDeleteSale;

  @override
  Widget build(BuildContext context) {
    final refreshFailed = controller.refreshFailed;
    final refreshing = controller.isRefreshing && !refreshFailed;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          if (refreshFailed)
            _SalesRefreshFailedBanner(onRetry: onRefreshRetry)
          else if (refreshing)
            const _SalesRefreshingBar(),
          Expanded(
            child: ListView.separated(
              itemCount: controller.sales.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, index) {
                final sale = controller.sales[index];
                return _SaleRow(
                  sale: sale,
                  hasInternet: hasInternet,
                  onTap: () => onOpenDetail(sale),
                  canUpdateSale: canUpdateSales,
                  canDeleteSale: canDeleteSales,
                  onEdit: () => onEditSale(sale),
                  onDelete: () => onDeleteSale(sale),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador discreto de refresh en segundo plano con datos visibles.
class _SalesRefreshingBar extends StatelessWidget {
  const _SalesRefreshingBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF2F6FB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Actualizando…',
            style: TextStyle(fontSize: 12, color: Color(0xFF4A5A72)),
          ),
        ],
      ),
    );
  }
}

/// Refresh fallido CON datos visibles: aviso no bloqueante con reintentar.
class _SalesRefreshFailedBanner extends StatelessWidget {
  const _SalesRefreshFailedBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF7E6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: Color(0xFF8A5A00),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'No pudimos actualizar. Mostrando datos guardados.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B4A00)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Compact sale row ──────────────────────────────────────────────────────────

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.sale,
    required this.hasInternet,
    required this.onTap,
    required this.canUpdateSale,
    required this.canDeleteSale,
    required this.onEdit,
    required this.onDelete,
  });

  final SaleSummary sale;
  final bool hasInternet;
  final VoidCallback onTap;
  final bool canUpdateSale;
  final bool canDeleteSale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final initials = sale.clientName.isEmpty
        ? '?'
        : sale.clientName[0].toUpperCase();
    final statusColor = _saleRowStatusColor(sale.status);
    final dateLabel = _formatShortDate(context, sale.saleDate);
    final isFailed = sale.syncStatus.trim().toLowerCase() == 'failed';
    final showSyncBadge = shouldShowRowSyncBadge(
      hasInternet: hasInternet,
      syncStatus: sale.syncStatus,
      isFailed: isFailed,
    );
    final syncBadgeLabel = rowSyncBadgeLabel(
      syncStatus: sale.syncStatus,
      isFailed: isFailed,
    );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE8EFF8),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sale.clientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A2235),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'RD\$${sale.salePrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2235),
                          ),
                        ),
                        if (showSyncBadge && syncBadgeLabel != null) ...[
                          const SizedBox(width: 8),
                          RowSyncListBadge(label: syncBadgeLabel),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _saleRowStatusLabel(sale.status),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                        if ((sale.status == 'apartado' ||
                                sale.status == 'inicial_incompleto') &&
                            sale.paidApartadoPayment > 0.009) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE67E00).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Apartado: RD\$${sale.paidApartadoPayment.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE67E00),
                              ),
                            ),
                          ),
                        ],
                        if (sale.overdueInstallmentCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC62828).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'En atrasos (${sale.overdueInstallmentCount})',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC62828),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sale.lotDisplayCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8893AA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8893AA),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (canUpdateSale)
                IconButton(
                  tooltip: 'Editar venta',
                  icon: const Icon(Icons.edit_outlined),
                  color: const Color(0xFF49608C),
                  onPressed: onEdit,
                ),
              if (canDeleteSale)
                IconButton(
                  tooltip: 'Eliminar venta',
                  icon: const Icon(Icons.delete_outline),
                  color: const Color(0xFFB42318),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatShortDate(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context).formatShortDate(date);
}

String _saleRowStatusLabel(String status) {
  return switch (status.toLowerCase()) {
    'apartado' => 'Apartado',
    'inicial_incompleto' => 'Inicial incompleto',
    'activa' => 'Activa',
    'pagada' => 'Pagada',
    'cancelada' => 'Cancelada',
    'reservada' => 'Reservada',
    'completada' => 'Completada',
    _ => status,
  };
}

Color _saleRowStatusColor(String status) {
  return switch (status.toLowerCase()) {
    'activa' => const Color(0xFF2E7D32),
    'pagada' => const Color(0xFF1565C0),
    'apartado' || 'inicial_incompleto' => const Color(0xFFE67E00),
    'cancelada' => const Color(0xFFC62828),
    'reservada' => const Color(0xFF6A1B9A),
    'completada' => const Color(0xFF1565C0),
    _ => const Color(0xFF455A64),
  };
}
