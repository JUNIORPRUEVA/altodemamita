import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../core/resilience/friendly_error_messages.dart';
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
import 'documents/sale_documents_dialog.dart';
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
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
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
      await SaleDocumentsDialog.show(
        context,
        detail: detail,
        initialType: SaleDocumentType.initialReceipt,
      );
    }
  }

  Future<void> _editSale(SaleSummary summary) async {
    final detail = await _controller.fetchDetail(summary.id);
    if (!mounted || detail == null) {
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
      return;
    }

    final error = await _controller.updateSale(summary.id, draft);
    if (!mounted) {
      return;
    }

    _showMessage(error ?? 'Venta actualizada correctamente.');
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
    required this.onTap,
    required this.onAction,
    required this.availableActions,
  });

  final SaleSummary sale;
  final VoidCallback onTap;
  final void Function(_SaleAdminAction) onAction;
  final List<_SaleAdminAction> availableActions;

  @override
  Widget build(BuildContext context) {
    final initials = sale.clientName.isEmpty
        ? '?'
        : sale.clientName[0].toUpperCase();
    final statusColor = _saleRowStatusColor(sale.status);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 62,
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
              const SizedBox(width: 14),
              // Client name + lot + document
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.clientName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2235),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${sale.lotDisplayCode}  ·  ${sale.clientDocumentId}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8893AA),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Status badge
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
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: sale.isPendingSync
                    ? 'Pendiente de sincronizacion'
                    : 'Sincronizado con la nube',
                child: Icon(
                  sale.isPendingSync
                      ? Icons.cloud_upload_rounded
                      : Icons.cloud_done_rounded,
                  size: 18,
                  color: sale.isPendingSync
                      ? const Color(0xFFE0A800)
                      : const Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 20),
              // Sale price + pending balance
              SizedBox(
                width: 150,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'RD\$${sale.salePrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2235),
                      ),
                    ),
                    Text(
                      'Saldo RD\$${sale.pendingBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8893AA),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Installments count
              SizedBox(
                width: 64,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${sale.generatedInstallments}/${sale.installmentCount}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B5BDB),
                      ),
                    ),
                    const Text(
                      'cuotas',
                      style: TextStyle(fontSize: 10, color: Color(0xFF8893AA)),
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
