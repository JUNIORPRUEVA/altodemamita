import 'package:flutter/material.dart';

import '../../../shared/widgets/base_layout.dart';
import '../data/installments_repository.dart';
import '../domain/installment_detail.dart';
import 'installments_controller.dart';

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({
    super.key,
    this.saleId,
  });

  final int? saleId;

  @override
  State<InstallmentsPage> createState() => _InstallmentsPageState();
}

class _InstallmentsPageState extends State<InstallmentsPage> {
  late InstallmentsController _controller;
  late TextEditingController _searchController;

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
    return BaseLayout(
      title: 'Cuotas',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(),
            if (_controller.isLoading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else ...[
                if (_controller.selectedSaleSummary != null)
                  _buildSaleSummaryStrip(
                      _controller.selectedSaleSummary!)
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
                                    borderRadius:
                                        BorderRadius.circular(22),
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
                                        color: Color(0xFF8893AA)),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.white,
                          child: ListView.separated(
                            itemCount:
                                _controller.installments.length,
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: filterRow,
                ),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                          fontSize: 12, color: Color(0xFF8893AA)),
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
                    summary.totalFinanced),
                color: const Color(0xFF3B5BDB),
              ),
              _StatChip(
                label: 'Pagado',
                value: InstallmentsController.formatCurrency(
                    summary.totalPaid),
                color: const Color(0xFF2E7D32),
              ),
              _StatChip(
                label: 'Pendiente',
                value: InstallmentsController.formatCurrency(
                    summary.totalPending),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatChip(
            label: 'Total financiado',
            value: InstallmentsController.formatCurrency(
                _controller.totalFinanced),
            color: const Color(0xFF3B5BDB),
          ),
          _StatChip(
            label: 'Pagado',
            value: InstallmentsController.formatCurrency(
                _controller.totalPaid),
            color: const Color(0xFF2E7D32),
          ),
          _StatChip(
            label: 'Pendiente',
            value: InstallmentsController.formatCurrency(
                _controller.totalPending),
            color: const Color(0xFFE67E00),
          ),
          if (_controller.hasOverdue)
            _StatChip(
              label: 'Vencido',
              value: InstallmentsController.formatCurrency(
                  _controller.totalOverdueAmount),
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
          isSelected && status != null ? null : status),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : const Color(0xFFD0D7E4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
                isSelected ? FontWeight.w700 : FontWeight.w500,
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
        ? (installment.paidAmount / installment.totalAmount)
              .clamp(0.0, 1.0)
        : 0.0;

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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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
                    color: color.withValues(alpha: 0.7)),
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
