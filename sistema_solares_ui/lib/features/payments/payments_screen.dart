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
          final sales = data.sales;
          final selectedSale = data.selectedSale;
          final detailErrorMessage = data.detailErrorMessage;
          _selectedSaleId ??= selectedSale?.summary.id;
          final compact = MediaQuery.sizeOf(context).width < 760;
          final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
          final totalCollected =
              selectedSale?.history.fold<double>(
                0,
                (total, payment) => total + payment.amount,
              ) ??
              0;
          final averageTicket =
              selectedSale == null || selectedSale.history.isEmpty
              ? 0.0
              : totalCollected / selectedSale.history.length;
          final methods =
              selectedSale?.history
                  .map((payment) => payment.method.trim())
                  .where((method) => method.isNotEmpty)
                  .toSet() ??
              <String>{};
          final lastPaymentDate = selectedSale?.history
              .map((payment) => payment.paymentDate)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (latest, current) => latest == null || current.isAfter(latest)
                    ? current
                    : latest,
              );
          final selectedSummary = selectedSale?.summary;
          final visibleOutstanding = sales.fold<double>(
            0,
            (total, sale) => total + sale.pendingBalance,
          );

          return DesktopPageScaffold(
          title: 'Pagos',
          subtitle: compact
              ? 'Consulta de pagos y cuotas en modo solo lectura.'
              : 'Modulo de supervision de pagos, cuotas e historial usando datos reales del backend.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar por cliente, contrato, solar o estado',
                onSubmitted: (_) => _reloadFromStart(),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
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
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
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
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    DesktopTag(
                      label: compact
                          ? '${data.total} ventas'
                          : 'Ventas ${data.total}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: currency.format(visibleOutstanding),
                      background: const Color(0xFFEAF4ED),
                      foreground: const Color(0xFF2F6F5C),
                    ),
                    if (selectedSummary != null && !compact)
                      DesktopTag(
                        label:
                            'Pagado ${currency.format(selectedSummary.totalPaid)}',
                        background: const Color(0xFFF6EFE3),
                        foreground: const Color(0xFF8C5A2C),
                      ),
                    if (selectedSale != null && !compact)
                      DesktopTag(
                        label: 'Historial ${selectedSale.history.length}',
                        background: const Color(0xFFF5EEF8),
                        foreground: const Color(0xFF7A4A97),
                      ),
                    if (!compact)
                      DesktopTag(
                        label: 'Pag. ${data.page}/${data.totalPages}',
                        background: const Color(0xFFF1F4FA),
                      ),
                    if (selectedSale != null)
                      DesktopTag(
                        label: selectedSale.stageLabel,
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
              const SizedBox(height: 16),
              Expanded(
                child: sales.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.payments_outlined,
                        title: 'No se encontraron ventas para pagos',
                        message:
                            'Prueba otra busqueda o espera a la siguiente sincronizacion del backend.',
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
                                if (selectedSale != null) ...[
                                  _buildSummaryPanel(selectedSale, currency),
                                  const SizedBox(height: 12),
                                  _buildInstallmentsPanel(
                                    selectedSale,
                                    currency,
                                    compact,
                                    scrollable: false,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildHistoryPanel(
                                    selectedSale,
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
                                flex: 34,
                                child: _buildSalesPanel(
                                  data,
                                  currency,
                                  compact,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 36,
                                child: selectedSale == null
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
                                        selectedSale,
                                        currency,
                                        compact,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 30,
                                child: selectedSale == null
                                    ? const SizedBox.shrink()
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildSummaryPanel(
                                            selectedSale,
                                            currency,
                                          ),
                                          const SizedBox(height: 12),
                                          Expanded(
                                            child: _buildHistoryPanel(
                                              selectedSale,
                                              currency,
                                              averageTicket,
                                              methods.length,
                                              compact,
                                            ),
                                          ),
                                        ],
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

  Widget _buildSalesPanel(
    PaymentsReadOnlyData data,
    NumberFormat currency,
    bool compact, {
    bool scrollable = true,
  }) {
    final content = data.sales.isEmpty
        ? const DesktopEmptyState(
            icon: Icons.payments_outlined,
            title: 'Sin ventas visibles',
            message: 'No hay ventas para la consulta actual.',
          )
        : (scrollable
              ? DesktopModuleList(
                  children: data.sales
                      .map((sale) {
                        final selected = sale.id == _selectedSaleId;
                        return _buildSaleRow(sale, selected, compact, currency);
                      })
                      .toList(growable: false),
                )
              : _StaticPaymentsList(
                  children: data.sales
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
                label: '${data.total} visibles',
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
    return DesktopSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Resumen',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2640),
                  ),
                ),
              ),
              DesktopTag(
                label: 'Solo lectura',
                background: const Color(0xFFEAF4ED),
                foreground: const Color(0xFF2F6F5C),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryItem(label: 'Cliente', value: sale.clientName),
              _SummaryItem(
                label: 'Documento',
                value: sale.clientDocumentId.isEmpty
                    ? 'No disponible'
                    : sale.clientDocumentId,
              ),
              _SummaryItem(
                label: 'Telefono',
                value: sale.clientPhone.isEmpty
                    ? 'No disponible'
                    : sale.clientPhone,
              ),
              _SummaryItem(label: 'Solar', value: sale.lotLabel),
              _SummaryItem(
                label: 'Contrato',
                value: sale.contractNumber.isEmpty
                    ? 'No disponible'
                    : sale.contractNumber,
              ),
              _SummaryItem(label: 'Estado', value: _statusLabel(sale.status)),
              _SummaryItem(
                label: 'Saldo pendiente',
                value: currency.format(sale.pendingBalance),
              ),
              _SummaryItem(
                label: 'Inicial requerida',
                value: currency.format(sale.requiredInitialPayment),
              ),
              _SummaryItem(
                label: 'Inicial pagada',
                value: currency.format(sale.paidInitialPayment),
              ),
              _SummaryItem(
                label: 'Inicial pendiente',
                value: currency.format(sale.pendingInitialPayment),
              ),
              _SummaryItem(
                label: 'Interes mensual',
                value: '${detail.monthlyInterest.toStringAsFixed(2)}%',
              ),
              _SummaryItem(label: 'Plazo', value: '${detail.termMonths} meses'),
              _SummaryItem(
                label: 'Cuotas pagadas',
                value: '${detail.paidInstallmentsCount}',
              ),
              _SummaryItem(
                label: 'Cuotas pendientes',
                value: '${detail.pendingInstallmentsCount}',
              ),
              _SummaryItem(
                label: 'Prioridad',
                value: priority == null
                    ? 'Sin cuota prioritaria'
                    : 'Cuota #${priority.installmentNumber}',
              ),
              _SummaryItem(label: 'Responsable', value: detail.salespersonName),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4EAF2)),
            ),
            child: Text(
              detail.nextActionText,
              style: const TextStyle(color: Color(0xFF556079), height: 1.4),
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
                height: compact ? 104 : 84,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4ED),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _paymentIcon(payment.type),
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
                  style: const TextStyle(color: Color(0xFF6E7791)),
                ),
                trailing: DesktopTag(
                  label: currency.format(payment.amount),
                  background: _paymentBackground(payment.type),
                  foreground: _paymentForeground(payment.type),
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
                  'Historial',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2640),
                  ),
                ),
              ),
              if (detail.history.isNotEmpty)
                DesktopTag(
                  label: 'Ticket ${currency.format(averageTicket)}',
                  background: const Color(0xFFF6EFE3),
                  foreground: const Color(0xFF8C5A2C),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopTag(
                label: '${detail.history.length} pagos',
                background: const Color(0xFFF1F4FA),
              ),
              DesktopTag(
                label: '$methodsCount metodos',
                background: const Color(0xFFF5EEF8),
                foreground: const Color(0xFF7A4A97),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (scrollable) Expanded(child: content) else content,
        ],
      ),
    );
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

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
      width: compact ? double.infinity : 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6E7791),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D2640),
            ),
          ),
        ],
      ),
    );
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
