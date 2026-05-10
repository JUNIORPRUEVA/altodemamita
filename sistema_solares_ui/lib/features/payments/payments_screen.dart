
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/payments/payments_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _searchController = TextEditingController();
  final _inspectorScrollController = ScrollController();
  static const int _mobileDetailPageSize = 5;
  Future<PaymentsReadOnlyData>? _future;
  int _lastTick = -1;
  int _page = 1;
  String? _selectedSaleId;
  String _salesFilter = 'all';
  _MobilePaymentsDetailTab _mobileDetailTab = _MobilePaymentsDetailTab.payments;
  int _mobileDetailPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    _inspectorScrollController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = null;
    });
  }

  void _reloadFromStart() {
    setState(() {
      _page = 1;
      _future = null;
    });
  }

  void _selectSale(String saleId) {
    if (_selectedSaleId == saleId) {
      return;
    }
    setState(() {
      _selectedSaleId = saleId;
      _mobileDetailPage = 1;
      _future = null;
    });
  }

  void _goToPage(int page) {
    if (page < 1 || page == _page) {
      return;
    }
    setState(() {
      _page = page;
      _future = null;
    });
  }

  void _setSalesFilter(String filter) {
    if (_salesFilter == filter) {
      return;
    }
    setState(() {
      _salesFilter = filter;
      _mobileDetailPage = 1;
    });
  }

  void _setMobileDetailTab(_MobilePaymentsDetailTab tab) {
    if (_mobileDetailTab == tab) {
      return;
    }
    setState(() {
      _mobileDetailTab = tab;
      _mobileDetailPage = 1;
    });
  }

  void _setMobileDetailPage(int page) {
    if (page < 1 || page == _mobileDetailPage) {
      return;
    }
    setState(() {
      _mobileDetailPage = page;
    });
  }

  void _openMobilePaymentsDetail(String saleId) {
    final apiClient = context.read<ApiClient>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MobilePaymentsDetailPage(
          saleId: saleId,
          apiClient: apiClient,
        ),
      ),
    );
  }

  Future<void> _showMobileFilterSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return _MobilePaymentsFilterSheet(currentFilter: _salesFilter);
      },
    );
    if (selected == null) return;
    if (selected == '__clear__') {
      _searchController.clear();
      setState(() {
        _salesFilter = 'all';
        _mobileDetailPage = 1;
        _page = 1;
        _future = null;
      });
      return;
    }
    _setSalesFilter(selected);
    _reloadFromStart();
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.select<RealtimeController, int>((realtime) => realtime.refreshTick);
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = PaymentsService(context.read<ApiClient>()).fetchReadOnly(
        search: _searchController.text,
        page: _page,
        selectedSaleId: _selectedSaleId,
      );
    }

    return FutureBuilder<PaymentsReadOnlyData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }
        try {
          final data = snapshot.data!;
          final sales = _filterSales(data.sales);
          final selectedSale = data.selectedSale;
          final detailErrorMessage = data.detailErrorMessage;
          _selectedSaleId ??= selectedSale?.summary.id;
          final activeSelectedSale =
              selectedSale != null &&
                  sales.any((sale) => sale.id == selectedSale.summary.id)
              ? selectedSale
              : null;
          if (activeSelectedSale == null && sales.isNotEmpty) {
            final fallbackSaleId = sales.first.id;
            if (_selectedSaleId != fallbackSaleId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _selectSale(fallbackSaleId);
                }
              });
            }
          }
          final compact = MediaQuery.sizeOf(context).width < 760;
          final currency = AppNumberFormats.currency;
          final totalCollected =
              activeSelectedSale?.history.fold<double>(
                0,
                (total, payment) => total + payment.amount,
              ) ??
              0;
          final averageTicket =
              activeSelectedSale == null || activeSelectedSale.history.isEmpty
              ? 0.0
              : totalCollected / activeSelectedSale.history.length;
          final methods =
              activeSelectedSale?.history
                  .map((payment) => payment.method.trim())
                  .where((method) => method.isNotEmpty)
                  .toSet() ??
              <String>{};
          final lastPaymentDate = activeSelectedSale?.history
              .map((payment) => payment.paymentDate)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (latest, current) => latest == null || current.isAfter(latest)
                    ? current
                    : latest,
              );
          final selectedSummary = activeSelectedSale?.summary;
          final visibleOutstanding = sales.fold<double>(
            0,
            (total, sale) => total + sale.pendingBalance,
          );
          final visiblePayments = sales.fold<int>(
            0,
            (total, sale) => total + sale.paymentsCount,
          );
          final visibleInstallments = sales.fold<int>(
            0,
            (total, sale) => total + sale.installmentsCount,
          );

          return DesktopPageScaffold(
            title: 'Pagos',
            subtitle: compact
                ? null
                : 'Vista unificada de pagos reales, cuotas y resumen de cobranza en modo solo lectura.',
            showMobileTitle: false,
            toolbar: DesktopFieldToolbar(
              child: compact
                  ? _MobilePaymentsCompactToolbar(
                      searchController: _searchController,
                      currentFilter: _salesFilter,
                      onOpenFilters: _showMobileFilterSheet,
                      onSubmitSearch: _reloadFromStart,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DesktopToolbar(
                          searchField: DesktopSearchField(
                            controller: _searchController,
                            hintText: 'Buscar por cliente, contrato, solar o estado',
                            onSubmitted: (_) => _reloadFromStart(),
                          ),
                          actions: [
                            _PaymentsFilterBar(
                              currentFilter: _salesFilter,
                              onChanged: _setSalesFilter,
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                _setSalesFilter('all');
                                _reloadFromStart();
                              },
                              icon: const Icon(Icons.cleaning_services_outlined),
                              label: const Text('Limpiar'),
                            ),
                            FilledButton.icon(
                              onPressed: _reloadFromStart,
                              icon: const Icon(Icons.search_rounded),
                              label: const Text('Buscar'),
                            ),
                          ],
                          compactActions: [
                            DesktopToolbarIconAction(
                              icon: Icons.cleaning_services_outlined,
                              tooltip: 'Limpiar',
                              onPressed: () {
                                _searchController.clear();
                                _setSalesFilter('all');
                                _reloadFromStart();
                              },
                            ),
                            DesktopToolbarIconAction(
                              icon: Icons.search_rounded,
                              tooltip: 'Buscar',
                              tone: DesktopToolbarActionTone.filled,
                              onPressed: _reloadFromStart,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact)
                  _MobileFilterIndicator(
                    currentFilter: _salesFilter,
                    salesCount: sales.length,
                    onClear: _salesFilter == 'all'
                        ? null
                        : () {
                            _setSalesFilter('all');
                            _reloadFromStart();
                          },
                  )
                else
                  DesktopInfoStrip(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DesktopTag(
                          label: 'Ventas ${sales.length}',
                          background: const Color(0xFFF1F4FA),
                        ),
                        DesktopTag(
                          label: 'Pagos realizados $visiblePayments',
                          background: const Color(0xFFEAF4ED),
                          foreground: const Color(0xFF2F6F5C),
                        ),
                        DesktopTag(
                          label: currency.format(visibleOutstanding),
                          background: const Color(0xFFF6EFE3),
                          foreground: const Color(0xFF8C5A2C),
                        ),
                        DesktopTag(
                          label: 'Cuotas generadas $visibleInstallments',
                          background: const Color(0xFFF5EEF8),
                          foreground: const Color(0xFF7A4A97),
                        ),
                        if (selectedSummary != null)
                          DesktopTag(
                            label: 'Pagado ${currency.format(selectedSummary.totalPaid)}',
                            background: const Color(0xFFEAF4ED),
                            foreground: const Color(0xFF2F6F5C),
                          ),
                        DesktopTag(
                          label: 'Pag. ${data.page}/${data.totalPages}',
                          background: const Color(0xFFF1F4FA),
                        ),
                        if (activeSelectedSale != null)
                          DesktopTag(
                            label: activeSelectedSale.stageLabel,
                            background: const Color(0xFFF7F1E4),
                            foreground: const Color(0xFF8C5A2C),
                          ),
                        if (lastPaymentDate != null)
                          DesktopTag(
                            label: _formatDate(lastPaymentDate),
                            background: const Color(0xFFF1F4FA),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: sales.isEmpty
                      ? DesktopEmptyState(
                          icon: Icons.payments_outlined,
                          title: _salesFilter == 'all'
                              ? 'No se encontraron ventas para pagos'
                              : 'No hay resultados para este filtro',
                          message: _salesFilter == 'all'
                              ? 'Prueba otra busqueda o espera a la siguiente sincronizacion del backend.'
                              : 'Ajusta el filtro de pendientes o realizados para ver otras ventas.',
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked =
                                constraints.maxWidth < 1100 ||
                                constraints.maxHeight < 720;
                            if (stacked && compact) {
                              return _buildCompactSalesList(
                                data,
                                sales,
                                currency,
                              );
                            }

                            if (stacked) {
                              return ListView(
                                children: [
                                  _buildSalesPanel(
                                    data,
                                    currency,
                                    compact,
                                    scrollable: false,
                                  ),
                                  const SizedBox(height: 12),
                                  if (activeSelectedSale != null) ...[
                                    _buildSummaryPanel(
                                      activeSelectedSale,
                                      currency,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildInstallmentsPanel(
                                      activeSelectedSale,
                                      currency,
                                      compact,
                                      scrollable: false,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildHistoryPanel(
                                      activeSelectedSale,
                                      currency,
                                      averageTicket,
                                      methods.length,
                                      compact,
                                      scrollable: false,
                                    ),
                                  ],
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 32,
                                  child: _buildSalesPanel(
                                    data,
                                    currency,
                                    compact,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 40,
                                  child: activeSelectedSale == null
                                      ? DesktopEmptyState(
                                          icon: Icons.view_list_outlined,
                                          title: detailErrorMessage == null
                                              ? 'Selecciona una venta'
                                              : 'No se pudo cargar el detalle',
                                          message:
                                              detailErrorMessage ??
                                              'Elige una venta de la lista para ver cuotas e historial.',
                                        )
                                      : _buildInstallmentsPanel(
                                          activeSelectedSale,
                                          currency,
                                          compact,
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 28,
                                  child: activeSelectedSale == null
                                      ? const SizedBox.shrink()
                                      : _buildInspectorPanel(
                                          activeSelectedSale,
                                          currency,
                                          averageTicket,
                                          methods.length,
                                          compact,
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        } catch (error, stackTrace) {
          developer.log(
            'Payments screen render failed.',
            name: 'SistemaSolares.PaymentsScreen',
            error: error,
            stackTrace: stackTrace,
          );
          return DesktopPageError(
            message:
                'Render fallo en PaymentsScreen: ${error.runtimeType}: $error',
            onRetry: _reload,
          );
        }
      },
    );
  }

  Widget _buildMobileSummaryPanel(
    PaymentSaleDetail detail,
    NumberFormat currency,
  ) {
    return DesktopCompactSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.summary.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF10263D),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              DesktopTag(
                label: detail.stageLabel,
                background: const Color(0xFFF7F1E4),
                foreground: const Color(0xFF8C5A2C),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryMetricPill(
                label: 'Pendiente',
                value: currency.format(detail.summary.pendingBalance),
              ),
              _SummaryMetricPill(
                label: 'Pagos',
                value: '${detail.history.length}',
                tone: _SummaryTone.success,
              ),
              _SummaryMetricPill(
                label: 'Cuotas',
                value: '${detail.installments.length}',
                tone: _SummaryTone.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDetailPanel(
    PaymentSaleDetail detail,
    NumberFormat currency,
  ) {
    final isPayments = _mobileDetailTab == _MobilePaymentsDetailTab.payments;
    final totalItems = isPayments ? detail.history.length : detail.installments.length;
    final totalPages = totalItems == 0
        ? 1
        : (totalItems / _mobileDetailPageSize).ceil();
    final currentPage = _mobileDetailPage.clamp(1, totalPages);
    final startIndex = (currentPage - 1) * _mobileDetailPageSize;
    final endIndex = (startIndex + _mobileDetailPageSize).clamp(0, totalItems);

    return DesktopCompactSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileDetailSegmentedControl(
            currentTab: _mobileDetailTab,
            paymentsCount: detail.history.length,
            installmentsCount: detail.installments.length,
            onChanged: _setMobileDetailTab,
          ),
          const SizedBox(height: 12),
          if (totalItems == 0)
            DesktopEmptyState(
              icon: isPayments
                  ? Icons.receipt_long_outlined
                  : Icons.view_list_outlined,
              title: isPayments ? 'Sin pagos visibles' : 'Sin cuotas visibles',
              message: isPayments
                  ? 'Esta venta no tiene pagos aplicados dentro del detalle cargado.'
                  : 'Esta venta no tiene cuotas visibles en este momento.',
            )
          else ...[
            for (final index in List<int>.generate(endIndex - startIndex, (i) => startIndex + i)) ...[
              if (isPayments)
                _MobilePaymentRow(
                  payment: detail.history[index],
                  currency: currency,
                  formatDate: _formatDate,
                  paymentBackground: _paymentBackground,
                  paymentForeground: _paymentForeground,
                  paymentIcon: _paymentIcon,
                  paymentMethodLabel: _paymentMethodLabel,
                )
              else
                _MobileInstallmentRow(
                  installment: detail.installments[index],
                  currency: currency,
                  installmentBackground: _installmentBackground,
                  installmentForeground: _installmentForeground,
                ),
              if (index != endIndex - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1),
                ),
            ],
            const SizedBox(height: 12),
            _MobileMiniPagination(
              currentPage: currentPage,
              totalPages: totalPages,
              onPrevious: currentPage > 1
                  ? () => _setMobileDetailPage(currentPage - 1)
                  : null,
              onNext: currentPage < totalPages
                  ? () => _setMobileDetailPage(currentPage + 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  List<PaymentSaleSummary> _filterSales(List<PaymentSaleSummary> sales) {
    return sales
        .where((sale) => _matchesSalesFilter(sale))
        .toList(growable: false);
  }

  bool _matchesSalesFilter(PaymentSaleSummary sale) {
    final status = sale.status.toLowerCase();
    final hasPending =
        sale.pendingInitialPayment > 0.009 || sale.pendingBalance > 0.009;
    return switch (_salesFilter) {
      'pending' => hasPending && status != 'overdue',
      'overdue' => status == 'overdue',
      'paid' => !hasPending || status == 'completed',
      'completed' => sale.paymentsCount > 0,
      _ => true,
    };
  }

  Widget _buildCompactSalesList(
    PaymentsReadOnlyData data,
    List<PaymentSaleSummary> visibleSales,
    NumberFormat currency,
  ) {
    if (visibleSales.isEmpty) {
      return const DesktopEmptyState(
        icon: Icons.payments_outlined,
        title: 'Sin ventas visibles',
        message: 'No hay ventas para la consulta o filtro actual.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4EAF2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: visibleSales.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                thickness: 1,
                indent: 22,
                endIndent: 12,
                color: Color(0xFFEEF1F6),
              ),
              itemBuilder: (context, index) {
                final sale = visibleSales[index];
                return _MobileSaleRow(
                  sale: sale,
                  selected: false,
                  currency: currency,
                  onTap: () => _openMobilePaymentsDetail(sale.id),
                  statusLabel: _statusLabel(sale.status),
                  statusBackground: _statusBackground(sale.status),
                  statusForeground: _statusForeground(sale.status),
                  formatDate: _formatDate,
                );
              },
            ),
          ),
        ),
        if (data.totalPages > 1) ...[
          const SizedBox(height: 8),
          _MobileMiniPagination(
            currentPage: data.page,
            totalPages: data.totalPages,
            onPrevious: data.page > 1 ? () => _goToPage(data.page - 1) : null,
            onNext: data.page < data.totalPages
                ? () => _goToPage(data.page + 1)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildSalesPanel(
    PaymentsReadOnlyData data,
    NumberFormat currency,
    bool compact, {
    bool scrollable = true,
    ValueChanged<String>? onSaleTap,
  }) {
    final visibleSales = _filterSales(data.sales);
    final content = visibleSales.isEmpty
        ? const DesktopEmptyState(
            icon: Icons.payments_outlined,
            title: 'Sin ventas visibles',
            message: 'No hay ventas para la consulta actual.',
          )
        : (scrollable
              ? DesktopModuleList(
                  children: visibleSales
                      .map((sale) {
                        final selected = sale.id == _selectedSaleId;
                        return _buildSaleRow(
                          sale,
                          selected,
                          compact,
                          currency,
                          onTap: onSaleTap,
                        );
                      })
                      .toList(growable: false),
                )
              : _StaticPaymentsList(
                  children: visibleSales
                      .map((sale) {
                        final selected = sale.id == _selectedSaleId;
                        return _buildSaleRow(
                          sale,
                          selected,
                          compact,
                          currency,
                          onTap: onSaleTap,
                        );
                      })
                      .toList(growable: false),
                ));

    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ventas',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2640),
                  ),
                ),
              ),
              DesktopTag(
                label: '${visibleSales.length} visibles',
                background: const Color(0xFFF1F4FA),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (scrollable) Expanded(child: content) else content,
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: data.page > 1
                      ? () => _goToPage(data.page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Anterior'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: data.page < data.totalPages
                      ? () => _goToPage(data.page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Siguiente'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaleRow(
    PaymentSaleSummary sale,
    bool selected,
    bool compact,
    NumberFormat currency, {
    ValueChanged<String>? onTap,
  }) {
    final tapHandler = onTap == null
        ? () => _selectSale(sale.id)
        : () => onTap(sale.id);
    if (compact) {
      return _MobileSaleRow(
        sale: sale,
        selected: selected,
        currency: currency,
        onTap: tapHandler,
        statusLabel: _statusLabel(sale.status),
        statusBackground: _statusBackground(sale.status),
        statusForeground: _statusForeground(sale.status),
        formatDate: _formatDate,
      );
    }

    return Container(
      color: selected ? const Color(0xFFF4F7FD) : Colors.transparent,
      child: DesktopListRow(
        onTap: tapHandler,
        height: compact ? 98 : 90,
        leading: Container(
          width: compact ? 38 : 44,
          height: compact ? 38 : 44,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE1EAFE) : const Color(0xFFF1F4FA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.payments_outlined,
            color: selected ? const Color(0xFF2E5AAC) : const Color(0xFF223048),
          ),
        ),
        title: Text(
          sale.clientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (sale.contractNumber.isNotEmpty) sale.contractNumber,
            sale.lotLabel,
            _statusLabel(sale.status),
            '${sale.paymentsCount} pagos realizados',
            _formatDate(sale.saleDate),
          ].join(compact ? '\n' : '  •  '),
          maxLines: compact ? 4 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6E7791)),
        ),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DesktopTag(
              label: '${sale.paymentsCount} realizados',
              background: const Color(0xFFEAF4ED),
              foreground: const Color(0xFF2F6F5C),
            ),
            DesktopTag(
              label: currency.format(sale.pendingBalance),
              background: const Color(0xFFF6EFE3),
              foreground: const Color(0xFF8C5A2C),
            ),
            DesktopTag(
              label: _statusLabel(sale.status),
              background: _statusBackground(sale.status),
              foreground: _statusForeground(sale.status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallmentsPanel(
    PaymentSaleDetail detail,
    NumberFormat currency,
    bool compact, {
    bool scrollable = true,
  }) {
    final content = detail.installments.isEmpty
        ? const DesktopEmptyState(
            icon: Icons.view_list_outlined,
            title: 'Sin cuotas registradas',
            message: 'Esta venta no tiene cuotas visibles en el backend.',
          )
        : ListView.separated(
            shrinkWrap: !scrollable,
            physics: scrollable
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: detail.installments.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final installment = detail.installments[index];
              return DesktopListRow(
                height: compact ? 92 : 82,
                leading: Container(
                  width: compact ? 38 : 44,
                  height: compact ? 38 : 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4FA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '#${installment.installmentNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF223048),
                      ),
                    ),
                  ),
                ),
                title: Text(
                  'Vence ${installment.dueDateIso}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Monto ${currency.format(installment.amount)}  •  Pagado ${currency.format(installment.paidAmount)}  •  Restante ${currency.format(installment.remainingAmount)}',
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF6E7791)),
                ),
                trailing: DesktopTag(
                  label: installment.statusLabel,
                  background: _installmentBackground(installment.statusLabel),
                  foreground: _installmentForeground(installment.statusLabel),
                ),
              );
            },
          );

    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Cuotas',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2640),
                  ),
                ),
              ),
              DesktopTag(
                label: '${detail.installments.length} cuotas',
                background: const Color(0xFFF1F4FA),
              ),
              if (detail.overdueInstallmentsCount > 0) ...[
                const SizedBox(width: 6),
                DesktopTag(
                  label: '${detail.overdueInstallmentsCount} en atraso',
                  background: const Color(0xFFFBE6E0),
                  foreground: const Color(0xFFA53F2B),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (scrollable) Expanded(child: content) else content,
        ],
      ),
    );
  }

  Widget _buildSummaryPanel(PaymentSaleDetail detail, NumberFormat currency) {
    final sale = detail.summary;
    final priority = detail.priorityInstallment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: 'Resumen',
          trailing: DesktopTag(
            label: 'Solo lectura',
            background: const Color(0xFFEAF4ED),
            foreground: const Color(0xFF2F6F5C),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SummaryMetricPill(
              label: 'Pendiente',
              value: currency.format(sale.pendingBalance),
            ),
            _SummaryMetricPill(
              label: 'Pagos',
              value: '${sale.paymentsCount}',
              tone: _SummaryTone.success,
            ),
            _SummaryMetricPill(
              label: 'Cuotas',
              value: '${sale.installmentsCount}',
              tone: _SummaryTone.accent,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FBFD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5EBF3)),
          ),
          child: Column(
            children: [
              _SummaryFactRow(label: 'Cliente', value: sale.clientName),
              _SummaryFactRow(
                label: 'Documento',
                value: sale.clientDocumentId.isEmpty
                    ? 'No disponible'
                    : sale.clientDocumentId,
              ),
              _SummaryFactRow(
                label: 'Telefono',
                value: sale.clientPhone.isEmpty
                    ? 'No disponible'
                    : sale.clientPhone,
              ),
              _SummaryFactRow(label: 'Solar', value: sale.lotLabel),
              _SummaryFactRow(
                label: 'Contrato',
                value: sale.contractNumber.isEmpty
                    ? 'No disponible'
                    : sale.contractNumber,
              ),
              _SummaryFactRow(
                label: 'Estado',
                value: _statusLabel(sale.status),
              ),
              _SummaryFactRow(
                label: 'Inicial requerida',
                value: currency.format(sale.requiredInitialPayment),
              ),
              _SummaryFactRow(
                label: 'Inicial pagada',
                value: currency.format(sale.paidInitialPayment),
              ),
              _SummaryFactRow(
                label: 'Inicial pendiente',
                value: currency.format(sale.pendingInitialPayment),
              ),
              _SummaryFactRow(
                label: 'Interes mensual',
                value: '${detail.monthlyInterest.toStringAsFixed(2)}%',
              ),
              _SummaryFactRow(
                label: 'Plazo',
                value: '${detail.termMonths} meses',
              ),
              _SummaryFactRow(
                label: 'Cuotas pagadas',
                value: '${detail.paidInstallmentsCount}',
              ),
              _SummaryFactRow(
                label: 'Cuotas pendientes',
                value: '${detail.pendingInstallmentsCount}',
              ),
              if (detail.overdueInstallmentsCount > 0)
                _SummaryFactRow(
                  label: 'Cuotas vencidas',
                  value: '${detail.overdueInstallmentsCount}',
                ),
              _SummaryFactRow(
                label: 'Prioridad',
                value: priority == null
                    ? 'Sin cuota prioritaria'
                    : 'Cuota #${priority.installmentNumber}',
              ),
              _SummaryFactRow(
                label: 'Responsable',
                value: detail.salespersonName,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _InlineInfoBadge(label: 'Proxima accion', value: detail.nextActionText),
      ],
    );
  }

  Widget _buildInspectorPanel(
    PaymentSaleDetail detail,
    NumberFormat currency,
    double averageTicket,
    int methodsCount,
    bool compact,
  ) {
    return _PaymentsPanelSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _inspectorScrollController,
            thumbVisibility: true,
            child: ListView(
              controller: _inspectorScrollController,
              primary: false,
              padding: EdgeInsets.zero,
              children: [
                _buildSummaryPanel(detail, currency),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > 280
                        ? constraints.maxHeight - 280
                        : 0,
                  ),
                  child: _buildHistoryPanel(
                    detail,
                    currency,
                    averageTicket,
                    methodsCount,
                    compact,
                    scrollable: false,
                    embedded: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryPanel(
    PaymentSaleDetail detail,
    NumberFormat currency,
    double averageTicket,
    int methodsCount,
    bool compact, {
    bool scrollable = true,
    bool embedded = false,
  }) {
    final content = detail.history.isEmpty
        ? const DesktopEmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'Sin historial de pagos',
            message: 'Esta venta aun no tiene pagos visibles en el backend.',
          )
        : ListView.separated(
            shrinkWrap: !scrollable,
            physics: scrollable
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: detail.history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final payment = detail.history[index];
              return DesktopListRow(
                height: compact ? 78 : 68,
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4ED),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    _paymentIcon(payment.type),
                    size: 17,
                    color: _paymentForeground(payment.type),
                  ),
                ),
                title: Text(
                  payment.typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  [
                    _formatDate(payment.paymentDate),
                    _paymentMethodLabel(payment.method),
                    if (payment.reference.isNotEmpty) payment.reference,
                  ].join(compact ? '\n' : '  •  '),
                  maxLines: compact ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6E7791),
                    fontSize: 12.2,
                  ),
                ),
                trailing: DesktopTag(
                  label: currency.format(payment.amount),
                  background: _paymentBackground(payment.type),
                  foreground: _paymentForeground(payment.type),
                ),
              );
            },
          );

    final contentPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: 'Historial',
          trailing: detail.history.isNotEmpty
              ? DesktopTag(
                  label: 'Ticket ${currency.format(averageTicket)}',
                  background: const Color(0xFFF6EFE3),
                  foreground: const Color(0xFF8C5A2C),
                )
              : null,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            DesktopTag(
              label: '${detail.history.length} realizados',
              background: const Color(0xFFF1F4FA),
            ),
            DesktopTag(
              label: '$methodsCount metodos',
              background: const Color(0xFFF5EEF8),
              foreground: const Color(0xFF7A4A97),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (scrollable) Expanded(child: content) else content,
      ],
    );

    return embedded ? contentPanel : _PaymentsPanelSurface(child: contentPanel);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _statusLabel(String status) {
    return switch (status) {
      'draft' => 'apartado',
      'active' => 'activa',
      'completed' => 'pagada',
      'cancelled' => 'cancelada',
      'overdue' => 'vencida',
      _ => status,
    };
  }

  Color _statusBackground(String status) {
    return switch (status) {
      'completed' => const Color(0xFFEAF4ED),
      'overdue' => const Color(0xFFFBE6E0),
      'cancelled' => const Color(0xFFF3F4F6),
      'draft' => const Color(0xFFF6EFE3),
      _ => const Color(0xFFF1F4FA),
    };
  }

  Color _statusForeground(String status) {
    return switch (status) {
      'completed' => const Color(0xFF2F6F5C),
      'overdue' => const Color(0xFFA53F2B),
      'cancelled' => const Color(0xFF556079),
      'draft' => const Color(0xFF8C5A2C),
      _ => const Color(0xFF223048),
    };
  }

  Color _installmentBackground(String status) {
    return switch (status) {
      'pagada' => const Color(0xFFEAF4ED),
      'cancelada' => const Color(0xFFF3F4F6),
      'vencida' || 'vencida parcial' => const Color(0xFFFBE6E0),
      'parcial' => const Color(0xFFFBEFDF),
      _ => const Color(0xFFF1F4FA),
    };
  }

  Color _installmentForeground(String status) {
    return switch (status) {
      'pagada' => const Color(0xFF2F6F5C),
      'cancelada' => const Color(0xFF556079),
      'vencida' || 'vencida parcial' => const Color(0xFFA53F2B),
      'parcial' => const Color(0xFFB06618),
      _ => const Color(0xFF2E5AAC),
    };
  }

  Color _paymentBackground(String type) {
    return switch (type) {
      'abono_capital' => const Color(0xFFE8F0FD),
      'apartado' || 'abono_inicial' => const Color(0xFFFBEFDF),
      _ => const Color(0xFFEAF4ED),
    };
  }

  Color _paymentForeground(String type) {
    return switch (type) {
      'abono_capital' => const Color(0xFF2E5AAC),
      'apartado' || 'abono_inicial' => const Color(0xFFB06618),
      _ => const Color(0xFF2F6F5C),
    };
  }

  IconData _paymentIcon(String type) {
    return switch (type) {
      'abono_capital' => Icons.trending_down_outlined,
      'apartado' || 'abono_inicial' => Icons.flag_outlined,
      _ => Icons.receipt_long_outlined,
    };
  }

  String _paymentMethodLabel(String method) {
    return switch (method) {
      'cash' => 'Efectivo',
      'transfer' => 'Transferencia',
      'card' => 'Tarjeta',
      'check' => 'Cheque',
      'mobile_wallet' => 'Billetera movil',
      'mixed' => 'Mixto',
      _ => method.isEmpty ? 'Metodo no definido' : method,
    };
  }
}

class _StaticPaymentsList extends StatelessWidget {
  const _StaticPaymentsList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _PaymentsFilterBar extends StatelessWidget {
  const _PaymentsFilterBar({
    required this.currentFilter,
    required this.onChanged,
    this.compact = false,
  });

  final String currentFilter;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('all', 'Todas'),
      ('pending', 'Pendientes'),
      ('overdue', 'Vencidas'),
      ('paid', 'Pagadas'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips
          .map((entry) {
            final selected = currentFilter == entry.$1;
            return ChoiceChip(
              label: Text(entry.$2),
              selected: selected,
              onSelected: (_) => onChanged(entry.$1),
              labelStyle: TextStyle(
                fontSize: compact ? 11.5 : 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF2F6F5C)
                    : const Color(0xFF556079),
              ),
              selectedColor: const Color(0xFFEAF4ED),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF2F6F5C)
                      : const Color(0xFFD0D7E4),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

enum _MobilePaymentsDetailTab { payments, installments }

class _MobilePaymentsCompactToolbar extends StatelessWidget {
  const _MobilePaymentsCompactToolbar({
    required this.searchController,
    required this.currentFilter,
    required this.onOpenFilters,
    required this.onSubmitSearch,
  });

  final TextEditingController searchController;
  final String currentFilter;
  final VoidCallback onOpenFilters;
  final VoidCallback onSubmitSearch;

  @override
  Widget build(BuildContext context) {
    final filterActive = currentFilter != 'all';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: DesktopSearchField(
              controller: searchController,
              hintText: 'Buscar cliente, contrato o solar',
              onSubmitted: (_) => onSubmitSearch(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _AppBarIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Filtros',
          onPressed: onOpenFilters,
          active: filterActive,
        ),
      ],
    );
  }
}

class _AppBarIconButton extends StatelessWidget {
  const _AppBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? const Color(0xFF14385F) : const Color(0xFF173450);
    final bg = active ? const Color(0xFFE6EEF9) : const Color(0xFFF3F6FA);
    final border = active
        ? const Color(0xFF14385F).withValues(alpha: 0.18)
        : const Color(0xFFD8E2EE);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Icon(icon, size: 19, color: fg),
          ),
        ),
      ),
    );
  }
}

class _MobileFilterIndicator extends StatelessWidget {
  const _MobileFilterIndicator({
    required this.currentFilter,
    required this.salesCount,
    this.onClear,
  });

  final String currentFilter;
  final int salesCount;
  final VoidCallback? onClear;

  String get _filterLabel => switch (currentFilter) {
        'pending' => 'Pendientes',
        'overdue' => 'Vencidas',
        'paid' => 'Pagadas',
        'completed' => 'Realizados',
        _ => 'Todas',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        children: [
          Text(
            '$_filterLabel · $salesCount',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6E7791),
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  'Limpiar filtro',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF14385F),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MobilePaymentsFilterSheet extends StatelessWidget {
  const _MobilePaymentsFilterSheet({required this.currentFilter});

  final String currentFilter;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String, IconData)>[
      ('all', 'Todas', Icons.list_alt_rounded),
      ('pending', 'Pendientes', Icons.hourglass_bottom_rounded),
      ('overdue', 'Vencidas', Icons.error_outline_rounded),
      ('paid', 'Pagadas', Icons.check_circle_outline_rounded),
      ('completed', 'Con pagos realizados', Icons.receipt_long_outlined),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                'Filtrar pagos',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF10263D),
                ),
              ),
            ),
            for (final option in options)
              _FilterSheetOption(
                label: option.$2,
                icon: option.$3,
                selected: currentFilter == option.$1,
                onTap: () => Navigator.of(context).pop(option.$1),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Divider(height: 1),
            ),
            _FilterSheetOption(
              label: 'Limpiar filtros y busqueda',
              icon: Icons.cleaning_services_outlined,
              selected: false,
              destructive: true,
              onTap: () => Navigator.of(context).pop('__clear__'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheetOption extends StatelessWidget {
  const _FilterSheetOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFA53F2B)
        : (selected ? const Color(0xFF14385F) : const Color(0xFF223048));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: Color(0xFF14385F),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileSaleRow extends StatelessWidget {
  const _MobileSaleRow({
    required this.sale,
    required this.selected,
    required this.currency,
    required this.onTap,
    required this.statusLabel,
    required this.statusBackground,
    required this.statusForeground,
    required this.formatDate,
  });

  final PaymentSaleSummary sale;
  final bool selected;
  final NumberFormat currency;
  final VoidCallback onTap;
  final String statusLabel;
  final Color statusBackground;
  final Color statusForeground;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (sale.lotLabel.isNotEmpty) sale.lotLabel,
      if (sale.clientDocumentId.isNotEmpty) sale.clientDocumentId,
    ];
    return Material(
      color: selected ? const Color(0xFFF4F7FD) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 38,
                decoration: BoxDecoration(
                  color: statusForeground,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sale.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.2,
                        color: Color(0xFF10263D),
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8995AB),
                          fontSize: 10.8,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currency.format(sale.pendingBalance),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.4,
                      height: 1.2,
                      color: sale.pendingBalance > 0.009
                          ? const Color(0xFF8C5A2C)
                          : const Color(0xFF2F6F5C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: statusForeground,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFB6BFD0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileDetailSegmentedControl extends StatelessWidget {
  const _MobileDetailSegmentedControl({
    required this.currentTab,
    required this.paymentsCount,
    required this.installmentsCount,
    required this.onChanged,
  });

  final _MobilePaymentsDetailTab currentTab;
  final int paymentsCount;
  final int installmentsCount;
  final ValueChanged<_MobilePaymentsDetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Pagos',
              count: paymentsCount,
              selected: currentTab == _MobilePaymentsDetailTab.payments,
              onTap: () => onChanged(_MobilePaymentsDetailTab.payments),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SegmentButton(
              label: 'Cuotas',
              count: installmentsCount,
              selected: currentTab == _MobilePaymentsDetailTab.installments,
              onTap: () => onChanged(_MobilePaymentsDetailTab.installments),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? const Color(0xFF16324F)
                      : const Color(0xFF68768A),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEAF0F7)
                      : const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF173450),
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

class _MobileInstallmentRow extends StatelessWidget {
  const _MobileInstallmentRow({
    required this.installment,
    required this.currency,
    required this.installmentBackground,
    required this.installmentForeground,
  });

  final PaymentInstallmentView installment;
  final NumberFormat currency;
  final Color Function(String status) installmentBackground;
  final Color Function(String status) installmentForeground;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4FA),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            '#${installment.installmentNumber}',
            style: const TextStyle(
              color: Color(0xFF223048),
              fontSize: 11.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vence ${installment.dueDateIso}',
                      style: const TextStyle(
                        color: Color(0xFF10263D),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DesktopTag(
                    label: installment.statusLabel,
                    background: installmentBackground(installment.statusLabel),
                    foreground: installmentForeground(installment.statusLabel),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Monto ${currency.format(installment.amount)}  •  Pagado ${currency.format(installment.paidAmount)}',
                style: const TextStyle(
                  color: Color(0xFF6E7791),
                  fontSize: 11.6,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Restante ${currency.format(installment.remainingAmount)}',
                style: const TextStyle(
                  color: Color(0xFF8C5A2C),
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobilePaymentRow extends StatelessWidget {
  const _MobilePaymentRow({
    required this.payment,
    required this.currency,
    required this.formatDate,
    required this.paymentBackground,
    required this.paymentForeground,
    required this.paymentIcon,
    required this.paymentMethodLabel,
  });

  final PaymentHistoryView payment;
  final NumberFormat currency;
  final String Function(DateTime? value) formatDate;
  final Color Function(String type) paymentBackground;
  final Color Function(String type) paymentForeground;
  final IconData Function(String type) paymentIcon;
  final String Function(String method) paymentMethodLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: paymentBackground(payment.type),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            paymentIcon(payment.type),
            size: 18,
            color: paymentForeground(payment.type),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      payment.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF10263D),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    currency.format(payment.amount),
                    style: TextStyle(
                      color: paymentForeground(payment.type),
                      fontSize: 12.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  formatDate(payment.paymentDate),
                  paymentMethodLabel(payment.method),
                  if (payment.installmentNumber != null)
                    'Cuota #${payment.installmentNumber}',
                  if (payment.reference.isNotEmpty) payment.reference,
                ].join('  •  '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6E7791),
                  fontSize: 11.6,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileMiniPagination extends StatelessWidget {
  const _MobileMiniPagination({
    required this.currentPage,
    required this.totalPages,
    this.onPrevious,
    this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Anterior'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '$currentPage / $totalPages',
            style: const TextStyle(
              color: Color(0xFF6E7791),
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('Siguiente'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentsPanelSurface extends StatelessWidget {
  const _PaymentsPanelSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopSurface(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      radius: 18,
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D2640),
            ),
          ),
        ),
        ...?trailing == null ? null : [trailing!],
      ],
    );
  }
}

enum _SummaryTone { neutral, success, accent }

class _SummaryMetricPill extends StatelessWidget {
  const _SummaryMetricPill({
    required this.label,
    required this.value,
    this.tone = _SummaryTone.neutral,
  });

  final String label;
  final String value;
  final _SummaryTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = switch (tone) {
      _SummaryTone.success => (
        const Color(0xFFEAF4ED),
        const Color(0xFF2F6F5C),
      ),
      _SummaryTone.accent => (const Color(0xFFF5EEF8), const Color(0xFF7A4A97)),
      _SummaryTone.neutral => (
        const Color(0xFFF1F4FA),
        const Color(0xFF223048),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.$2.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.$2.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: palette.$2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryFactRow extends StatelessWidget {
  const _SummaryFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8EDF4), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 106,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6E7791),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D2640),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfoBadge extends StatelessWidget {
  const _InlineInfoBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6E7791),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF556079),
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePaymentsDetailPage extends StatefulWidget {
  const _MobilePaymentsDetailPage({
    required this.saleId,
    required this.apiClient,
  });

  final String saleId;
  final ApiClient apiClient;

  @override
  State<_MobilePaymentsDetailPage> createState() =>
      _MobilePaymentsDetailPageState();
}

class _MobilePaymentsDetailPageState extends State<_MobilePaymentsDetailPage> {
  static const int _pageSize = 6;
  Future<PaymentSaleDetail>? _future;
  _MobilePaymentsDetailTab _tab = _MobilePaymentsDetailTab.payments;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = PaymentsService(widget.apiClient).fetchSaleDetail(widget.saleId);
  }

  void _reload() {
    setState(() {
      _future = PaymentsService(widget.apiClient).fetchSaleDetail(widget.saleId);
    });
  }

  void _setTab(_MobilePaymentsDetailTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _page = 1;
    });
  }

  void _setPage(int page) {
    if (page < 1 || page == _page) return;
    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final currency = AppNumberFormats.currency;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: const Text(
          'Detalle de pagos',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF10263D),
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF173450)),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<PaymentSaleDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return DesktopPageError(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }
            final detail = snapshot.data!;
            final isPayments = _tab == _MobilePaymentsDetailTab.payments;
            final totalItems = isPayments
                ? detail.history.length
                : detail.installments.length;
            final totalPages = totalItems == 0
                ? 1
                : (totalItems / _pageSize).ceil();
            final currentPage = _page.clamp(1, totalPages);
            final startIndex = (currentPage - 1) * _pageSize;
            final endIndex = (startIndex + _pageSize).clamp(0, totalItems);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MobilePaymentsDetailSummary(
                    detail: detail,
                    currency: currency,
                  ),
                  const SizedBox(height: 12),
                  DesktopCompactSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MobileDetailSegmentedControl(
                          currentTab: _tab,
                          paymentsCount: detail.history.length,
                          installmentsCount: detail.installments.length,
                          onChanged: _setTab,
                        ),
                        const SizedBox(height: 12),
                        if (totalItems == 0)
                          DesktopEmptyState(
                            icon: isPayments
                                ? Icons.receipt_long_outlined
                                : Icons.view_list_outlined,
                            title: isPayments
                                ? 'Sin pagos visibles'
                                : 'Sin cuotas visibles',
                            message: isPayments
                                ? 'Esta venta aun no tiene pagos registrados.'
                                : 'Esta venta no tiene cuotas visibles en este momento.',
                          )
                        else ...[
                          for (
                            final index in List<int>.generate(
                              endIndex - startIndex,
                              (i) => startIndex + i,
                            )
                          ) ...[
                            if (isPayments)
                              _MobilePaymentRow(
                                payment: detail.history[index],
                                currency: currency,
                                formatDate: _formatDateStatic,
                                paymentBackground: _paymentBackgroundStatic,
                                paymentForeground: _paymentForegroundStatic,
                                paymentIcon: _paymentIconStatic,
                                paymentMethodLabel: _paymentMethodLabelStatic,
                              )
                            else
                              _MobileInstallmentRow(
                                installment: detail.installments[index],
                                currency: currency,
                                installmentBackground:
                                    _installmentBackgroundStatic,
                                installmentForeground:
                                    _installmentForegroundStatic,
                              ),
                            if (index != endIndex - 1)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Divider(height: 1),
                              ),
                          ],
                          const SizedBox(height: 12),
                          _MobileMiniPagination(
                            currentPage: currentPage,
                            totalPages: totalPages,
                            onPrevious: currentPage > 1
                                ? () => _setPage(currentPage - 1)
                                : null,
                            onNext: currentPage < totalPages
                                ? () => _setPage(currentPage + 1)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MobilePaymentsDetailSummary extends StatelessWidget {
  const _MobilePaymentsDetailSummary({
    required this.detail,
    required this.currency,
  });

  final PaymentSaleDetail detail;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    return DesktopCompactSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF10263D),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              DesktopTag(
                label: detail.stageLabel,
                background: const Color(0xFFF7F1E4),
                foreground: const Color(0xFF8C5A2C),
              ),
            ],
          ),
          if (summary.contractNumber.isNotEmpty ||
              summary.lotLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (summary.contractNumber.isNotEmpty) summary.contractNumber,
                if (summary.lotLabel.isNotEmpty) summary.lotLabel,
              ].join('  •  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6E7791),
                fontSize: 11.6,
                height: 1.2,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryMetricPill(
                label: 'Pendiente',
                value: currency.format(summary.pendingBalance),
              ),
              _SummaryMetricPill(
                label: 'Pagado',
                value: currency.format(summary.totalPaid),
                tone: _SummaryTone.success,
              ),
              _SummaryMetricPill(
                label: 'Pagos',
                value: '${detail.history.length}',
                tone: _SummaryTone.success,
              ),
              _SummaryMetricPill(
                label: 'Cuotas',
                value: '${detail.installments.length}',
                tone: _SummaryTone.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDateStatic(DateTime? value) {
  if (value == null) return '-';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

Color _installmentBackgroundStatic(String status) {
  return switch (status) {
    'pagada' => const Color(0xFFEAF4ED),
    'cancelada' => const Color(0xFFF3F4F6),
    'vencida' || 'vencida parcial' => const Color(0xFFFBE6E0),
    'parcial' => const Color(0xFFFBEFDF),
    _ => const Color(0xFFF1F4FA),
  };
}

Color _installmentForegroundStatic(String status) {
  return switch (status) {
    'pagada' => const Color(0xFF2F6F5C),
    'cancelada' => const Color(0xFF556079),
    'vencida' || 'vencida parcial' => const Color(0xFFA53F2B),
    'parcial' => const Color(0xFFB06618),
    _ => const Color(0xFF223048),
  };
}

Color _paymentBackgroundStatic(String type) {
  return switch (type) {
    'abono_capital' => const Color(0xFFE8F0FD),
    'apartado' || 'abono_inicial' => const Color(0xFFFBEFDF),
    _ => const Color(0xFFEAF4ED),
  };
}

Color _paymentForegroundStatic(String type) {
  return switch (type) {
    'abono_capital' => const Color(0xFF2E5AAC),
    'apartado' || 'abono_inicial' => const Color(0xFFB06618),
    _ => const Color(0xFF2F6F5C),
  };
}

IconData _paymentIconStatic(String type) {
  return switch (type) {
    'abono_capital' => Icons.trending_down_outlined,
    'apartado' || 'abono_inicial' => Icons.flag_outlined,
    _ => Icons.receipt_long_outlined,
  };
}

String _paymentMethodLabelStatic(String method) {
  return switch (method) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'card' => 'Tarjeta',
    'check' => 'Cheque',
    'mobile_wallet' => 'Billetera movil',
    'mixed' => 'Mixto',
    _ => method.isEmpty ? 'Metodo no definido' : method,
  };
}



