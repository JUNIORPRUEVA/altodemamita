import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
  Future<PaymentsReadOnlyData>? _future;
  int _lastTick = -1;
  int _page = 1;
  String? _selectedSaleId;
  String _salesFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
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
          final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
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
              ? 'Consulta alineada de cuotas y pagos reales.'
              : 'Vista unificada de pagos reales, cuotas y resumen de cobranza en modo solo lectura.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
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
                _PaymentsFilterBar(
                  currentFilter: _salesFilter,
                  onChanged: _setSalesFilter,
                  compact: true,
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
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopInfoStrip(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DesktopTag(
                      label: compact
                          ? '${sales.length} ventas'
                          : 'Ventas ${sales.length}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: compact
                          ? '$visiblePayments realizados'
                          : 'Pagos realizados $visiblePayments',
                      background: const Color(0xFFEAF4ED),
                      foreground: const Color(0xFF2F6F5C),
                    ),
                    DesktopTag(
                      label: currency.format(visibleOutstanding),
                      background: const Color(0xFFF6EFE3),
                      foreground: const Color(0xFF8C5A2C),
                    ),
                    if (!compact)
                      DesktopTag(
                        label: 'Cuotas generadas $visibleInstallments',
                        background: const Color(0xFFF5EEF8),
                        foreground: const Color(0xFF7A4A97),
                      ),
                    if (selectedSummary != null && !compact)
                      DesktopTag(
                        label:
                            'Pagado ${currency.format(selectedSummary.totalPaid)}',
                        background: const Color(0xFFEAF4ED),
                        foreground: const Color(0xFF2F6F5C),
                      ),
                    if (!compact)
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
                          final stacked = constraints.maxWidth < 1100;
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
                                  _buildSummaryPanel(activeSelectedSale, currency),
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

  List<PaymentSaleSummary> _filterSales(List<PaymentSaleSummary> sales) {
    return sales.where((sale) => _matchesSalesFilter(sale)).toList(growable: false);
  }

  bool _matchesSalesFilter(PaymentSaleSummary sale) {
    return switch (_salesFilter) {
      'pending' => sale.pendingInitialPayment > 0.009 || sale.pendingBalance > 0.009,
      'completed' => sale.paymentsCount > 0,
      _ => true,
    };
  }

  Widget _buildSalesPanel(
    PaymentsReadOnlyData data,
    NumberFormat currency,
    bool compact, {
    bool scrollable = true,
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
                        return _buildSaleRow(sale, selected, compact, currency);
                      })
                      .toList(growable: false),
                )
              : _StaticPaymentsList(
                  children: visibleSales
                      .map((sale) {
                        final selected = sale.id == _selectedSaleId;
                        return _buildSaleRow(sale, selected, compact, currency);
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
    NumberFormat currency,
  ) {
    return Container(
      color: selected ? const Color(0xFFF4F7FD) : Colors.transparent,
      child: DesktopListRow(
        onTap: () => _selectSale(sale.id),
        height: compact ? 112 : 90,
        leading: Container(
          width: 44,
          height: 44,
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
                height: compact ? 102 : 82,
                leading: Container(
                  width: 44,
                  height: 44,
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
              _SummaryFactRow(label: 'Estado', value: _statusLabel(sale.status)),
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
              _SummaryFactRow(label: 'Plazo', value: '${detail.termMonths} meses'),
              _SummaryFactRow(
                label: 'Cuotas pagadas',
                value: '${detail.paidInstallmentsCount}',
              ),
              _SummaryFactRow(
                label: 'Cuotas pendientes',
                value: '${detail.pendingInstallmentsCount}',
              ),
              _SummaryFactRow(
                label: 'Prioridad',
                value: priority == null
                    ? 'Sin cuota prioritaria'
                    : 'Cuota #${priority.installmentNumber}',
              ),
              _SummaryFactRow(label: 'Responsable', value: detail.salespersonName),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryPanel(detail, currency),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: _buildHistoryPanel(
              detail,
              currency,
              averageTicket,
              methodsCount,
              compact,
              embedded: true,
            ),
          ),
        ],
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
                height: compact ? 86 : 68,
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
                  style: const TextStyle(color: Color(0xFF6E7791), fontSize: 12.2),
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
      ('completed', 'Realizados'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((entry) {
        final selected = currentFilter == entry.$1;
        return ChoiceChip(
          label: Text(entry.$2),
          selected: selected,
          onSelected: (_) => onChanged(entry.$1),
          labelStyle: TextStyle(
            fontSize: compact ? 11.5 : 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF2F6F5C) : const Color(0xFF556079),
          ),
          selectedColor: const Color(0xFFEAF4ED),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: selected ? const Color(0xFF2F6F5C) : const Color(0xFFD0D7E4),
            ),
          ),
        );
      }).toList(growable: false),
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
      _SummaryTone.success => (const Color(0xFFEAF4ED), const Color(0xFF2F6F5C)),
      _SummaryTone.accent => (const Color(0xFFF5EEF8), const Color(0xFF7A4A97)),
      _SummaryTone.neutral => (const Color(0xFFF1F4FA), const Color(0xFF223048)),
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
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8EDF4), width: 1),
        ),
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
