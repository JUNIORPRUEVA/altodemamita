import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/module_list_states.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../../installments/domain/installment.dart';
import '../data/payments_repository.dart';
import '../data/receipt_repository.dart';
import '../domain/client_pagare_report.dart';
import '../domain/payment_draft.dart';
import '../domain/payment_history_item.dart';
import '../domain/payment_sale_context.dart';
import '../domain/payment_sale_option.dart';
import '../domain/payment_work_queue.dart';
import 'payment_annul_dialog.dart';
import 'payment_form_dialog.dart';
import 'payment_history_fullscreen.dart';
import 'payments_controller.dart';
import 'receipt/receipt_dialog.dart';
import 'reports/client_pagare_dialog.dart';

class PaymentsPage extends StatefulWidget {
  PaymentsPage({
    super.key,
    required this.paymentsRepository,
    ReceiptRepository? receiptRepository,
    this.initialSaleId,
  }) : _receiptRepository = receiptRepository ?? ReceiptRepository();

  final PaymentsRepository paymentsRepository;
  final ReceiptRepository _receiptRepository;
  final int? initialSaleId;

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late final PaymentsController _controller;
  late final TextEditingController _saleSearchController;
  late final ScrollController _historyScrollController;

  final Map<int, PaymentSaleContext> _saleContextCache = {};
  Timer? _searchDebounce;
  String _searchQuery = '';
  int? _selectedSaleId;
  int? _selectedHistoryPaymentId;
  String _installmentFilter = 'all';
  String _sortOrder = 'recent';
  DateTimeRange? _dateRange;
  bool _isHydratingSaleContexts = false;

  @override
  void initState() {
    super.initState();
    _controller = PaymentsController(
      paymentsRepository: widget.paymentsRepository,
    );
    _saleSearchController = TextEditingController();
    _historyScrollController = ScrollController();
    _controller.addListener(_syncSelectedSaleState);
    _controller.load(preferredSaleId: widget.initialSaleId);
  }

  @override
  void didUpdateWidget(covariant PaymentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSaleId == widget.initialSaleId) {
      return;
    }

    _controller.load(preferredSaleId: widget.initialSaleId);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.removeListener(_syncSelectedSaleState);
    _saleSearchController.dispose();
    _historyScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<PaymentSaleOption> get _searchMatches {
    final query = _searchQuery.trim();
    if (query.isEmpty) {
      return const [];
    }

    return _matchSales(query);
  }

  int get _activeFilterCount {
    var count = 0;
    if (_installmentFilter != 'all') {
      count++;
    }
    if (_sortOrder != 'recent') {
      count++;
    }
    if (_dateRange != null) {
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreatePayments = auth.canAccess(
      PermissionCatalog.payments,
      PermissionAction.create,
    );
    final isAdmin = auth.isAdmin;

    return BaseLayout(
      title: 'Pagos',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, canCreatePayments: canCreatePayments),
            Expanded(child: _buildBody(context, isAdmin: isAdmin)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool canCreatePayments}) {
    final searchMatches = _searchMatches;
    final showSearchMatches = _searchQuery.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildSaleSearchField()),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _openFiltersDialog,
                icon: const Icon(Icons.filter_alt_outlined, size: 18),
                label: Text(
                  _activeFilterCount == 0
                      ? 'Filtros'
                      : 'Filtros ($_activeFilterCount)',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (_) {
                  final selected = _controller.selectedContext?.sale;
                  final isInitialPending =
                      selected != null &&
                      !selected.isFinancingActive &&
                      selected.pendingInitialPayment > 0.009;
                  final buttonLabel = _controller.isSaving
                      ? 'Guardando...'
                      : isInitialPending
                      ? (selected.paidInitialPayment <= 0.009
                            ? 'Pagar apartado'
                            : 'Pagar completivo del inicial')
                      : 'Registrar pago';
                  final buttonIcon = isInitialPending
                      ? Icons.flag_outlined
                      : Icons.point_of_sale_outlined;
                  return FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed:
                        !canCreatePayments ||
                            _controller.selectedContext == null ||
                            _controller.isSaving
                        ? null
                        : _registerPayment,
                    icon: Icon(buttonIcon, size: 18),
                    label: Text(
                      buttonLabel,
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                },
              ),
            ],
          ),
          if (showSearchMatches) ...[
            const SizedBox(height: 10),
            _buildSearchMatchesPanel(searchMatches),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchMatchesPanel(List<PaymentSaleOption> matches) {
    if (matches.isEmpty && _controller.isSearching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD7E0EC)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Buscando en el servidor…',
                style: TextStyle(fontSize: 13, color: Color(0xFF556079)),
              ),
            ),
          ],
        ),
      );
    }

    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD7E0EC)),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_off_outlined, size: 18, color: Color(0xFF6B7494)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No se encontraron coincidencias con ese nombre, telefono, cedula o solar.',
                style: TextStyle(fontSize: 13, color: Color(0xFF556079)),
              ),
            ),
          ],
        ),
      );
    }

    final visibleMatches = matches.take(6).toList(growable: false);
    final remainingMatches = matches.length - visibleMatches.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E0EC)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < visibleMatches.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _commitSaleSelection(visibleMatches[index].saleId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EEF9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_search_outlined,
                          size: 18,
                          color: Color(0xFF3B5BDB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              visibleMatches[index].clientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A2235),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _searchMatchDetails(visibleMatches[index]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7494),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF6B7494),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (remainingMatches > 0) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_outlined,
                    size: 16,
                    color: Color(0xFF6B7494),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hay $remainingMatches coincidencias mas. Sigue escribiendo para acotar la lista.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7494),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _searchMatchDetails(PaymentSaleOption sale) {
    final details = <String>[];
    if (sale.lotDisplayCode.trim().isNotEmpty) {
      details.add('Solar ${sale.lotDisplayCode}');
    }
    if (sale.clientPhone.trim().isNotEmpty) {
      details.add(sale.clientPhone);
    }
    if (sale.clientDocumentId.trim().isNotEmpty) {
      details.add(sale.clientDocumentId);
    }
    details.add('Venta #${sale.saleId}');
    return details.join(' - ');
  }

  Widget _buildSaleSearchField() {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: _saleSearchController,
        onChanged: _handleSearchChanged,
        onSubmitted: _handleSearchSubmitted,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, telefono, cedula o numero de solar',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _saleSearchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _saleSearchController.clear();
                    _handleSearchChanged('');
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: const Color(0xFFFDFEFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD0D7E4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD0D7E4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF3B5BDB)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool isAdmin}) {
    final matchedSales = _controller.activeSales;

    if (_controller.isLoading &&
        _controller.activeSales.isEmpty &&
        _controller.workQueue == null) {
      return _buildLoadingState('Consultando cuotas y pagos...');
    }

    // Pantalla fatal real: solo cuando NO hay ningun dato visible.
    if (_controller.loadError != null &&
        _controller.activeSales.isEmpty &&
        _controller.workQueue == null) {
      final failure = _controller.loadError!;
      return InlineModuleRecoveryCard(
        title: failure.title,
        message: failure.message,
        details: failure.details,
        suggestions: failure.suggestions,
        onRetry: () => _controller.load(preferredSaleId: widget.initialSaleId),
      );
    }

    if (_controller.activeSales.isEmpty) {
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
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    size: 34,
                    color: Color(0xFF3B5BDB),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'No hay ventas con inicial o saldo pendiente.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cuando exista una venta activa con pendiente, aparecera aqui para cobrarla.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7494)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final workQueue = _controller.workQueue;
    // Cache-first real: si ya hay cola/sales visibles, pintamos de inmediato
    // con un contexto parcial y cargamos el detalle en segundo plano. Solo se
    // muestra el spinner global cuando NO existe ningun dato usable.
    final contextLoading = _controller.selectedContext == null;
    final contextData =
        _controller.selectedContext ??
        _partialContextFromData(matchedSales, workQueue);
    if (contextData == null) {
      return _buildLoadingState('Cargando cuotas y pagos...');
    }

    if (workQueue == null) {
      _ensureSaleContextsHydrated();
    }

    final visibleInstallments = workQueue == null
        ? _filteredInstallmentEntries(matchedSales)
        : _filteredWorkQueueEntries(workQueue.entries);
    final totalInstallments =
        workQueue?.total ?? _totalInstallmentsForSales(matchedSales);
    final hasPendingContexts =
        workQueue == null && _hasPendingSaleContexts(matchedSales);
    final visibleHistory = contextLoading
        ? const <PaymentHistoryItem>[]
        : _filteredHistory(contextData.history);
    final selectedHistoryPaymentId = _resolveSelectedHistoryPaymentId(
      visibleHistory,
    );

    return Column(
      children: [
        ModuleStatusBanner(
          isRefreshing: _controller.isRefreshing,
          refreshFailed: _controller.refreshFailed,
          onRetry: () =>
              _controller.load(preferredSaleId: widget.initialSaleId),
          moduleLabel: 'Pagos',
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFF5F7FA),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;

            if (!wide) {
              return ListView(
                children: [
                  _buildInstallmentsPanel(
                    contextData,
                    visibleInstallments,
                    matchedSalesCount: matchedSales.length,
                    totalInstallments: totalInstallments,
                    hasPendingContexts: hasPendingContexts,
                    fillAvailableHeight: false,
                  ),
                  const SizedBox(height: 12),
                  _buildDetailsPanel(
                    contextData,
                    visibleHistory,
                    isAdmin: isAdmin,
                    selectedHistoryPaymentId: selectedHistoryPaymentId,
                    scrollable: false,
                    isContextLoading: contextLoading,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 65,
                  child: _buildInstallmentsPanel(
                    contextData,
                    visibleInstallments,
                    matchedSalesCount: matchedSales.length,
                    totalInstallments: totalInstallments,
                    hasPendingContexts: hasPendingContexts,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 35,
                  child: _buildDetailsPanel(
                    contextData,
                    visibleHistory,
                    isAdmin: isAdmin,
                    selectedHistoryPaymentId: selectedHistoryPaymentId,
                    isContextLoading: contextLoading,
                  ),
                ),
              ],
            );
          },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF556079),
            ),
          ),
        ],
      ),
    );
  }

  /// Panel de detalle discreto mientras llega el contexto real de la venta
  /// (no bloquea el resto del modulo).
  Widget _buildDetailsLoadingCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text(
              'Cargando detalle de la venta…',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7494)),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye un contexto parcial (solo para encabezado/cuotas) a partir de la
  /// cola o las ventas activas, para pintar el modulo de inmediato mientras el
  /// contexto autoritativo llega en segundo plano.
  PaymentSaleContext? _partialContextFromData(
    List<PaymentSaleOption> sales,
    PaymentWorkQueue? queue,
  ) {
    PaymentSaleOption? sale;
    final selectedId = _controller.selectedSaleId;
    if (selectedId != null) {
      for (final candidate in sales) {
        if (candidate.saleId == selectedId) {
          sale = candidate;
          break;
        }
      }
      if (sale == null && queue != null) {
        for (final entry in queue.entries) {
          if (entry.sale.saleId == selectedId) {
            sale = entry.sale;
            break;
          }
        }
      }
    }
    sale ??= sales.isNotEmpty
        ? sales.first
        : (queue != null && queue.entries.isNotEmpty
              ? queue.entries.first.sale
              : null);
    if (sale == null) {
      return null;
    }
    final resolvedSale = sale;
    final installments = queue == null
        ? const <Installment>[]
        : queue.entries
              .where((entry) => entry.sale.saleId == resolvedSale.saleId)
              .map((entry) => entry.installment)
              .toList(growable: false);
    return PaymentSaleContext(
      sale: resolvedSale,
      monthlyInterest: 0,
      installments: installments,
      history: const [],
    );
  }

  Widget _buildInstallmentsPanel(
    PaymentSaleContext contextData,
    List<_PaymentInstallmentEntry> visibleInstallments, {
    required int matchedSalesCount,
    required int totalInstallments,
    required bool hasPendingContexts,
    bool fillAvailableHeight = true,
  }) {
    final showAggregate = matchedSalesCount > 1;
    final panelTitle = showAggregate
        ? 'Lista de cuotas'
        : contextData.sale.isFinancingActive
        ? 'Lista de cuotas'
        : 'Activacion del financiamiento';
    final panelSubtitle = showAggregate
        ? 'Mostrando cuotas de todas las ventas activas'
        : '${contextData.sale.clientName} - ${contextData.sale.lotDisplayCode}';

    final installmentList = hasPendingContexts && totalInstallments == 0
        ? const Center(child: CircularProgressIndicator())
        : totalInstallments == 0
        ? _buildEmptyInstallmentsState(hasFilters: false)
        : visibleInstallments.isEmpty
        ? _buildEmptyInstallmentsState(hasFilters: true)
        : ListView.separated(
            itemCount: visibleInstallments.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = visibleInstallments[index];
              final installment = item.installment;
              final statusLabel = _statusLabel(installment);
              return _CompactInstallmentRow(
                installment: installment,
                formattedDate: _formatDate(installment.dueDate),
                formattedAmount: _money(installment.totalAmount),
                formattedPaid: _money(installment.paidAmount),
                formattedRemaining: _money(installment.remainingAmount),
                statusLabel: statusLabel,
                statusColor: _installmentColor(statusLabel),
                selected: item.saleId == _effectiveSelectedSaleId,
                onTap: () => _commitSaleSelection(item.saleId),
              );
            },
          );

    final listRegion = fillAvailableHeight
        ? Expanded(child: installmentList)
        : SizedBox(height: 420, child: installmentList);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        panelTitle,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2235),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        panelSubtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8893AA),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    hasPendingContexts && totalInstallments == 0
                        ? 'Cargando...'
                        : 'Mostrando ${visibleInstallments.length} de $totalInstallments',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7494),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildInstallmentsTableHeader(),
          const Divider(height: 1),
          listRegion,
        ],
      ),
    );
  }

  Widget _buildInstallmentsTableHeader() {
    const labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF8893AA),
      letterSpacing: 0.4,
    );

    return SizedBox(
      height: 42,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: const [
            SizedBox(width: 88, child: Text('CUOTA', style: labelStyle)),
            SizedBox(width: 102, child: Text('FECHA', style: labelStyle)),
            Expanded(child: Text('MONTO', style: labelStyle)),
            Expanded(child: Text('PAGADO', style: labelStyle)),
            Expanded(child: Text('RESTANTE', style: labelStyle)),
            SizedBox(
              width: 108,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('ESTADO', style: labelStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyInstallmentsState({required bool hasFilters}) {
    final sale = _controller.selectedContext?.sale;
    final isPendingInitial =
        !hasFilters &&
        sale != null &&
        !sale.isFinancingActive &&
        sale.pendingInitialPayment > 0.009;
    final canCreatePayments = context.read<AuthProvider>().canAccess(
      PermissionCatalog.payments,
      PermissionAction.create,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isPendingInitial
                    ? const Color(0xFFFFF3E0)
                    : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                isPendingInitial
                    ? Icons.flag_outlined
                    : Icons.view_list_outlined,
                size: 30,
                color: isPendingInitial
                    ? const Color(0xFFE67E00)
                    : const Color(0xFF3B5BDB),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No hay cuotas que coincidan con los filtros actuales.'
                  : isPendingInitial
                  ? 'Inicial pendiente de completar'
                  : 'Esta venta todavia no tiene cuotas activas.',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2235),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Prueba ajustando el estado, la fecha o el orden para ver mas resultados.'
                  : isPendingInitial
                  ? 'Registra el pago del inicial para activar el financiamiento y generar las cuotas.'
                  : 'El financiamiento inicia cuando el inicial queda completo.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8893AA)),
              textAlign: TextAlign.center,
            ),
            if (isPendingInitial) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Inicial pagado: ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8893AA),
                          ),
                        ),
                        Text(
                          _money(sale.paidInitialPayment),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A2235),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Monto pendiente: ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8893AA),
                          ),
                        ),
                        Text(
                          _money(sale.pendingInitialPayment),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE67E00),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE67E00),
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: canCreatePayments && !_controller.isSaving
                    ? () => _registerPayment()
                    : null,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(
                  sale.paidInitialPayment <= 0.009
                      ? 'Registrar pago de apartado'
                      : 'Completar pago del inicial',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(
    PaymentSaleContext contextData,
    List<PaymentHistoryItem> visibleHistory, {
    required bool isAdmin,
    required int? selectedHistoryPaymentId,
    bool scrollable = true,
    bool isContextLoading = false,
  }) {
    if (isContextLoading) {
      return _buildDetailsLoadingCard();
    }
    final sale = contextData.sale;
    final authProvider = context.watch<AuthProvider>();
    final canCancelPayments =
        authProvider.currentUser?.canCancelPayments ?? authProvider.isAdmin;
    final actionableInstallment = contextData.actionableInstallment;
    final isFinancingActive = sale.isFinancingActive;
    final paidCount = contextData.installments
        .where((item) => item.status == 'pagada' || item.status == 'ajustada')
        .length;
    final pendingCount = contextData.installments.length - paidCount;
    final nextActionText = !isFinancingActive
        ? sale.pendingInitialPayment <= 0.009
              ? 'El inicial ya esta completo. La venta quedara lista para operar con cuotas.'
              : 'El proximo pago se aplicara al inicial. Cuando el pendiente llegue a cero, la venta se activara y se generaran las cuotas.'
        : actionableInstallment == null
        ? 'No hay cuota vencida o exigible. Si registras un pago ahora, ira directo a capital.'
        : 'El proximo pago cubrira primero la cuota #${actionableInstallment.installmentNumber} con restante de ${_money(actionableInstallment.remainingAmount)}.';

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailSection(
            title: 'Cliente',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.clientName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                ),
                const SizedBox(height: 12),
                _DetailGrid(
                  items: [
                    _DetailItem(label: 'Cedula', value: sale.clientDocumentId),
                    _DetailItem(label: 'Solar', value: sale.lotDisplayCode),
                    _DetailItem(label: 'Venta', value: '#${sale.saleId}'),
                    _DetailItem(
                      label: 'Modalidad',
                      value: isFinancingActive ? 'Financiamiento' : 'Inicial',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 28),
          _DetailSection(
            title: 'Resumen financiero',
            child: _DetailGrid(
              items: [
                _DetailItem(
                  label: isFinancingActive
                      ? 'Saldo pendiente'
                      : 'Inicial minimo requerido',
                  value: _money(
                    isFinancingActive
                        ? sale.pendingBalance
                        : sale.requiredInitialPayment,
                  ),
                  emphasized: true,
                ),
                _DetailItem(
                  label: 'Inicial real pagado',
                  value: _money(sale.paidInitialPayment),
                ),
                _DetailItem(
                  label: 'Inicial pendiente',
                  value: _money(sale.pendingInitialPayment),
                ),
                if (sale.paidApartadoPayment > 0.009)
                  _DetailItem(
                    label: 'Apartado pagado',
                    value: _money(sale.paidApartadoPayment),
                  ),
                _DetailItem(
                  label: 'Interes mensual',
                  value: '${contextData.monthlyInterest.toStringAsFixed(2)}%',
                ),
              ],
            ),
          ),
          const Divider(height: 28),
          _DetailSection(
            title: 'Estado actual',
            trailing: _SummaryBadge(
              label: !isFinancingActive
                  ? 'Inicial en proceso'
                  : actionableInstallment == null
                  ? 'Ira a capital'
                  : 'Cuota prioritaria',
              color: !isFinancingActive
                  ? const Color(0xFFE67E00)
                  : actionableInstallment == null
                  ? const Color(0xFF3B5BDB)
                  : const Color(0xFFE67E00),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailGrid(
                  items: [
                    _DetailItem(
                      label: 'Pagos realizados',
                      value: '${visibleHistory.length}',
                    ),
                    _DetailItem(label: 'Cuotas pagadas', value: '$paidCount'),
                    _DetailItem(
                      label: 'Cuotas pendientes',
                      value: '$pendingCount',
                    ),
                    _DetailItem(
                      label: 'Proxima prioridad',
                      value: actionableInstallment == null
                          ? 'Capital'
                          : 'Cuota #${actionableInstallment.installmentNumber}',
                    ),
                    _DetailItem(
                      label: 'Fecha de corte',
                      value: _dateRange == null
                          ? 'Sin rango'
                          : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE4EAF2)),
                  ),
                  child: Text(
                    nextActionText,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF556079),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 28),
          _DetailSection(
            title: 'Historial',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: visibleHistory.isEmpty
                      ? null
                      : () => _showClientPagares(contextData),
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                  label: const Text(
                    'Ver pagos',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: visibleHistory.isEmpty
                      ? null
                      : () => _printFromHistory(contextData, visibleHistory),
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('Imprimir', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            child: visibleHistory.isEmpty
                ? const Text(
                    'Todavia no hay pagos registrados para esta venta.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF8893AA)),
                  )
                : SizedBox(
                    height: scrollable ? 304 : 280,
                    child: Scrollbar(
                      controller: _historyScrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _historyScrollController,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: visibleHistory.length,
                        separatorBuilder: (_, _) => const Divider(height: 12),
                        itemBuilder: (context, index) {
                          final payment = visibleHistory[index];
                          return _HistoryRow(
                            title: _paymentTypeLabel(
                              payment.paymentType,
                              payment.installmentNumber,
                            ),
                            subtitle:
                                '${_formatDate(payment.paymentDate)} - ${_capitalize(payment.paymentMethod)}',
                            amount: _money(payment.amountPaid),
                            color: _paymentTypeColor(payment.paymentType),
                            icon: _paymentTypeIcon(payment.paymentType),
                            isAnnulled: payment.isAnnulled,
                            canDelete:
                                (canCancelPayments || isAdmin) &&
                                payment.id ==
                                    _latestAnnullablePaymentId(visibleHistory) &&
                                !_controller.isSaving,
                            selected: selectedHistoryPaymentId == payment.id,
                            onTap: () {
                              setState(() {
                                _selectedHistoryPaymentId = payment.id;
                              });
                            },
                            onDeleteTap: () =>
                                _confirmDeletePayment(payment, contextData),
                            onReceiptTap: () => _showReceiptDialog(payment.id),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (contextData.annulledHistory.isNotEmpty) ...[
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Pagos anulados',
              child: SizedBox(
                height: contextData.annulledHistory.length > 2 ? 200 : null,
                child: contextData.annulledHistory.length > 2
                    ? ListView.separated(
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: contextData.annulledHistory.length,
                        separatorBuilder: (_, _) => const Divider(height: 12),
                        itemBuilder: (context, index) => _annulledHistoryRow(
                          contextData.annulledHistory[index],
                        ),
                      )
                    : Column(
                        children: [
                          for (final annulled in contextData.annulledHistory)
                            _annulledHistoryRow(annulled),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDFEFF), Color(0xFFF3F7FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E0EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140D2844),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              height: 5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D2844), Color(0xFF2C5282)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            if (scrollable)
              Expanded(child: SingleChildScrollView(child: content))
            else
              content,
          ],
        ),
      ),
    );
  }

  Future<void> _openFiltersDialog() async {
    var tempInstallmentFilter = _installmentFilter;
    var tempSortOrder = _sortOrder;
    var tempDateRange = _dateRange;

    final result = await showDialog<_PaymentViewFilters>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filtros de cuotas'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado de cuota',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'Todas',
                          selected: tempInstallmentFilter == 'all',
                          onSelected: () {
                            setDialogState(() {
                              tempInstallmentFilter = 'all';
                            });
                          },
                        ),
                        _buildFilterChip(
                          label: 'Pendientes futuras',
                          selected: tempInstallmentFilter == 'pending',
                          onSelected: () {
                            setDialogState(() {
                              tempInstallmentFilter = 'pending';
                            });
                          },
                        ),
                        _buildFilterChip(
                          label: 'Vencidas',
                          selected: tempInstallmentFilter == 'overdue',
                          onSelected: () {
                            setDialogState(() {
                              tempInstallmentFilter = 'overdue';
                            });
                          },
                        ),
                        _buildFilterChip(
                          label: 'Parciales',
                          selected: tempInstallmentFilter == 'partial',
                          onSelected: () {
                            setDialogState(() {
                              tempInstallmentFilter = 'partial';
                            });
                          },
                        ),
                        _buildFilterChip(
                          label: 'Pagadas',
                          selected: tempInstallmentFilter == 'paid',
                          onSelected: () {
                            setDialogState(() {
                              tempInstallmentFilter = 'paid';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Rango de fechas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final selectedRange = tempDateRange;
                              final label = selectedRange == null
                                  ? 'Sin rango aplicado.'
                                  : '${_formatDate(selectedRange.start)} - ${_formatDate(selectedRange.end)}';

                              return Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7494),
                                ),
                              );
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDateRange: tempDateRange,
                            );
                            if (picked == null) {
                              return;
                            }
                            setDialogState(() {
                              tempDateRange = picked;
                            });
                          },
                          child: const Text('Elegir rango'),
                        ),
                        if (tempDateRange != null)
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                tempDateRange = null;
                              });
                            },
                            child: const Text('Quitar'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Orden',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'Mas reciente',
                          selected: tempSortOrder == 'recent',
                          onSelected: () {
                            setDialogState(() {
                              tempSortOrder = 'recent';
                            });
                          },
                        ),
                        _buildFilterChip(
                          label: 'Mas antigua',
                          selected: tempSortOrder == 'oldest',
                          onSelected: () {
                            setDialogState(() {
                              tempSortOrder = 'oldest';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      const _PaymentViewFilters(
                        installmentFilter: 'all',
                        sortOrder: 'recent',
                      ),
                    );
                  },
                  child: const Text('Limpiar filtros'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _PaymentViewFilters(
                        installmentFilter: tempInstallmentFilter,
                        sortOrder: tempSortOrder,
                        dateRange: tempDateRange,
                      ),
                    );
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _installmentFilter = result.installmentFilter;
      _sortOrder = result.sortOrder;
      _dateRange = result.dateRange;
    });
    _controller.reloadWorkQueue(state: _workQueueStateForFilter());
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFFEAF0FB),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? const Color(0xFF3B5BDB) : const Color(0xFF556079),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? const Color(0xFF3B5BDB) : const Color(0xFFD0D7E4),
        ),
      ),
      backgroundColor: Colors.white,
    );
  }

  List<PaymentSaleOption> _matchSales(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final normalizedQuery = _normalizeSearchValue(rawQuery);
    if (query.isEmpty) {
      return _controller.activeSales;
    }

    final localMatches = _controller.activeSales
        .where((sale) {
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

          return haystack.contains(query) ||
              (normalizedQuery.isNotEmpty &&
                  normalizedHaystack.contains(normalizedQuery));
        })
        .toList(growable: false);

    // Resultados autoritativos del backend (PostgreSQL): permiten encontrar
    // ventas que NO estan en la pagina cargada de la cola de trabajo.
    final merged = <PaymentSaleOption>[];
    final seenSaleIds = <int>{};
    for (final sale in [...localMatches, ..._controller.searchResults]) {
      if (seenSaleIds.add(sale.saleId)) {
        merged.add(sale);
      }
    }
    return merged;
  }

  void _handleSearchChanged(String value) {
    final normalized = value.trim();
    setState(() {
      _searchQuery = normalized;
    });
    _searchDebounce?.cancel();
    if (normalized.isEmpty) {
      _controller.clearSearch();
      return;
    }
    if (normalized.length < 2) {
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) {
        return;
      }
      _controller.searchSales(normalized);
    });
  }

  void _handleSearchSubmitted(String value) {
    if (value.trim().isEmpty) {
      return;
    }

    _searchDebounce?.cancel();
    _controller.searchSales(value);

    final matches = _matchSales(value);
    if (matches.length != 1) {
      return;
    }

    _commitSaleSelection(matches.first.saleId);
  }

  int? get _effectiveSelectedSaleId =>
      _selectedSaleId ?? _controller.selectedSaleId;

  void _commitSaleSelection(int saleId) {
    _searchDebounce?.cancel();
    _saleSearchController.clear();
    _controller.clearSearch();
    setState(() {
      _searchQuery = '';
      _selectedSaleId = saleId;
      _selectedHistoryPaymentId = null;
    });

    if (_controller.selectedSaleId != saleId) {
      _controller.selectSale(saleId);
    }
  }

  void _syncSelectedSaleState() {
    final controllerSaleId = _controller.selectedSaleId;
    final controllerContext = _controller.selectedContext;
    var needsRefresh = false;

    if (!mounted) {
      return;
    }

    if (controllerSaleId != null && controllerContext != null) {
      _saleContextCache[controllerSaleId] = controllerContext;
      needsRefresh = true;
    }

    final activeSaleIds = _controller.activeSales
        .map((sale) => sale.saleId)
        .toSet();
    if (_saleContextCache.keys.any(
      (saleId) => !activeSaleIds.contains(saleId),
    )) {
      _saleContextCache.removeWhere(
        (saleId, _) => !activeSaleIds.contains(saleId),
      );
      needsRefresh = true;
    }

    if (controllerSaleId != null && controllerSaleId != _selectedSaleId) {
      _selectedSaleId = controllerSaleId;
      needsRefresh = true;
    }

    _ensureSaleContextsHydrated();

    if (needsRefresh) {
      setState(() {});
    }
  }

  String _normalizeSearchValue(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }

  Future<void> _ensureSaleContextsHydrated() async {
    if (_isHydratingSaleContexts || _controller.activeSales.isEmpty) {
      return;
    }

    final missingSales = _controller.activeSales
        .where((sale) => !_saleContextCache.containsKey(sale.saleId))
        .toList(growable: false);
    if (missingSales.isEmpty) {
      return;
    }

    _isHydratingSaleContexts = true;
    try {
      for (final sale in missingSales) {
        try {
          final context = await widget.paymentsRepository.fetchSaleContext(
            sale.saleId,
          );
          if (!mounted) {
            return;
          }
          if (context != null) {
            _saleContextCache[sale.saleId] = context;
          }
        } catch (_) {}
      }
    } finally {
      _isHydratingSaleContexts = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool _hasPendingSaleContexts(List<PaymentSaleOption> sales) {
    return sales.any((sale) => !_saleContextCache.containsKey(sale.saleId));
  }

  int _totalInstallmentsForSales(List<PaymentSaleOption> sales) {
    var total = 0;
    for (final sale in sales) {
      total += _saleContextCache[sale.saleId]?.installments.length ?? 0;
    }
    return total;
  }

  List<_PaymentInstallmentEntry> _filteredInstallmentEntries(
    List<PaymentSaleOption> sales,
  ) {
    final items = <_PaymentInstallmentEntry>[];

    for (final sale in sales) {
      final context = _saleContextCache[sale.saleId];
      if (context == null) {
        continue;
      }

      for (final installment in context.installments) {
        items.add(
          _PaymentInstallmentEntry(
            saleId: sale.saleId,
            installment: installment,
          ),
        );
      }
    }

    items.retainWhere((item) {
      if (_installmentFilter != 'all' &&
          !_matchesInstallmentFilter(item.installment)) {
        return false;
      }

      if (_dateRange != null && !_matchesDateRange(item.installment.dueDate)) {
        return false;
      }

      return true;
    });

    items.sort((left, right) {
      final compare = left.installment.dueDate.compareTo(
        right.installment.dueDate,
      );
      if (compare != 0) {
        return _sortOrder == 'recent' ? -compare : compare;
      }

      final installmentCompare = left.installment.installmentNumber.compareTo(
        right.installment.installmentNumber,
      );
      return _sortOrder == 'recent' ? -installmentCompare : installmentCompare;
    });

    return items;
  }

  List<_PaymentInstallmentEntry> _filteredWorkQueueEntries(
    List<PaymentWorkQueueEntry> entries,
  ) {
    final items = entries
        .map(
          (entry) => _PaymentInstallmentEntry(
            saleId: entry.sale.saleId,
            installment: entry.installment,
          ),
        )
        .toList();

    items.retainWhere((item) {
      if (_dateRange != null && !_matchesDateRange(item.installment.dueDate)) {
        return false;
      }
      return true;
    });

    items.sort((left, right) {
      final compare = left.installment.dueDate.compareTo(
        right.installment.dueDate,
      );
      if (compare != 0) {
        return _sortOrder == 'recent' ? -compare : compare;
      }

      final installmentCompare = left.installment.installmentNumber.compareTo(
        right.installment.installmentNumber,
      );
      return _sortOrder == 'recent' ? -installmentCompare : installmentCompare;
    });

    return items;
  }

  String _workQueueStateForFilter() {
    return switch (_installmentFilter) {
      'overdue' => 'overdue',
      'pending' => 'pending',
      'partial' => 'partial',
      'paid' => 'paid',
      _ => 'collectible',
    };
  }

  List<PaymentHistoryItem> _filteredHistory(List<PaymentHistoryItem> history) {
    final items = List<PaymentHistoryItem>.from(history);
    items.retainWhere((payment) {
      if (_dateRange != null && !_matchesDateRange(payment.paymentDate)) {
        return false;
      }
      return true;
    });
    items.sort((left, right) {
      final compare = left.paymentDate.compareTo(right.paymentDate);
      return _sortOrder == 'recent' ? -compare : compare;
    });
    return items;
  }

  /// Pago activo mas reciente (candidato unico a anulacion segun el backend).
  int? _latestAnnullablePaymentId(List<PaymentHistoryItem> history) {
    PaymentHistoryItem? latest;
    for (final payment in history) {
      if (payment.isAnnulled) {
        continue;
      }
      if (latest == null ||
          payment.paymentDate.isAfter(latest.paymentDate) ||
          (payment.paymentDate.isAtSameMomentAs(latest.paymentDate) &&
              payment.id > latest.id)) {
        latest = payment;
      }
    }
    return latest?.id;
  }

  bool _matchesInstallmentFilter(Installment installment) {
    final status = _statusCategory(installment);
    return switch (_installmentFilter) {
      'pending' => status == 'pending',
      'overdue' => status == 'overdue',
      'partial' => _isPartialInstallment(installment),
      'paid' => status == 'paid',
      _ => true,
    };
  }

  bool _isPartialInstallment(Installment installment) {
    return installment.paidAmount > 0.009 &&
        installment.remainingAmount > 0.009 &&
        _statusCategory(installment) != 'paid';
  }

  bool _matchesDateRange(DateTime value) {
    final range = _dateRange;
    if (range == null) {
      return true;
    }

    final normalized = DateTime(value.year, value.month, value.day);
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return !normalized.isBefore(start) && !normalized.isAfter(end);
  }

  String _statusCategory(Installment installment) {
    final label = _statusLabel(installment);
    if (label == 'pagada' || label == 'ajustada') {
      return 'paid';
    }
    if (label.contains('vencida')) {
      return 'overdue';
    }
    return 'pending';
  }

  Future<void> _registerPayment({String? initialPaymentType}) async {
    final contextData = _controller.selectedContext;
    if (contextData == null) {
      return;
    }

    final currentUserId = context.read<AuthProvider>().currentUser?.id;

    final draft = await PaymentFormDialog.show(
      context,
      sale: contextData.sale,
      defaultPaymentMethod: _controller.defaultPaymentMethod,
      registeredByUserId: currentUserId,
      actionableInstallment: contextData.actionableInstallment,
      overdueInstallments: contextData.overdueInstallments,
      initialPaymentType: initialPaymentType,
    );
    if (!mounted || draft == null) {
      return;
    }

    final confirmed = await _confirmApplyPayment(
      sale: contextData.sale,
      draft: draft,
    );
    if (!mounted || !confirmed) {
      return;
    }

    final error = await _controller.registerPayment(draft);
    if (!mounted) {
      return;
    }

    if (error == null) {
      final updatedContext = _controller.selectedContext;
      if (updatedContext != null && updatedContext.history.isNotEmpty) {
        final lastPaymentId = updatedContext.history.first.id;
        setState(() {
          _selectedHistoryPaymentId = lastPaymentId;
        });
        if (draft.printReceiptAutomatically) {
          await _showReceiptDialog(lastPaymentId, autoPrint: true);
        } else {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Pago registrado correctamente.')),
          );
        }
      }
      return;
    }

    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<bool> _confirmApplyPayment({
    required PaymentSaleOption sale,
    required PaymentDraft draft,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final typeLabel = _draftPaymentTypeLabel(sale, draft);
        return AlertDialog(
          icon: const Icon(Icons.verified_outlined),
          title: const Text('Confirmar pago'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estas seguro de aplicar este pago?'),
              const SizedBox(height: 14),
              _PaymentConfirmationRow(
                label: 'Monto',
                value: _money(draft.amountPaid),
                emphasized: true,
              ),
              _PaymentConfirmationRow(
                label: 'Cliente',
                value: sale.clientName.trim().isEmpty
                    ? '-'
                    : sale.clientName.trim(),
              ),
              _PaymentConfirmationRow(
                label: 'Solar',
                value: sale.lotDisplayCode.trim().isEmpty
                    ? '-'
                    : sale.lotDisplayCode.trim(),
              ),
              _PaymentConfirmationRow(label: 'Tipo', value: typeLabel),
              _PaymentConfirmationRow(
                label: 'Metodo',
                value: _capitalize(draft.paymentMethod),
              ),
              if (draft.yearToPay != null && draft.yearToPay!.trim().isNotEmpty)
                _PaymentConfirmationRow(
                  label: 'Ano aplicado',
                  value: draft.yearToPay!.trim(),
                ),
              if (draft.printReceiptAutomatically)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Se imprimira el recibo automaticamente despues de guardar.',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Aplicar pago'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _showReceiptDialog(
    int paymentId, {
    bool autoPrint = false,
  }) async {
    await ReceiptDialog.printQuick(
      context,
      paymentId: paymentId,
      receiptRepository: widget._receiptRepository,
    );
  }

  Future<void> _showClientPagares(PaymentSaleContext contextData) async {
    if (contextData.history.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    await openSalePaymentHistoryFullscreen(
      context,
      sale: contextData.sale,
      history: contextData.history,
    );
  }

  Future<ClientPagareReport?> _loadClientPagareReport(int clientId) async {
    try {
      final ClientPagareReport report = await widget.paymentsRepository
          .fetchClientPagareReport(clientId);

      if (!mounted) {
        return null;
      }

      if (report.items.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'El cliente no tiene pagares/pagos registrados todavia.',
            ),
          ),
        );
        return null;
      }
      return report;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      FriendlyErrorMessages.forOperation(
        'generar el reporte de pagares',
        error,
        module: 'reportes',
      );
      return null;
    }
  }

  int? _resolveSelectedHistoryPaymentId(List<PaymentHistoryItem> history) {
    if (history.isEmpty) {
      return null;
    }

    final selectedPaymentId = _selectedHistoryPaymentId;
    if (selectedPaymentId != null &&
        history.any((payment) => payment.id == selectedPaymentId)) {
      return selectedPaymentId;
    }

    return history.first.id;
  }

  PaymentHistoryItem? _resolveSelectedHistoryPayment(
    List<PaymentHistoryItem> history,
  ) {
    final selectedPaymentId = _resolveSelectedHistoryPaymentId(history);
    if (selectedPaymentId == null) {
      return null;
    }

    for (final payment in history) {
      if (payment.id == selectedPaymentId) {
        return payment;
      }
    }

    return null;
  }

  Future<void> _printFromHistory(
    PaymentSaleContext contextData,
    List<PaymentHistoryItem> visibleHistory,
  ) async {
    final selectedChoice = await showDialog<_PaymentPrintChoice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Que deseas imprimir?'),
          content: const SizedBox(
            width: 360,
            child: Text(
              'Puedes imprimir el ticket del pago seleccionado o la lista completa de pagos del cliente.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_PaymentPrintChoice.ticket),
              child: const Text('Ticket'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_PaymentPrintChoice.list),
              child: const Text('Lista de pagos'),
            ),
          ],
        );
      },
    );

    if (!mounted || selectedChoice == null) {
      return;
    }

    if (selectedChoice == _PaymentPrintChoice.ticket) {
      final selectedPayment = _resolveSelectedHistoryPayment(visibleHistory);
      if (selectedPayment == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Selecciona un pago para imprimir el ticket.'),
          ),
        );
        return;
      }

      await ReceiptDialog.printQuick(
        context,
        paymentId: selectedPayment.id,
        receiptRepository: widget._receiptRepository,
      );
      return;
    }

    final report = await _loadClientPagareReport(contextData.sale.clientId);
    if (!mounted || report == null) {
      return;
    }

    await ClientPagareDialog.printQuick(context, report: report);
  }

  Widget _annulledHistoryRow(PaymentHistoryItem payment) {
    return _HistoryRow(
      title: _paymentTypeLabel(payment.paymentType, payment.installmentNumber),
      subtitle: _annulledSubtitle(payment),
      amount: _money(payment.amountPaid),
      color: const Color(0xFF8A94A6),
      icon: Icons.block_outlined,
      isAnnulled: true,
      canDelete: false,
      selected: false,
      onReceiptTap: () => _showReceiptDialog(payment.id),
    );
  }

  String _annulledSubtitle(PaymentHistoryItem payment) {
    final annulledAt = payment.annulledAt;
    final parts = <String>[
      if (annulledAt != null) 'Anulado ${_formatDate(annulledAt)}',
      _capitalize(payment.paymentMethod),
      if ((payment.annulmentReason ?? '').trim().isNotEmpty)
        payment.annulmentReason!.trim(),
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(' · ');
  }

  Future<void> _confirmDeletePayment(
    PaymentHistoryItem payment,
    PaymentSaleContext contextData,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final canCancelDirectly =
        authProvider.currentUser?.canCancelPayments ?? authProvider.isAdmin;

    final result = await showDialog<PaymentAnnulResult>(
      context: context,
      builder: (dialogContext) => PaymentAnnulDialog(
        clientName: contextData.sale.clientName,
        concept: _paymentTypeLabel(
          payment.paymentType,
          payment.installmentNumber,
        ),
        amount: _money(payment.amountPaid),
        paymentDate: _formatDate(payment.paymentDate),
        requiresAdminAuthorization: !canCancelDirectly,
        onAuthorize: (email, password) =>
            _controller.requestAdminAuthorization(
              paymentId: payment.id,
              email: email,
              password: password,
            ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }

    final error = await _controller.deletePayment(
      paymentId: payment.id,
      preferredSaleId: payment.saleId,
      reason: result.reason,
      adminAuthorizationId: result.adminAuthorizationId,
    );
    if (!mounted) {
      return;
    }

    if (error == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Pago anulado correctamente.')),
      );
      return;
    }

    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  String _statusLabel(Installment installment) {
    final now = DateTime.now();
    if (installment.status == 'pagada') {
      return 'pagada';
    }
    if (installment.status == 'ajustada') {
      return 'ajustada';
    }
    if (installment.dueDate.isBefore(DateTime(now.year, now.month, now.day))) {
      return installment.status == 'parcial' ? 'vencida parcial' : 'vencida';
    }
    return installment.status;
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _money(double value) => 'RD\$ ${formatRdCurrency(value)}';

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _paymentTypeLabel(String paymentType, int? installmentNumber) {
    return switch (paymentType) {
      'apartado' => 'Pago de apartado',
      'abono_inicial' => 'Abono a inicial',
      'abono_capital' => 'Abono a capital',
      _ => 'Pago de cuota #${installmentNumber ?? '-'}',
    };
  }

  String _draftPaymentTypeLabel(PaymentSaleOption sale, PaymentDraft draft) {
    final override = draft.paymentTypeOverride;
    if (override != null && override.trim().isNotEmpty) {
      return switch (override) {
        'apartado' => 'Pago de apartado',
        'abono_inicial' => 'Abono a inicial',
        'abono_capital' => 'Abono a capital',
        'cuota_vencida' => 'Pago de cuota vencida',
        _ => 'Pago de cuota',
      };
    }

    if (!sale.isFinancingActive) {
      return sale.paidInitialPayment <= 0.009
          ? 'Pago de apartado'
          : 'Abono a inicial';
    }

    return 'Pago de cuota';
  }
}

class _PaymentConfirmationRow extends StatelessWidget {
  const _PaymentConfirmationRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: emphasized
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactInstallmentRow extends StatelessWidget {
  const _CompactInstallmentRow({
    required this.installment,
    required this.formattedDate,
    required this.formattedAmount,
    required this.formattedPaid,
    required this.formattedRemaining,
    required this.statusLabel,
    required this.statusColor,
    required this.selected,
    this.onTap,
  });

  final Installment installment;
  final String formattedDate;
  final String formattedAmount;
  final String formattedPaid;
  final String formattedRemaining;
  final String statusLabel;
  final Color statusColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF5F8FF) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: const Color(0xFFF7F9FC),
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    'Cuota #${installment.installmentNumber}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ),
                SizedBox(
                  width: 102,
                  child: Text(
                    formattedDate,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF556079),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    formattedAmount,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2235),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    formattedPaid,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF556079),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    formattedRemaining,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: installment.remainingAmount <= 0.009
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF1A2235),
                    ),
                  ),
                ),
                SizedBox(
                  width: 108,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentInstallmentEntry {
  const _PaymentInstallmentEntry({
    required this.saleId,
    required this.installment,
  });

  final int saleId;
  final Installment installment;
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF8893AA),
                ),
              ),
            ),
            ...(trailing != null ? <Widget>[trailing!] : const <Widget>[]),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items});

  final List<_DetailItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < items.length; index += 2) {
      final left = items[index];
      final right = index + 1 < items.length ? items[index + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DetailValue(item: left)),
            const SizedBox(width: 16),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _DetailValue(item: right),
            ),
          ],
        ),
      );
      if (index + 2 < items.length) {
        rows.add(const SizedBox(height: 12));
      }
    }

    return Column(children: rows);
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.item});

  final _DetailItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8893AA)),
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: item.emphasized ? FontWeight.w700 : FontWeight.w600,
            color: item.emphasized
                ? const Color(0xFF3B5BDB)
                : const Color(0xFF1A2235),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.color,
    required this.icon,
    required this.onReceiptTap,
    required this.canDelete,
    this.selected = false,
    this.onTap,
    this.onDeleteTap,
    this.isAnnulled = false,
  });

  final String title;
  final String subtitle;
  final String amount;
  final Color color;
  final IconData icon;
  final VoidCallback onReceiptTap;
  final bool canDelete;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDeleteTap;

  /// Un pago anulado se conserva como historial/auditoria y ya no admite
  /// acciones financieras.
  final bool isAnnulled;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? const Color(0xFFEAF2FF)
        : const Color(0xFFFDFEFF);
    final borderColor = selected
        ? const Color(0xFF3B5BDB)
        : const Color(0xFFE4EAF2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isAnnulled
                            ? const Color(0xFF8A94A6)
                            : const Color(0xFF1A2235),
                        decoration: isAnnulled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (isAnnulled) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE4A0A0)),
                        ),
                        child: const Text(
                          'ANULADO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Color(0xFFB3261E),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8893AA),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2235),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canDelete)
                    IconButton(
                      tooltip: 'Anular pago',
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: onDeleteTap,
                    ),
                  IconButton(
                    tooltip: 'Imprimir ticket',
                    icon: const Icon(Icons.print_outlined, size: 16),
                    onPressed: onReceiptTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DetailItem {
  const _DetailItem({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;
}

class _PaymentViewFilters {
  const _PaymentViewFilters({
    required this.installmentFilter,
    required this.sortOrder,
    this.dateRange,
  });

  final String installmentFilter;
  final String sortOrder;
  final DateTimeRange? dateRange;
}

enum _PaymentPrintChoice { ticket, list }

Color _installmentColor(String status) {
  return switch (status) {
    'pagada' => const Color(0xFF2E7D32),
    'ajustada' => const Color(0xFF546E7A),
    'vencida' => const Color(0xFFC62828),
    'vencida parcial' => const Color(0xFFE64A19),
    'parcial' => const Color(0xFFE67E00),
    _ => const Color(0xFF3B5BDB),
  };
}

Color _paymentTypeColor(String type) {
  return switch (type) {
    'abono_capital' => const Color(0xFF1565C0),
    'apartado' || 'abono_inicial' => const Color(0xFFE67E00),
    _ => const Color(0xFF2E7D32),
  };
}

IconData _paymentTypeIcon(String type) {
  return switch (type) {
    'abono_capital' => Icons.trending_down_outlined,
    'apartado' || 'abono_inicial' => Icons.flag_outlined,
    _ => Icons.receipt_long_outlined,
  };
}
