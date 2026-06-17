import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/safe_area_padding.dart';
import '../../core/utils.dart';

class SaleInstallmentsPage extends StatelessWidget {
  const SaleInstallmentsPage({
    super.key,
    required this.sale,
    required this.installments,
  });

  final Map<String, dynamic> sale;
  final List<Map<String, dynamic>> installments;

  @override
  Widget build(BuildContext context) {
    final client = text(sale['client'], 'Cliente');
    final lot = text(sale['lot'], '-');

    // Calculate totals
    double totalCapital = 0;
    double totalInterest = 0;
    double totalPaid = 0;
    double totalEndingBalance = 0;

    for (final inst in installments) {
      totalCapital +=
          num.tryParse(inst['totalAmount']?.toString() ?? '0')?.toDouble() ?? 0;
      totalInterest +=
          num.tryParse(inst['interestAmount']?.toString() ?? '0')?.toDouble() ??
          0;
      totalPaid +=
          num.tryParse(inst['paidAmount']?.toString() ?? '0')?.toDouble() ?? 0;
      totalEndingBalance +=
          num.tryParse(inst['endingBalance']?.toString() ?? '0')?.toDouble() ??
          0;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Cuotas amortizadas',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      body: SafeArea(
        top: false,
        child: installments.isEmpty
            ? _buildEmptyState()
            : Column(
                children: [
                  // Subtitle
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '$client · $lot',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // Installments vertical list
                  Expanded(
                    child: ListView.builder(
                      padding: safeScrollPadding(context, top: 8),
                      itemCount: installments.length,
                      itemBuilder: (context, index) {
                        return _InstallmentRow(
                          installment: installments[index],
                          index: index,
                        );
                      },
                    ),
                  ),
                  // Summary footer
                  _buildSummary(
                    totalCapital,
                    totalInterest,
                    totalPaid,
                    totalEndingBalance,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se encontraron cuotas\nrelacionadas con esta venta.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(
    double totalCapital,
    double totalInterest,
    double totalPaid,
    double totalEndingBalance,
  ) {
    final totalPlan = totalCapital + totalInterest;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _SummaryRow('Capital total', money(totalCapital)),
          _SummaryRow('Interés total', money(totalInterest)),
          _SummaryRow('Total del plan', money(totalPlan), isBold: true),
          const Divider(height: 16),
          _SummaryRow('Total pagado', money(totalPaid)),
          _SummaryRow(
            'Saldo pendiente',
            money(totalEndingBalance),
            isBold: true,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Installment row (vertical list, horizontal scroll inside)
// ──────────────────────────────────────────────

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({required this.installment, required this.index});

  final Map<String, dynamic> installment;
  final int index;

  @override
  Widget build(BuildContext context) {
    final number = text(installment['installmentNumber'], '${index + 1}');
    final status = installment['status']?.toString();
    final dueDate = dateText(installment['dueDate']);
    final totalAmount = money(installment['totalAmount']);
    final paidAmount = money(installment['paidAmount']);
    final endingBalance = money(installment['endingBalance']);
    final capital = money(installment['capitalAmount']);
    final interest = money(installment['interestAmount']);

    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Number badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Due date
              _Cell(label: 'Vence', value: dueDate),
              const SizedBox(width: 12),
              // Cuota
              _Cell(label: 'Cuota', value: totalAmount),
              const SizedBox(width: 12),
              // Capital
              _Cell(label: 'Capital', value: capital),
              const SizedBox(width: 12),
              // Interés
              _Cell(label: 'Interés', value: interest),
              const SizedBox(width: 12),
              // Pagado
              _Cell(label: 'Pagado', value: paidAmount),
              const SizedBox(width: 12),
              // Pendiente
              _Cell(label: 'Pendiente', value: endingBalance),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pagada':
      case 'paid':
      case 'pagado':
        return AppColors.accentGreen;
      case 'pendiente':
      case 'pending':
        return AppColors.accentAmber;
      case 'vencida':
      case 'overdue':
      case 'vencido':
        return AppColors.accentRose;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'pagada':
      case 'paid':
      case 'pagado':
        return 'Pagada';
      case 'pendiente':
      case 'pending':
        return 'Pendiente';
      case 'vencida':
      case 'overdue':
      case 'vencido':
        return 'Vencida';
      default:
        return status ?? '-';
    }
  }
}

// ──────────────────────────────────────────────
// Cell for horizontal row
// ──────────────────────────────────────────────

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Summary row
// ──────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.isBold = false});

  final String label;
  final String value;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
