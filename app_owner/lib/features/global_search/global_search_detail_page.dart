import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/safe_area_padding.dart';
import '../../core/utils.dart';
import '../../widgets/detail_page.dart';
import 'global_search_models.dart';
import '../sales/sale_detail_page.dart';
import '../sales/sale_installments_page.dart';
import '../sales/sale_payments_page.dart';

class GlobalSearchDetailPage extends StatelessWidget {
  const GlobalSearchDetailPage({super.key, required this.result});

  final GlobalSearchResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalle global'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: safeScrollPadding(context),
        children: [
          _Header(result: result),
          const SizedBox(height: 14),
          _FinancialSummary(result: result),
          const SizedBox(height: 16),
          if (_alerts.isNotEmpty) _Alerts(alerts: _alerts),
          if (_alerts.isNotEmpty) const SizedBox(height: 16),
          _InfoSection(
            title: 'Resumen del cliente',
            icon: Icons.person_outline_rounded,
            onTap: result.client == null ? null : () => _openClient(context),
            rows: [
              _row('Teléfono', _client('phone', 'No registrado')),
              _row('Cédula', _client('document', 'No registrado')),
              _row('Dirección', _client('address', 'No registrado')),
              _row('Actualizado', dateText(result.client?['updatedAt'])),
            ],
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Datos del solar',
            icon: Icons.map_outlined,
            onTap: result.lot == null ? null : () => _openLot(context),
            rows: [
              _row('Manzana', _lot('block', 'No disponible')),
              _row('Estado', _lot('status', 'No disponible')),
              _row('Área', money(result.lot?['area'])),
              _row('Precio/m2', money(result.lot?['price'])),
            ],
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Datos de la venta',
            icon: Icons.receipt_long_outlined,
            onTap: result.sale == null ? null : () => _openSale(context),
            rows: [
              _row('Fecha', dateText(result.sale?['saleDate'])),
              _row('Referencia', _sale('syncId', 'No disponible')),
            ],
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Datos del vendedor',
            icon: Icons.badge_outlined,
            onTap: result.seller == null ? null : () => _openSeller(context),
            rows: [
              _row('Nombre', result.displaySeller),
              _row('Teléfono', _seller('phone', 'No registrado')),
              _row('Cédula', _seller('document', 'No registrado')),
            ],
          ),
          const SizedBox(height: 16),
          _PaymentsSection(
            payments: result.payments,
            onOpen: result.sale == null ? null : () => _openPayments(context),
          ),
          const SizedBox(height: 16),
          _InstallmentsSection(
            installments: result.installments,
            onOpen: result.sale == null
                ? null
                : () => _openInstallments(context),
          ),
        ],
      ),
    );
  }

  List<String> get _alerts {
    final alerts = <String>[];
    if (result.overdueInstallments > 0) {
      alerts.add(
        'Tiene ${result.overdueInstallments} cuota${result.overdueInstallments == 1 ? '' : 's'} atrasada${result.overdueInstallments == 1 ? '' : 's'}.',
      );
    }
    if (result.totalPending > 0) {
      alerts.add('Balance pendiente: ${money(result.totalPending)}.');
    }
    if (result.payments.isEmpty) {
      alerts.add('No hay pagos registrados para esta relación.');
    }
    final lotStatus = result.lot?['status']?.toString().toLowerCase() ?? '';
    if (lotStatus.contains('cancel') ||
        lotStatus.contains('reserv') ||
        lotStatus.contains('apart')) {
      alerts.add(
        'El solar tiene estado especial: ${_lot('status', 'No disponible')}.',
      );
    }
    return alerts;
  }

  RecordField _row(String label, String value) => RecordField(label, value);

  String _client(String key, String fallback) {
    return _text(result.client?[key], fallback);
  }

  String _lot(String key, String fallback) {
    return _text(result.lot?[key], fallback);
  }

  String _sale(String key, String fallback) {
    return _text(result.sale?[key], fallback);
  }

  String _seller(String key, String fallback) {
    return _text(result.seller?[key], fallback);
  }

  void _openClient(BuildContext context) {
    final client = result.client;
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DetailPage(view: RecordBuilders.client(client), title: 'Cliente'),
      ),
    );
  }

  void _openLot(BuildContext context) {
    final lot = result.lot;
    if (lot == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DetailPage(view: RecordBuilders.lot(lot), title: 'Solar'),
      ),
    );
  }

  void _openSeller(BuildContext context) {
    final seller = result.seller;
    if (seller == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DetailPage(view: RecordBuilders.seller(seller), title: 'Vendedor'),
      ),
    );
  }

  void _openSale(BuildContext context) {
    final sale = result.sale;
    if (sale == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailPage(
          sale: sale,
          allInstallments: result.installments,
          allPayments: result.payments,
          allClients: [if (result.client != null) result.client!],
          allSellers: [if (result.seller != null) result.seller!],
          allLots: [if (result.lot != null) result.lot!],
        ),
      ),
    );
  }

  void _openPayments(BuildContext context) {
    final sale = result.sale;
    if (sale == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalePaymentsPage(sale: sale, payments: result.payments),
      ),
    );
  }

  void _openInstallments(BuildContext context) {
    final sale = result.sale;
    if (sale == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SaleInstallmentsPage(sale: sale, installments: result.installments),
      ),
    );
  }

  String _text(Object? value, String fallback) {
    final clean = value?.toString().trim() ?? '';
    return clean.isEmpty || clean == '-' ? fallback : clean;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.result});

  final GlobalSearchResult result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.manage_search_rounded,
            color: AppColors.primary,
            size: 25,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.displayClient,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                result.displayLot,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _StatusPill(label: result.status),
      ],
    );
  }
}

class _FinancialSummary extends StatelessWidget {
  const _FinancialSummary({required this.result});

  final GlobalSearchResult result;

  @override
  Widget build(BuildContext context) {
    final nextDate = result.nextPaymentDate == null
        ? 'No disponible'
        : dateText(result.nextPaymentDate!.toIso8601String());
    final items = [
      _Metric('Vendido', money(result.sale?['total']), AppColors.primary),
      _Metric('Pagado', money(result.totalPaid), AppColors.accentGreen),
      _Metric('Pendiente', money(result.totalPending), AppColors.accentAmber),
      _Metric('Atraso', money(result.totalOverdue), AppColors.accentRose),
      _Metric(
        'Cuotas atrasadas',
        result.overdueInstallments.toString(),
        AppColors.accentRose,
      ),
      _Metric('Próximo pago', nextDate, AppColors.textSecondary),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => SizedBox(
              width: (MediaQuery.sizeOf(context).width - 42) / 2,
              child: _MetricCard(metric: item),
            ),
          )
          .toList(),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: metric.color,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.rows,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final List<RecordField> rows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      icon: icon,
      onTap: onTap,
      child: Column(
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        row.label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({required this.payments, this.onOpen});

  final List<Map<String, dynamic>> payments;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Pagos realizados',
      icon: Icons.payments_outlined,
      onTap: onOpen,
      child: payments.isEmpty
          ? const _MutedText('No hay pagos registrados.')
          : Column(
              children: payments.map((payment) {
                return _CompactRow(
                  title: money(payment['amount']),
                  subtitle:
                      '${dateText(payment['paidAt'])} · ${_text(payment['method'], 'Método no registrado')}',
                  trailing: _text(payment['reference'], ''),
                );
              }).toList(),
            ),
    );
  }
}

class _InstallmentsSection extends StatelessWidget {
  const _InstallmentsSection({required this.installments, this.onOpen});

  final List<Map<String, dynamic>> installments;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Cuotas / plan de pago',
      icon: Icons.event_note_outlined,
      onTap: onOpen,
      child: installments.isEmpty
          ? const _MutedText('No hay cuotas registradas.')
          : Column(
              children: installments.map((installment) {
                final number = _text(installment['installmentNumber'], '-');
                final isOverdue = _isOverdueInstallment(installment);
                final status = isOverdue
                    ? 'Vencida'
                    : _installmentStatusLabel(installment['status']);
                return _CompactRow(
                  title: 'Cuota $number · ${money(installment['totalAmount'])}',
                  subtitle: 'Vence ${dateText(installment['dueDate'])}',
                  trailing: status,
                  titleColor: isOverdue
                      ? AppColors.accentRose
                      : AppColors.textPrimary,
                  trailingColor: isOverdue
                      ? AppColors.accentRose
                      : AppColors.primary,
                );
              }).toList(),
            ),
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.alerts});

  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accentAmber.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        children: alerts
            .map(
              (alert) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.accentAmber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alert,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.primary,
                  size: 15,
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: content,
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.titleColor = AppColors.textPrimary,
    this.trailingColor = AppColors.primary,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color titleColor;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (trailing.trim().isNotEmpty)
            Text(
              trailing,
              style: TextStyle(
                color: trailingColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

bool _isOverdueInstallment(Map<String, dynamic> installment) {
  final status = installment['status']?.toString().toLowerCase() ?? '';
  final isPaid = status.contains('pag') || status.contains('paid');
  if (status.contains('venc') || status.contains('overdue')) return true;
  final dueDate = DateTime.tryParse(installment['dueDate']?.toString() ?? '');
  if (dueDate == null || isPaid) return false;
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  return dueDate.isBefore(todayOnly);
}

String _installmentStatusLabel(Object? status) {
  switch (status?.toString().toLowerCase()) {
    case 'pagada':
    case 'pagado':
    case 'paid':
      return 'Pagada';
    case 'pendiente':
    case 'pending':
      return 'Pendiente';
    case 'vencida':
    case 'vencido':
    case 'overdue':
      return 'Vencida';
    default:
      return _text(status, 'No disponible');
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _text(Object? value, String fallback) {
  final clean = value?.toString().trim() ?? '';
  return clean.isEmpty || clean == '-' ? fallback : clean;
}
