import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../domain/payment_sale_option.dart';

/// Lista + acceso a PAGOS en el layout compacto (PWA / móvil / tableta).
class PaymentsMobileView extends StatefulWidget {
  const PaymentsMobileView({
    super.key,
    required this.sales,
    required this.searchResults,
    required this.isLoading,
    required this.isSearching,
    required this.isRefreshing,
    required this.refreshFailed,
    required this.loadErrorTitle,
    required this.searchErrorTitle,
    required this.canCreatePayments,
    required this.canRegisterPayment,
    required this.isSaving,
    required this.selectedSaleId,
    required this.onSearch,
    required this.onClearSearch,
    required this.onRetry,
    required this.onRegisterPayment,
    required this.onSelectSale,
    required this.onOpenSale,
  });

  final List<PaymentSaleOption> sales;
  final List<PaymentSaleOption> searchResults;
  final bool isLoading;
  final bool isSearching;
  final bool isRefreshing;
  final bool refreshFailed;
  final String? loadErrorTitle;
  final String? searchErrorTitle;
  final bool canCreatePayments;
  final bool canRegisterPayment;
  final bool isSaving;
  final int? selectedSaleId;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onRetry;
  final VoidCallback onRegisterPayment;
  final ValueChanged<int> onSelectSale;
  final ValueChanged<int> onOpenSale;

  @override
  State<PaymentsMobileView> createState() => _PaymentsMobileViewState();
}

class _PaymentsMobileViewState extends State<PaymentsMobileView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {});
    widget.onClearSearch();
  }

  void _handleSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();

    final query = value.trim();
    if (query.isEmpty) {
      widget.onClearSearch();
      return;
    }
    if (query.length < 2) {
      widget.onClearSearch();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) {
        return;
      }
      widget.onSearch(query);
    });
  }

  List<PaymentSaleOption> get _visibleSales {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return widget.sales;
    }

    final lowerQuery = query.toLowerCase();
    final normalizedQuery = _normalizeSearchValue(query);
    final localMatches = widget.sales.where((sale) {
      final haystack = [
        sale.clientName,
        sale.clientPhone,
        sale.clientDocumentId,
        sale.lotDisplayCode,
      ].join(' ').toLowerCase();
      final normalizedHaystack = _normalizeSearchValue(
        [
          sale.clientPhone,
          sale.clientDocumentId,
          sale.lotDisplayCode,
        ].join(' '),
      );
      return haystack.contains(lowerQuery) ||
          (normalizedQuery.isNotEmpty &&
              normalizedHaystack.contains(normalizedQuery));
    });

    final merged = <PaymentSaleOption>[];
    final seenSaleIds = <int>{};
    for (final sale in [...localMatches, ...widget.searchResults]) {
      if (seenSaleIds.add(sale.saleId)) {
        merged.add(sale);
      }
    }
    return merged;
  }

  String _normalizeSearchValue(String value) {
    return value.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final fabEnabled =
        widget.canCreatePayments &&
        widget.canRegisterPayment &&
        !widget.isSaving &&
        widget.selectedSaleId != null;

    return Scaffold(
      backgroundColor: MobileUi.background,
      body: Column(
        children: [
          Container(
            color: MobileUi.surface,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: MobileSearchRow(
              controller: _searchController,
              hintText: 'Buscar por cliente, cedula, telefono o solar...',
              onChanged: _handleSearchChanged,
              onSubmitted: widget.onSearch,
              onClear: _clearSearch,
            ),
          ),
          if (widget.refreshFailed)
            MobileRefreshFailedBanner(onRetry: widget.onRetry)
          else if (widget.isRefreshing || widget.isSearching)
            const MobileRefreshingBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: widget.canCreatePayments
          ? FloatingActionButton(
              tooltip: fabEnabled
                  ? 'Registrar pago'
                  : 'Selecciona una venta para registrar pago',
              backgroundColor: fabEnabled
                  ? MobileUi.primary
                  : MobileUi.primary.withValues(alpha: 0.22),
              foregroundColor: fabEnabled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.65),
              elevation: fabEnabled ? 4 : 0,
              onPressed: fabEnabled ? widget.onRegisterPayment : null,
              child: const Icon(Icons.payments_outlined),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (widget.loadErrorTitle != null) {
      return MobileSearchFailedView(
        title: widget.loadErrorTitle!,
        onRetry: widget.onRetry,
      );
    }
    if (widget.isLoading && widget.sales.isEmpty) {
      return const MobileLoadingView(label: 'Cargando pagos...');
    }

    final visibleSales = _visibleSales;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    if (widget.searchErrorTitle != null && hasQuery) {
      return MobileSearchFailedView(
        title: widget.searchErrorTitle!,
        onRetry: () => widget.onSearch(_searchController.text.trim()),
      );
    }

    if (visibleSales.isEmpty) {
      if (hasQuery) {
        return MobileEmptySearchView(
          message: 'No se encontraron ventas con esa búsqueda.',
          onClear: _clearSearch,
        );
      }
      return MobileEmptyState(
        title: 'No hay ventas con cobro pendiente',
        message: 'Cuando existan cuotas por cobrar aparecerán aquí.',
        icon: Icons.account_balance_wallet_outlined,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        MobileUi.listPadding,
        8,
        MobileUi.listPadding,
        88,
      ),
      itemCount: visibleSales.length,
      separatorBuilder: (_, _) => const SizedBox(height: MobileUi.rowGap),
      itemBuilder: (context, index) {
        final sale = visibleSales[index];
        return _PaymentSaleMobileRow(
          sale: sale,
          remaining: sale.pendingBalance + sale.pendingInitialPayment,
          selected: widget.selectedSaleId == sale.saleId,
          onTap: () => widget.onSelectSale(sale.saleId),
          onOpenSale: () => widget.onOpenSale(sale.saleId),
        );
      },
    );
  }
}

class _PaymentSaleMobileRow extends StatelessWidget {
  const _PaymentSaleMobileRow({
    required this.sale,
    required this.remaining,
    required this.selected,
    required this.onTap,
    required this.onOpenSale,
  });

  final PaymentSaleOption sale;
  final double remaining;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenSale;

  @override
  Widget build(BuildContext context) {
    final background = selected ? const Color(0xFFEAF2FF) : MobileUi.surface;
    final borderColor = selected ? MobileUi.primary : MobileUi.border;

    return Material(
      color: background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MobileUi.radiusCard),
        side: BorderSide(color: borderColor, width: selected ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MobileInitialAvatar(name: sale.clientName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sale.clientName.trim().isEmpty
                          ? 'Cliente sin nombre'
                          : sale.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileUi.itemTitle,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Solar ${sale.lotDisplayCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileUi.itemSubtitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _clientMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileUi.itemMeta,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Pendiente', style: MobileUi.amountLabel),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        MobileUi.money(remaining),
                        maxLines: 1,
                        style: MobileUi.amountSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Ver detalle',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: MobileUi.textSecondary,
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: onOpenSale,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _clientMeta {
    final values = <String>[
      if (sale.clientDocumentId.trim().isNotEmpty)
        'Cédula ${sale.clientDocumentId}',
      if (sale.clientPhone.trim().isNotEmpty) sale.clientPhone,
    ];
    return values.isEmpty ? 'Sin documento' : values.join(' · ');
  }
}
