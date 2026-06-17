import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../core/utils.dart';
import 'sale_installments_page.dart';
import 'sale_payments_page.dart';

class SaleDetailPage extends StatelessWidget {
  const SaleDetailPage({
    super.key,
    required this.sale,
    required this.allInstallments,
    required this.allPayments,
  });

  final Map<String, dynamic> sale;
  final List<Map<String, dynamic>> allInstallments;
  final List<Map<String, dynamic>> allPayments;

  String? get _syncId => sale['syncId']?.toString();
  String? get _saleId => sale['saleId']?.toString();
  String? get _id => sale['id']?.toString();
  String? get _localId => sale['localId']?.toString();

  /// Try to find related installments using syncId, saleId, or id
  List<Map<String, dynamic>> get _relatedInstallments {
    if (allInstallments.isEmpty) return [];
    final ids = [_syncId, _saleId, _id, _localId].whereType<String>().toSet();
    if (ids.isEmpty) return [];
    return allInstallments.where((inst) {
      return ids.any((id) =>
          inst['saleId']?.toString() == id ||
          inst['saleSyncId']?.toString() == id ||
          inst['syncId']?.toString() == id);
    }).toList();
  }

  /// Try to find related payments using syncId, saleId, or id
  List<Map<String, dynamic>> get _relatedPayments {
    if (allPayments.isEmpty) return [];
    final ids = [_syncId, _saleId, _id, _localId].whereType<String>().toSet();
    if (ids.isEmpty) return [];
    return allPayments.where((pay) {
      return ids.any((id) =>
          pay['saleId']?.toString() == id ||
          pay['saleSyncId']?.toString() == id ||
          pay['syncId']?.toString() == id);
    }).toList();
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'activa':
      case 'active':
        return AppColors.accentBlue;
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
      case 'activa':
      case 'active':
        return 'Activa';
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

  @override
  Widget build(BuildContext context) {
    final status = sale['status']?.toString();
    final statusColor = _statusColor(status);
    final client = text(sale['client'], 'Cliente');
    final lot = text(sale['lot'], '-');
    final balance = money(sale['balance']);
    final total = money(sale['total']);
    final initial = money(sale['initialPaid']);
    final date = dateText(sale['saleDate']);
    final cedula = text(sale['cedula'], '-');
    final seller = text(sale['seller'], '-');
    final plan = text(sale['plan'], '-');
    final modalidad = text(sale['modalidad'], '-');
    final metros = sale['metros']?.toString() ?? '-';
    final syncId = _syncId ?? '-';
    final localId = _localId ?? '-';

    final relatedInstallments = _relatedInstallments;
    final relatedPayments = _relatedPayments;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Detalle de venta',
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
      body: Column(
        children: [
          // ── Action buttons (fixed at top) ──
          _buildActionButtons(context, relatedInstallments, relatedPayments),
          // ── Scrollable content ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header compact card ──
                  _buildHeaderCard(client, status, statusColor, lot, balance),
                  const SizedBox(height: 12),

                  // ── Client & Lot section ──
                  _buildSectionCard('Cliente y Solar', [
                    _InfoRow('Cliente', client),
                    _InfoRow('Cédula', cedula),
                    _InfoRow('Solar', lot),
                    if (metros != '-') _InfoRow('Metros', metros),
                    if (modalidad != '-') _InfoRow('Modalidad', modalidad),
                  ]),
                  const SizedBox(height: 12),

                  // ── Sale info section ──
                  _buildSectionCard('Información de Venta', [
                    if (localId != '-') _InfoRow('Venta #', localId),
                    _InfoRow('Fecha', date),
                    _InfoRow('Estado', _statusLabel(status)),
                    if (seller != '-') _InfoRow('Vendedor', seller),
                    if (plan != '-') _InfoRow('Plan', plan),
                    if (syncId != '-')
                      _InfoRow('Sync ID', syncId, isMono: true),
                  ]),
                  const SizedBox(height: 12),

                  // ── Financial section ──
                  _buildSectionCard('Resumen Financiero', [
                    _InfoRow('Precio total', total),
                    _InfoRow('Inicial pagada', initial),
                    _InfoRow('Saldo pendiente', balance, isBold: true),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(
    String client,
    String? status,
    Color statusColor,
    String lot,
    String balance,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.description_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        client,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SaleDetailStatusChip(
                      label: _statusLabel(status),
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      lot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      balance,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    List<Map<String, dynamic>> installments,
    List<Map<String, dynamic>> payments,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Acciones',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.calendar_month_rounded,
                  label: 'Ver cuotas',
                  count: installments.length,
                  color: AppColors.accentBlue,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SaleInstallmentsPage(
                          sale: sale,
                          installments: installments,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Ver pagos',
                  count: payments.length,
                  color: AppColors.accentGreen,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SalePaymentsPage(
                          sale: sale,
                          payments: payments,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Info row widget
// ──────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.isBold = false, this.isMono = false});

  final String label;
  final String value;
  final bool isBold;
  final bool isMono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                fontFamily: isMono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Status chip for detail
// ──────────────────────────────────────────────

class _SaleDetailStatusChip extends StatelessWidget {
  const _SaleDetailStatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
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

// ──────────────────────────────────────────────
// Action button
// ──────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count ${count == 1 ? 'registro' : 'registros'}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
