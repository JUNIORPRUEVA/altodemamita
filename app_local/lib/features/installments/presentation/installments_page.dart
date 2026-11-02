import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/base_layout.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/installment_correction_repository.dart';
import '../data/installments_repository.dart';
import '../domain/installment_correction.dart';
import '../domain/installment_detail.dart';
import '../../../core/responsive/app_breakpoints.dart';
import 'installment_correction_dialog.dart';
import 'installments_controller.dart';
import 'installments_mobile.dart';

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({super.key, this.saleId});

  final int? saleId;

  @override
  State<InstallmentsPage> createState() => _InstallmentsPageState();
}

class _InstallmentsPageState extends State<InstallmentsPage> {
  late InstallmentsController _controller;
  late TextEditingController _searchController;
  final InstallmentCorrectionRepository _correctionRepository =
      InstallmentCorrectionRepository();
  bool _correctionBusy = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

    final repository = InstallmentsRepository();
    _controller = InstallmentsController(installmentsRepository: repository);

    // Load data based on whether a specific sale is selected
    if (widget.saleId != null) {
      _controller.loadBySaleId(widget.saleId!);
    } else {
      _controller.load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Layout compacto (PWA / mobile / tablet): patrón visual de Ventas.
    if (AppBreakpoints.usesCompactNavigation(context)) {
      return ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => InstallmentsMobileView(
          installments: _controller.installments,
          isLoading: _controller.isLoading,
          totalFinanced: _controller.totalFinanced,
          totalPaid: _controller.totalPaid,
          totalPending: _controller.totalPending,
          hasOverdue: _controller.hasOverdue,
          totalOverdueAmount: _controller.totalOverdueAmount,
          onSearch: _controller.search,
          onClearSearch: () => _controller.search(''),
          onRetry: () => widget.saleId == null
              ? _controller.load()
              : _controller.loadBySaleId(widget.saleId!),
        ),
      );
    }

    return BaseLayout(
      title: 'Cuotas',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(),
            if (context.watch<AuthProvider>().isAdmin && widget.saleId != null)
              _ownerCorrectionsBar(),
            if (_controller.isLoading && !_controller.hasVisibleData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              if (_controller.selectedSaleSummary != null)
                _buildSaleSummaryStrip(_controller.selectedSaleSummary!)
              else if (_controller.installments.isNotEmpty)
                _buildGeneralSummaryStrip(),

              // ── List ────────────────────────────────────────────────
              Expanded(
                child: _controller.installments.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
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
                                  Icons.view_list_outlined,
                                  size: 34,
                                  color: Color(0xFF3B5BDB),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                widget.saleId != null
                                    ? 'Esta venta todavía no tiene cuotas activas.'
                                    : 'No hay cuotas registradas.',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A2235),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              if (widget.saleId != null)
                                const Text(
                                  'El financiamiento inicia cuando el inicial queda completo.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8893AA),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.white,
                        child: ListView.separated(
                          itemCount: _controller.installments.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 64),
                          itemBuilder: (context, index) {
                            return _buildInstallmentRow(
                              _controller.installments[index],
                            );
                          },
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1100;

          final searchField = SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, cédula, solar o venta…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _controller.search('');
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD0D7E4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD0D7E4)),
                ),
              ),
              onChanged: (value) {
                _controller.search(value);
                setState(() {});
              },
            ),
          );

          final filterRow = SizedBox(
            height: 36,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusChip('Todos', null),
                  const SizedBox(width: 8),
                  _buildStatusChip('Pendiente', 'pendiente'),
                  const SizedBox(width: 8),
                  _buildStatusChip('Parcial', 'parcial'),
                  const SizedBox(width: 8),
                  _buildStatusChip('Pagada', 'pagada'),
                  const SizedBox(width: 8),
                  _buildStatusChip('Vencida', 'vencida'),
                ],
              ),
            ),
          );

          if (compact) {
            return Column(
              children: [
                searchField,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: filterRow),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 7, child: searchField),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: filterRow,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSaleSummaryStrip(SaleInstallmentsSummary summary) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.clientName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2235),
                      ),
                    ),
                    Text(
                      '${summary.lotCode}  ·  ${summary.clientDocumentId}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8893AA),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${summary.paidInstallments}/${summary.totalInstallments} cuotas pagadas',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B5BDB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _StatChip(
                label: 'Cuotas restantes',
                value: '${summary.pendingInstallments}',
                color: const Color(0xFF8E24AA),
              ),
              _StatChip(
                label: 'Total financiado',
                value: InstallmentsController.formatCurrency(
                  summary.totalFinanced,
                ),
                color: const Color(0xFF3B5BDB),
              ),
              _StatChip(
                label: 'Pagado',
                value: InstallmentsController.formatCurrency(summary.totalPaid),
                color: const Color(0xFF2E7D32),
              ),
              _StatChip(
                label: 'Pendiente',
                value: InstallmentsController.formatCurrency(
                  summary.totalPending,
                ),
                color: const Color(0xFFE67E00),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSummaryStrip() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatChip(
            label: 'Total financiado',
            value: InstallmentsController.formatCurrency(
              _controller.totalFinanced,
            ),
            color: const Color(0xFF3B5BDB),
          ),
          _StatChip(
            label: 'Pagado',
            value: InstallmentsController.formatCurrency(_controller.totalPaid),
            color: const Color(0xFF2E7D32),
          ),
          _StatChip(
            label: 'Pendiente',
            value: InstallmentsController.formatCurrency(
              _controller.totalPending,
            ),
            color: const Color(0xFFE67E00),
          ),
          if (_controller.hasOverdue)
            _StatChip(
              label: 'Vencido',
              value: InstallmentsController.formatCurrency(
                _controller.totalOverdueAmount,
              ),
              color: const Color(0xFFC62828),
              warning: true,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String? status) {
    final isSelected = _controller.selectedStatus == status;
    final color = status == null
        ? const Color(0xFF3B5BDB)
        : _instStatusColor(status);

    return GestureDetector(
      onTap: () => _controller.filterByStatus(
        isSelected && status != null ? null : status,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFD0D7E4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? color : const Color(0xFF6B7494),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallmentRow(InstallmentDetail installment) {
    final status = installment.calculatedStatus;
    final statusColor = _instStatusColor(status);
    final statusLabel = _instStatusLabel(status);
    final progress = installment.totalAmount > 0
        ? (installment.paidAmount / installment.totalAmount).clamp(0.0, 1.0)
        : 0.0;
    // FASE 02: el menu administrativo solo se ofrece a OWNER y solo en cuotas
    // sin pagos aplicados; el backend valida lo mismo de forma obligatoria.
    final canCorrect =
        context.watch<AuthProvider>().isAdmin && installment.paidAmount <= 0.009;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 92,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${installment.installmentNumber}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            installment.clientName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A2235),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${installment.lotCode}  ·  ${installment.clientDocumentId}',
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
                    SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Vence',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF8893AA),
                            ),
                          ),
                          Text(
                            _formatDate(installment.dueDate),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A2235),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Cuota fija',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF8893AA),
                            ),
                          ),
                          Text(
                            InstallmentsController.formatCurrency(
                              installment.totalAmount,
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A2235),
                            ),
                          ),
                          Text(
                            'Rest. ${InstallmentsController.formatCurrency(installment.remainingAmount)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: installment.remainingAmount <= 0.009
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF8893AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (canCorrect) ...[
                      const SizedBox(width: 4),
                      _rowCorrectionMenu(installment),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 50),
                    Expanded(
                      child: Text(
                        'Saldo inicial ${InstallmentsController.formatCurrency(installment.openingBalance)} · Interés ${InstallmentsController.formatCurrency(installment.interestAmount)} · Capital ${InstallmentsController.formatCurrency(installment.principalAmount)} · Saldo final ${InstallmentsController.formatCurrency(installment.endingBalance)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7494),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Thin progress bar as bottom accent
        LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          backgroundColor: const Color(0xFFF0F3F8),
          color: statusColor.withValues(alpha: 0.5),
        ),
      ],
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _reloadSchedule() async {
    if (widget.saleId != null) {
      await _controller.loadBySaleId(widget.saleId!);
    } else {
      await _controller.load();
    }
  }

  /// FASE 02 — Correccion OWNER del cronograma de cuotas.
  Future<void> _openCorrection({
    required String action,
    InstallmentDetail? installment,
  }) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAdmin) {
      _toast('No tienes permisos para corregir el cronograma.');
      return;
    }
    final saleId = installment?.saleId ?? widget.saleId;
    if (saleId == null) {
      _toast('Selecciona una venta para corregir su cronograma.');
      return;
    }
    if (_correctionBusy) {
      return;
    }

    Future<InstallmentCorrectionPreview> runPreview(
      DateTime? dueDate,
      double? principalAmount,
      double? interestAmount,
      int? installmentCount,
      DateTime? firstDueDate,
    ) {
      return _correctionRepository.preview(
        saleId: saleId,
        action: action,
        installmentId: installment?.id,
        dueDate: dueDate,
        principalAmount: principalAmount,
        interestAmount: interestAmount,
        installmentCount: installmentCount,
        firstDueDate: firstDueDate,
      );
    }

    final applied = await showDialog<bool>(
      context: context,
      builder: (_) => InstallmentCorrectionDialog(
        action: action,
        title: InstallmentCorrectionAction.label(action),
        installmentNumber: installment?.installmentNumber,
        currentDueDate: installment?.dueDate,
        currentPrincipal: installment?.principalAmount,
        currentInterest: installment?.interestAmount,
        loadPreview:
            ({
              dueDate,
              principalAmount,
              interestAmount,
              installmentCount,
              firstDueDate,
            }) => runPreview(
              dueDate,
              principalAmount,
              interestAmount,
              installmentCount,
              firstDueDate,
            ),
        apply:
            ({
              required reason,
              dueDate,
              principalAmount,
              interestAmount,
              installmentCount,
              firstDueDate,
            }) async {
              final preview = await runPreview(
                dueDate,
                principalAmount,
                interestAmount,
                installmentCount,
                firstDueDate,
              );
              if (!preview.allowed) {
                throw Exception(
                  preview.message.isEmpty
                      ? 'El servidor no autoriza esta correccion.'
                      : preview.message,
                );
              }
              return _correctionRepository.apply(
                saleId: saleId,
                action: action,
                reason: reason,
                expectedSaleVersion: preview.saleVersion,
                installmentId: installment?.id,
                dueDate: dueDate,
                principalAmount: principalAmount,
                interestAmount: interestAmount,
                installmentCount: installmentCount,
                firstDueDate: firstDueDate,
              );
            },
      ),
    );
    if (applied != true || !mounted) {
      return;
    }
    setState(() => _correctionBusy = true);
    try {
      await _reloadSchedule();
      if (!mounted) return;
      _toast('Cronograma actualizado. Los saldos se recalcularon.');
    } catch (_) {
      if (!mounted) return;
      _toast('La correccion se aplico, pero no se pudo refrescar la lista.');
    } finally {
      if (mounted) {
        setState(() => _correctionBusy = false);
      }
    }
  }

  Future<void> _showScheduleAudit() async {
    final auth = context.read<AuthProvider>();
    final saleId = widget.saleId;
    if (!auth.isAdmin || saleId == null) {
      _toast('Selecciona una venta como administrador para ver la auditoria.');
      return;
    }
    setState(() => _correctionBusy = true);
    Map<String, dynamic> data;
    try {
      data = await _correctionRepository.fetchAudit(saleId: saleId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _correctionBusy = false);
      _toast('No se pudo cargar la auditoria: ${error.toString()}');
      return;
    }
    if (!mounted) return;
    setState(() => _correctionBusy = false);
    await showDialog<void>(
      context: context,
      builder: (_) => _ScheduleAuditDialog(data: data),
    );
  }

  Widget _ownerCorrectionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFDFE),
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings_outlined, size: 16, color: Color(0xFF1F4B99)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Correcciones del cronograma (administrador)',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7494)),
            ),
          ),
          TextButton.icon(
            onPressed: _correctionBusy
                ? null
                : () => _openCorrection(
                    action: InstallmentCorrectionAction.addInstallment,
                  ),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Agregar cuota', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: _correctionBusy
                ? null
                : () => _openCorrection(
                    action: InstallmentCorrectionAction.reschedule,
                  ),
            icon: const Icon(Icons.event_repeat, size: 15),
            label: const Text('Reprogramar', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: _correctionBusy ? null : _showScheduleAudit,
            icon: const Icon(Icons.history, size: 15),
            label: const Text('Auditoria', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _rowCorrectionMenu(InstallmentDetail installment) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones administrativas de la cuota',
      padding: EdgeInsets.zero,
      iconSize: 16,
      splashRadius: 16,
      icon: const Icon(Icons.more_horiz, color: Color(0xFF1F4B99)),
      onSelected: (value) =>
          _openCorrection(action: value, installment: installment),
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: InstallmentCorrectionAction.changeDueDate,
          child: Text('Cambiar vencimiento', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem<String>(
          value: InstallmentCorrectionAction.changeAmounts,
          child: Text('Editar montos', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem<String>(
          value: InstallmentCorrectionAction.removeInstallment,
          child: Text('Eliminar cuota', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// FASE 02 — Auditoria de solo lectura del cronograma.
class _ScheduleAuditDialog extends StatelessWidget {
  const _ScheduleAuditDialog({required this.data});

  final Map<String, dynamic> data;

  String _date(Object? raw) {
    final value = DateTime.tryParse((raw ?? '').toString());
    if (value == null) return '-';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rawHistory = data['history'];
    final history = rawHistory is List
        ? rawHistory
              .whereType<Map>()
              .map((entry) => entry.map((k, v) => MapEntry(k.toString(), v)))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];

    return AlertDialog(
      title: const Text('Auditoria del cronograma', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 480,
        child: history.isEmpty
            ? const Text(
                'Sin correcciones de cronograma registradas.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7C89A3)),
              )
            : Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in history)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${entry['action'] ?? entry['kind']}'
                                '${entry['installmentNumber'] == null ? '' : ' — cuota #${entry['installmentNumber']}'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A2235),
                                ),
                              ),
                              if ((entry['reason'] ?? '').toString().trim().isNotEmpty)
                                Text(
                                  'Motivo: ${entry['reason']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              Text(
                                _date(entry['at'] ?? entry['performedAt']),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7C89A3),
                                ),
                              ),
                              const Divider(height: 8),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

Color _instStatusColor(String status) {
  return switch (status) {
    'pagada' => const Color(0xFF2E7D32),
    'parcial' => const Color(0xFFE67E00),
    'vencida' => const Color(0xFFC62828),
    _ => const Color(0xFF3B5BDB),
  };
}

String _instStatusLabel(String status) {
  return switch (status) {
    'pagada' => 'Pagada',
    'parcial' => 'Parcial',
    'vencida' => 'Vencida',
    _ => 'Pendiente',
  };
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    this.warning = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (warning) ...[
            Icon(Icons.warning_amber_rounded, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
