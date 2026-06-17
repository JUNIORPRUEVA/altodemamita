import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/safe_area_padding.dart';
import '../../core/utils.dart';

class SalePaymentsPage extends StatelessWidget {
  const SalePaymentsPage({
    super.key,
    required this.sale,
    required this.payments,
  });

  final Map<String, dynamic> sale;
  final List<Map<String, dynamic>> payments;

  @override
  Widget build(BuildContext context) {
    final client = text(sale['client'], 'Cliente');
    final lot = text(sale['lot'], '-');

    // Calculate totals
    double totalPaid = 0;
    for (final pay in payments) {
      totalPaid +=
          num.tryParse(pay['amount']?.toString() ?? '0')?.toDouble() ?? 0;
    }
    final balance =
        num.tryParse(sale['balance']?.toString() ?? '0')?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Historial de pagos',
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
        child: payments.isEmpty
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
                  // Payments vertical list
                  Expanded(
                    child: ListView.builder(
                      padding: safeScrollPadding(context, top: 8),
                      itemCount: payments.length,
                      itemBuilder: (context, index) {
                        return _PaymentRow(payment: payments[index]);
                      },
                    ),
                  ),
                  // Summary footer
                  _buildSummary(totalPaid, balance),
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
              Icons.payments_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se encontraron pagos\nrelacionados con esta venta.',
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

  Widget _buildSummary(double totalPaid, double balance) {
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
          _PaymentSummaryRow('Total pagado', money(totalPaid)),
          _PaymentSummaryRow(
            'Restante por pagar',
            money(balance),
            isBold: true,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Payment row (vertical list, horizontal scroll inside)
// ──────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final date = dateText(payment['paidAt']);
    final amount = money(payment['amount']);
    final method = text(payment['method'], '-');
    final reference = text(payment['reference'], '-');
    final concept = text(payment['paymentType'], 'Pago');
    final lot = text(payment['lot'], '-');
    final saleRef = text(payment['sale'], '-');

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
              // Icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 14,
                  color: AppColors.accentGreen,
                ),
              ),
              const SizedBox(width: 8),
              // Concept + date
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    concept,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Amount
              _PCell(label: 'Monto', value: amount),
              const SizedBox(width: 12),
              // Method
              _PCell(label: 'Método', value: method),
              const SizedBox(width: 12),
              // Reference
              if (reference != '-') ...[
                _PCell(label: 'Ref.', value: reference),
                const SizedBox(width: 12),
              ],
              // Lot
              if (lot != '-') ...[
                _PCell(label: 'Solar', value: lot),
                const SizedBox(width: 12),
              ],
              // Sale
              if (saleRef != '-') ...[_PCell(label: 'Venta', value: saleRef)],
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Cell for horizontal payment row
// ──────────────────────────────────────────────

class _PCell extends StatelessWidget {
  const _PCell({required this.label, required this.value});

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

class _PaymentSummaryRow extends StatelessWidget {
  const _PaymentSummaryRow(this.label, this.value, {this.isBold = false});

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
