import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    required bool canDeleteSales,
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
            canDeleteSale: canDeleteSales,
            onDelete: () => _confirmDeleteSale(sale),
          );
        },
      ),
    );
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
    required this.canDeleteSale,
    required this.onDelete,
  });

  final SaleSummary sale;
  final bool hasInternet;
  final VoidCallback onTap;
  final bool canDeleteSale;
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
