import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../domain/payment_sale_option.dart';

/// Lista + acceso a PAGOS en el layout compacto (patrón Ventas).
///
/// La lista muestra las ventas con cobro activo (cola de trabajo). Al tocar una
/// venta se abre su historial de pagos a pantalla completa (navegación
/// inmediata, con la consulta resuelta dentro de esa pantalla).
class PaymentsMobileView extends StatefulWidget {
  const PaymentsMobileView({
    super.key,
    required this.sales,
    required this.isLoading,
    required this.isRefreshing,
    required this.refreshFailed,
    required this.loadErrorTitle,
    required this.canCreatePayments,
    required this.onSearch,
    required this.onClearSearch,
    required this.onRetry,
    required this.onRegisterPayment,
    required this.onOpenSale,
  });

  final List<PaymentSaleOption> sales;
  final bool isLoading;
  final bool isRefreshing;
  final bool refreshFailed;
  final String? loadErrorTitle;
  final bool canCreatePayments;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onRetry;
  final VoidCallback onRegisterPayment;
  final ValueChanged<int> onOpenSale;

  @override
  State<PaymentsMobileView> createState() => _PaymentsMobileViewState();
}

class _PaymentsMobileViewState extends State<PaymentsMobileView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    widget.onClearSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileUi.background,
      body: Column(
        children: [
          Container(
            color: MobileUi.surface,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: MobileSearchRow(
              controller: _searchController,
              hintText: 'Buscar ventas por cliente o solar…',
              onSubmitted: widget.onSearch,
              onClear: _clearSearch,
            ),
          ),
          if (widget.refreshFailed)
            MobileRefreshFailedBanner(onRetry: widget.onRetry)
          else if (widget.isRefreshing)
            const MobileRefreshingBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: widget.canCreatePayments
          ? FloatingActionButton(
              tooltip: 'Registrar pago',
              onPressed: widget.onRegisterPayment,
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
      return const MobileLoadingView(label: 'Cargando pagos…');
    }
    if (widget.sales.isEmpty) {
      if (_searchController.text.trim().isNotEmpty) {
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
      itemCount: widget.sales.length,
      separatorBuilder: (_, _) => const SizedBox(height: MobileUi.rowGap),
      itemBuilder: (context, index) {
        final sale = widget.sales[index];
        final remaining = sale.pendingBalance + sale.pendingInitialPayment;
        return MobileEntityRow(
          title: sale.clientName.trim().isEmpty
              ? 'Cliente sin nombre'
              : sale.clientName,
          subtitle: 'Solar ${sale.lotDisplayCode}',
          meta: 'Cédula ${sale.clientDocumentId}',
          leading: MobileInitialAvatar(name: sale.clientName),
          trailing: SizedBox(
            width: 108,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pendiente',
                  style: MobileUi.amountLabel,
                ),
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
          onTap: () => widget.onOpenSale(sale.saleId),
        );
      },
    );
  }
}
