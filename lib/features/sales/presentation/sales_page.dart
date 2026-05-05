import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/sync/row_sync_badge_policy.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../../clients/data/client_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../lots/domain/lot.dart';
import '../../settings/data/settings_repository.dart';
import '../data/sales_repository.dart';
import '../data/seller_repository.dart';
import '../domain/sale_draft.dart';
import '../domain/sale_summary.dart';
import 'sale_detail_dialog.dart';
import 'sale_form_dialog.dart';
import 'seller_form_dialog.dart';
import 'sales_controller.dart';

enum _SaleAdminAction { editSale, deleteSale, editSeller, deleteSeller }

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
  bool _isUpdatingSale = false;
  OverlayEntry? _savingOverlayEntry;

  void _debugEditLog(String message) {
    if (kDebugMode) {
      debugPrint('[SALES][EDIT] $message');
    }
  }

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
    final canUpdateSales = auth.canAccess(
      PermissionCatalog.sales,
      PermissionAction.update,
    );
    final canDeleteSales = auth.canAccess(
      PermissionCatalog.sales,
      PermissionAction.delete,
    );
    final canUpdateSellers = auth.canAccess(
      PermissionCatalog.sellers,
      PermissionAction.update,
    );
    final canDeleteSellers = auth.canAccess(
      PermissionCatalog.sellers,
      PermissionAction.delete,
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
                canUpdateSellers: canUpdateSellers,
                canDeleteSellers: canDeleteSellers,
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
    required bool canUpdateSellers,
    required bool canDeleteSellers,
  }) {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.loadError != null) {
      final failure = _controller.loadError!;
      return InlineModuleRecoveryCard(
        title: failure.title,
        message: failure.message,
        details: failure.details,
        suggestions: failure.suggestions,
        onRetry: _runSearch,
      );
    }

    if (_controller.sales.isEmpty) {
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
                    onPressed: _controller.isSaving ? null : _createSale,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear venta'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: ListView.separated(
        itemCount: _controller.sales.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
        itemBuilder: (context, index) {
          final sale = _controller.sales[index];
          return _SaleRow(
            sale: sale,
            hasInternet: _hasInternet,
            onTap: () => _openDetail(sale),
            onAction: (action) => _handleAdminAction(action, sale),
            availableActions: [
              if (canUpdateSales) _SaleAdminAction.editSale,
              if (canDeleteSales) _SaleAdminAction.deleteSale,
              if (canUpdateSellers) _SaleAdminAction.editSeller,
              if (canDeleteSellers) _SaleAdminAction.deleteSeller,
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAdminAction(
    _SaleAdminAction action,
    SaleSummary summary,
  ) async {
    if (_controller.isSaving || _isUpdatingSale) {
      _showMessage('Ya hay una operacion de guardado en progreso.');
      return;
    }

    switch (action) {
      case _SaleAdminAction.editSale:
        await _editSale(summary);
        break;
      case _SaleAdminAction.deleteSale:
        await _confirmDeleteSale(summary);
        break;
      case _SaleAdminAction.editSeller:
        await _editSeller(summary);
        break;
      case _SaleAdminAction.deleteSeller:
        await _confirmDeleteSeller(summary);
        break;
    }
  }

  Future<void> _createSale() async {
    print('[SALES][UI] _createSale pressed');
    final draft = await SaleFormDialog.show(
      context,
      clients: _controller.clients,
      availableLots: _controller.availableLots,
      sellers: _controller.sellers,
      defaults: _controller.defaults,
      clientRepository: widget.clientRepository,
      lotRepository: widget.lotRepository,
      sellerRepository: widget.sellerRepository,
      onClientCreated: _reloadControllerSafely,
      onLotCreated: _reloadControllerSafely,
      onSellerCreated: _reloadControllerSafely,
    );
    if (!mounted || draft == null) {
      print(
        '[SALES][UI] dialog closed or not mounted (mounted=$mounted, draft=${draft != null})',
      );
      return;
    }

    print(
      '[SALES][UI] draft ready -> calling controller.createSale clientId=${draft.clientId} lotId=${draft.lotId} sellerId=${draft.sellerId} price=${draft.salePrice}',
    );
    final saleId = await _controller.createSale(draft);
    if (!mounted) {
      print('[SALES][UI] not mounted after createSale');
      return;
    }

    if (saleId == null) {
      final message =
          _controller.lastSaveErrorMessage ??
          'No se pudo guardar la venta. Revise los datos e intente nuevamente.';
      print('[SALES][UI] createSale returned null -> $message');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
      return;
    }

    print('[SALES][UI] saleId=$saleId -> fetching detail');
    final detail = await _controller.fetchDetail(saleId);
    if (!mounted) {
      print('[SALES][UI] not mounted after fetchDetail');
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

  Future<void> _editSale(SaleSummary summary) async {
    if (_controller.isSaving || _isUpdatingSale) {
      _debugEditLog(
        'blocked duplicate edit request saleId=${summary.id} (isSaving=${_controller.isSaving}, isUpdatingSale=$_isUpdatingSale)',
      );
      return;
    }

    _debugEditLog('start edit flow saleId=${summary.id}');
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted || detail == null) {
      _debugEditLog('stop: detail unavailable saleId=${summary.id}');
      return;
    }

    final currentLot = await widget.lotRepository.findById(detail.sale.lotId);
    if (!mounted || currentLot == null) {
      _showMessage('No se pudo cargar el solar actual de la venta.');
      return;
    }

    final editableLots = <Lot>[
      currentLot,
      ..._controller.availableLots.where((lot) => lot.id != currentLot.id),
    ];

    final draft = await SaleFormDialog.show(
      context,
      clients: _controller.clients,
      availableLots: editableLots,
      sellers: _controller.sellers,
      defaults: _controller.defaults,
      clientRepository: widget.clientRepository,
      lotRepository: widget.lotRepository,
      sellerRepository: widget.sellerRepository,
      initialDraft: SaleDraft(
        clientId: detail.sale.clientId,
        lotId: detail.sale.lotId,
        userId: detail.sale.userId,
        sellerId: detail.sale.sellerId,
        saleDate: detail.sale.saleDate,
        salePrice: detail.sale.salePrice,
        downPaymentPercentage: detail.sale.downPaymentPercentage,
        requiredInitialPayment: detail.sale.requiredInitialPayment,
        initialPaymentPaid: detail.sale.paidInitialPayment,
        initialPaymentMethod: detail.initialPaymentMethod,
        minimumReserveAmount: detail.sale.minimumReserveAmount,
        initialPaymentDeadline: detail.sale.initialPaymentDeadline,
        monthlyInterest: detail.sale.monthlyInterest,
        installmentCount: detail.sale.installmentCount,
        status: detail.sale.status,
      ),
      dialogTitle: 'Editar venta',
      submitLabel: 'Guardar cambios',
      onClientCreated: _reloadControllerSafely,
      onLotCreated: _reloadControllerSafely,
      onSellerCreated: _reloadControllerSafely,
    );
    if (!mounted || draft == null) {
      _debugEditLog('stop: dialog canceled saleId=${summary.id}');
      return;
    }

    _debugEditLog(
      'submit update saleId=${summary.id} clientId=${draft.clientId} lotId=${draft.lotId} installments=${draft.installmentCount}',
    );

    setState(() {
      _isUpdatingSale = true;
    });

    var loadingShown = false;
    try {
      if (mounted) {
        loadingShown = _showSavingOverlay();
      }

      final error = await _controller.updateSale(summary.id, draft);
      if (!mounted) {
        return;
      }

      _debugEditLog(
        error == null
            ? 'update success saleId=${summary.id}'
            : 'update failed saleId=${summary.id} error=$error',
      );
      _showMessage(error ?? 'Venta actualizada correctamente.');
    } finally {
      if (mounted) {
        if (loadingShown) {
          _hideSavingOverlay();
        }
        setState(() {
          _isUpdatingSale = false;
        });
      }
    }
  }

  bool _showSavingOverlay() {
    if (_savingOverlayEntry != null) {
      return false;
    }

    final overlayState = Overlay.of(context, rootOverlay: true);

    _savingOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            const ModalBarrier(
              dismissible: false,
              color: Color(0x66000000),
            ),
            Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text('Guardando cambios de la venta...'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(_savingOverlayEntry!);
    return true;
  }

  void _hideSavingOverlay() {
    _savingOverlayEntry?.remove();
    _savingOverlayEntry = null;
  }

  Future<void> _confirmDeleteSale(SaleSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar venta'),
          content: Text(
            'Se eliminara la venta de ${summary.clientName} para ${summary.lotDisplayCode}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
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

  Future<void> _editSeller(SaleSummary summary) async {
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted || detail == null) {
      return;
    }

    final sellerId = detail.sale.sellerId;
    if (sellerId == null) {
      _showMessage('Esta venta no tiene vendedor asignado.');
      return;
    }

    final seller = await widget.sellerRepository.getById(sellerId);
    if (!mounted || seller == null) {
      _showMessage('No se pudo cargar el vendedor de la venta.');
      return;
    }

    final updatedSeller = await SellerFormDialog.show(
      context,
      initialSeller: seller,
    );
    if (!mounted || updatedSeller == null) {
      return;
    }

    try {
      await widget.sellerRepository.update(updatedSeller);
      await _controller.load(query: _controller.currentQuery);
      if (!mounted) {
        return;
      }
      _showMessage('Vendedor actualizado correctamente.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'actualizar el vendedor',
        error,
        module: 'ventas',
      );
    }
  }

  Future<void> _confirmDeleteSeller(SaleSummary summary) async {
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted || detail == null) {
      return;
    }

    final sellerId = detail.sale.sellerId;
    final sellerName = detail.sellerName;
    if (sellerId == null || sellerName == null || sellerName.isEmpty) {
      _showMessage('Esta venta no tiene vendedor asignado.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar vendedor'),
          content: Text(
            'Se eliminara el vendedor $sellerName. La venta quedara sin vendedor asignado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.sellerRepository.delete(sellerId);
      await _controller.load(query: _controller.currentQuery);
      if (!mounted) {
        return;
      }
      _showMessage('Vendedor eliminado correctamente.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'eliminar el vendedor',
        error,
        module: 'ventas',
      );
    }
  }

  Future<void> _openDetail(SaleSummary summary) async {
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted || detail == null) {
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

// ── Compact sale row ──────────────────────────────────────────────────────────

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.sale,
    required this.hasInternet,
    required this.onTap,
    required this.onAction,
    required this.availableActions,
  });

  final SaleSummary sale;
  final bool hasInternet;
  final VoidCallback onTap;
  final void Function(_SaleAdminAction) onAction;
  final List<_SaleAdminAction> availableActions;

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
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            sale.status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
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
              // Admin popup menu
              if (availableActions.isNotEmpty)
                PopupMenuButton<_SaleAdminAction>(
                  tooltip: '',
                  onSelected: onAction,
                  itemBuilder: (context) => availableActions
                      .map(
                        (action) => PopupMenuItem<_SaleAdminAction>(
                          value: action,
                          child: Text(_saleAdminActionLabel(action)),
                        ),
                      )
                      .toList(growable: false),
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

String _saleAdminActionLabel(_SaleAdminAction action) {
  switch (action) {
    case _SaleAdminAction.editSale:
      return 'Editar venta';
    case _SaleAdminAction.deleteSale:
      return 'Eliminar venta';
    case _SaleAdminAction.editSeller:
      return 'Editar vendedor';
    case _SaleAdminAction.deleteSeller:
      return 'Eliminar vendedor';
  }
}

Color _saleRowStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'activa':
      return const Color(0xFF2E7D32);
    case 'reservada':
      return const Color(0xFFE67E00);
    case 'cancelada':
      return const Color(0xFFC62828);
    case 'completada':
      return const Color(0xFF1565C0);
    default:
      return const Color(0xFF455A64);
  }
}
