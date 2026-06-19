import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../core/utils.dart';
import '../../widgets/detail_page.dart';
import 'sale_installments_page.dart';
import 'sale_payments_page.dart';

class SaleDetailPage extends StatelessWidget {
  const SaleDetailPage({
    super.key,
    required this.sale,
    this.allInstallments = const [],
    this.allPayments = const [],
    this.allClients = const [],
    this.allSellers = const [],
  });

  final Map<String, dynamic> sale;
  final List<Map<String, dynamic>> allInstallments;
  final List<Map<String, dynamic>> allPayments;
  final List<Map<String, dynamic>> allClients;
  final List<Map<String, dynamic>> allSellers;

  String? get _syncId => _read('syncId', 'saleSyncId');
  String? get _saleId => _read('saleId', 'id', 'localId');

  String? _read(
    String key1, [
    String? key2,
    String? key3,
    String? key4,
  ]) {
    final keys = [key1, key2, key3, key4].whereType<String>();

    for (final key in keys) {
      final value = sale[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return null;
  }

  String _label(
    String key1, {
    String? key2,
    String? key3,
    String fallback = '-',
  }) {
    return text(_read(key1, key2, key3), fallback);
  }

  String _amount(
    String key1, {
    String? key2,
    String? key3,
  }) {
    final value = _read(key1, key2, key3);
    if (value == null) return money(0);
    return money(value);
  }

  String _date(
    String key1, {
    String? key2,
  }) {
    final raw = _read(key1, key2);
    if (raw == null) return '-';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final year = parsed.year.toString();

    return '$day/$month/$year';
  }

  String get _client => _label(
        'client',
        key2: 'clientName',
        key3: 'customerName',
        fallback: 'Cliente',
      );

  String get _lot => _label(
        'lot',
        key2: 'lotName',
        key3: 'solar',
      );

  String get _cedula => _label(
        'cedula',
        key2: 'document',
        key3: 'clientDocument',
      );

  String get _status => _label(
        'status',
        fallback: 'Activa',
      );

  String get _seller => _label(
        'seller',
        key2: 'sellerName',
        key3: 'vendor',
      );

  String get _plan => _label(
        'plan',
        key2: 'paymentPlan',
        key3: 'installmentPlan',
      );

  String get _modality => _label(
        'modalidad',
        key2: 'modality',
        key3: 'saleType',
      );

  String get _meters => _label(
        'metros',
        key2: 'area',
        key3: 'meters',
      );

  String get _saleDate => _date(
        'saleDate',
        key2: 'date',
      );

  String get _total => _amount(
        'total',
        key2: 'price',
        key3: 'amount',
      );

  String get _initial => _amount(
        'initialPaid',
        key2: 'initial',
        key3: 'downPayment',
      );

  String get _balance => _amount(
        'balance',
        key2: 'pending',
        key3: 'remaining',
      );

  String get _monthlyPayment => _amount(
        'monthlyPayment',
        key2: 'installmentAmount',
        key3: 'cuota',
      );

  List<String> get _relationIds {
    return [
      _syncId,
      _saleId,
      _read('id'),
      _read('localId'),
    ].whereType<String>().where((e) => e.trim().isNotEmpty).toSet().toList();
  }

  List<Map<String, dynamic>> get _relatedInstallments {
    final ids = _relationIds;
    if (ids.isEmpty || allInstallments.isEmpty) return [];

    return allInstallments.where((item) {
      return ids.any((id) {
        return item['saleId']?.toString() == id ||
            item['saleSyncId']?.toString() == id ||
            item['saleLocalId']?.toString() == id ||
            item['syncId']?.toString() == id;
      });
    }).toList();
  }

  List<Map<String, dynamic>> get _relatedPayments {
    final ids = _relationIds;
    if (ids.isEmpty || allPayments.isEmpty) return [];

    return allPayments.where((item) {
      return ids.any((id) {
        return item['saleId']?.toString() == id ||
            item['saleSyncId']?.toString() == id ||
            item['saleLocalId']?.toString() == id ||
            item['syncId']?.toString() == id;
      });
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
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
        return AppColors.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
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
        return status;
    }
  }

  void _openInstallments(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleInstallmentsPage(
          sale: sale,
          installments: _relatedInstallments,
        ),
      ),
    );
  }

  void _openPayments(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalePaymentsPage(
          sale: sale,
          payments: _relatedPayments,
        ),
      ),
    );
  }

  Map<String, dynamic>? get _foundClient {
    final clientSyncId = sale['clientSyncId']?.toString();
    if (clientSyncId == null || allClients.isEmpty) return null;
    return allClients.cast<Map<String, dynamic>?>().firstWhere(
      (c) => c?['syncId']?.toString() == clientSyncId,
      orElse: () => null,
    );
  }

  Map<String, dynamic>? get _foundSeller {
    final sellerSyncId = sale['sellerSyncId']?.toString();
    if (sellerSyncId == null || allSellers.isEmpty) return null;
    return allSellers.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s?['syncId']?.toString() == sellerSyncId,
      orElse: () => null,
    );
  }

  void _openClientDetail(BuildContext context) {
    final clientData = _foundClient;
    if (clientData == null) return;
    final view = RecordBuilders.client(clientData);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(view: view, title: 'Cliente'),
      ),
    );
  }

  void _openSellerDetail(BuildContext context) {
    final sellerData = _foundSeller;
    if (sellerData == null) return;
    final view = RecordBuilders.seller(sellerData);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(view: view, title: 'Vendedor'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(_status);
    final installments = _relatedInstallments;
    final payments = _relatedPayments;
    final hasClient = _foundClient != null;
    final hasSeller = _foundSeller != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Detalle de venta',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.border,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _TopIdentity(
              client: _client,
              lot: _lot,
              cedula: _cedula,
              status: _statusLabel(_status),
              statusColor: statusColor,
              onClientTap: hasClient ? () => _openClientDetail(context) : null,
            ),
            const SizedBox(height: 14),
            _ActionRow(
              installmentsCount: installments.length,
              paymentsCount: payments.length,
              onInstallments: () => _openInstallments(context),
              onPayments: () => _openPayments(context),
            ),
            const SizedBox(height: 18),
            _SectionBlock(
              title: 'Resumen financiero',
              icon: Icons.payments_outlined,
              rows: [
                _DetailRow(
                  label: 'Precio total',
                  value: _total,
                  valueColor: AppColors.accentBlue,
                  strong: true,
                ),
                _DetailRow(
                  label: 'Inicial pagada',
                  value: _initial,
                  valueColor: AppColors.accentGreen,
                  strong: true,
                ),
                _DetailRow(
                  label: 'Saldo pendiente',
                  value: _balance,
                  valueColor: AppColors.accentAmber,
                  strong: true,
                ),
                if (_monthlyPayment != money(0))
                  _DetailRow(
                    label: 'Cuota mensual',
                    value: _monthlyPayment,
                    valueColor: AppColors.primary,
                    strong: true,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionBlock(
              title: 'Datos de la operación',
              icon: Icons.receipt_long_outlined,
              rows: [
                _DetailRow(label: 'Fecha', value: _saleDate),
                if (_seller != '-')
                  _TappableDetailRow(
                    label: 'Vendedor',
                    value: _seller,
                    onTap: hasSeller ? () => _openSellerDetail(context) : null,
                  ),
                if (_plan != '-') _DetailRow(label: 'Plan', value: _plan),
                if (_modality != '-')
                  _DetailRow(label: 'Modalidad', value: _modality),
                if (_meters != '-') _DetailRow(label: 'Metros', value: _meters),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopIdentity extends StatelessWidget {
  const _TopIdentity({
    required this.client,
    required this.lot,
    required this.cedula,
    required this.status,
    required this.statusColor,
    this.onClientTap,
  });

  final String client;
  final String lot;
  final String cedula;
  final String status;
  final Color statusColor;
  final VoidCallback? onClientTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onClientTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              client,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: onClientTap != null ? AppColors.primary : AppColors.textPrimary,
                                fontSize: 18,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                                decoration: onClientTap != null ? TextDecoration.underline : null,
                                decorationColor: AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                          ),
                          if (onClientTap != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                              color: AppColors.primary.withOpacity(0.6),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _TinyMeta(
                      icon: Icons.location_on_outlined,
                      value: lot,
                    ),
                    if (cedula != '-')
                      _TinyMeta(
                        icon: Icons.badge_outlined,
                        value: cedula,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusChip(label: status, color: statusColor),
        ],
      ),
    );
  }
}

class _TinyMeta extends StatelessWidget {
  const _TinyMeta({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.installmentsCount,
    required this.paymentsCount,
    required this.onInstallments,
    required this.onPayments,
  });

  final int installmentsCount;
  final int paymentsCount;
  final VoidCallback onInstallments;
  final VoidCallback onPayments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            title: 'Cuotas',
            subtitle: '$installmentsCount registro${installmentsCount == 1 ? '' : 's'}',
            icon: Icons.calendar_month_rounded,
            color: AppColors.accentBlue,
            onTap: onInstallments,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            title: 'Pagos',
            subtitle: '$paymentsCount registro${paymentsCount == 1 ? '' : 's'}',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.accentGreen,
            onTap: onPayments,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.70),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: color.withOpacity(0.50),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.where((row) => row is! SizedBox).toList();

    if (visibleRows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title, icon: icon),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Column(
              children: [
                for (int i = 0; i < visibleRows.length; i++) ...[
                  visibleRows[i],
                  if (i != visibleRows.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.strong = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 13.2,
                height: 1.28,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TappableDetailRow extends StatelessWidget {
  const _TappableDetailRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onTap != null ? AppColors.primary : AppColors.textPrimary,
                            fontSize: 13.2,
                            height: 1.28,
                            fontWeight: FontWeight.w800,
                            decoration: onTap != null ? TextDecoration.underline : null,
                            decorationColor: AppColors.primary.withOpacity(0.3),
                          ),
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: AppColors.primary.withOpacity(0.6),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
