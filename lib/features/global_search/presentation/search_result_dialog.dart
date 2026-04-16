import 'package:flutter/material.dart';

import '../domain/search_result.dart';

class SearchResultDialog extends StatelessWidget {
  const SearchResultDialog({
    super.key,
    required this.result,
    this.onOpenClients,
    this.onOpenLots,
    this.onOpenSales,
    this.onOpenInstallments,
    this.onOpenPayments,
  });

  final GlobalSearchResult result;
  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenLots;
  final VoidCallback? onOpenSales;
  final void Function(int? saleId)? onOpenInstallments;
  final void Function(int? saleId)? onOpenPayments;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
              // Encabezado con nombre/código
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.displayName,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.displaySubtitle,
                          style: Theme.of(context).textTheme.labelMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Revisa coincidencias y navega directamente al módulo relacionado.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),

              // Información del cliente
              if (result.client != null) ...[
                _buildSectionTitle(context, 'Información del cliente'),
                const SizedBox(height: 12),
                _buildClientInfo(context, result.client!),
                const SizedBox(height: 24),
              ],

              // Información del solar
              if (result.lot != null) ...[
                _buildSectionTitle(context, 'Información del solar'),
                const SizedBox(height: 12),
                _buildLotInfo(context, result.lot!),
                const SizedBox(height: 24),
              ],

              // Ventas relacionadas
              if (result.relatedSales.isNotEmpty) ...[
                _buildSectionTitle(context, 'Ventas (${result.relatedSales.length})'),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: result.relatedSales.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final sale = result.relatedSales[index];
                    return _buildSaleInfo(context, sale);
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Cuotas pendientes
              if (result.relatedInstallments.isNotEmpty) ...[
                _buildSectionTitle(
                  context,
                  'Cuotas pendientes (${result.pendingInstallmentsCount})',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monto total pendiente: RD\$${result.totalPendingAmount.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${result.pendingInstallmentsCount} de ${result.relatedInstallments.length} cuotas pendientes',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: result.relatedInstallments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final installment = result.relatedInstallments[index];
                    return _buildInstallmentInfo(context, installment);
                  },
                ),
              ] else if (result.relatedInstallments.isEmpty && result.relatedSales.isNotEmpty)
                Text(
                  'No hay cuotas registradas',
                  style: Theme.of(context).textTheme.labelMedium,
                ),

              // Historial de pagos
              if (result.relatedPayments.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSectionTitle(
                  context,
                  'Historial de pagos (${result.relatedPayments.length})',
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: result.relatedPayments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _buildPaymentInfo(
                      context,
                      result.relatedPayments[index],
                    );
                  },
                ),
              ],

              const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildClientInfo(BuildContext context, client) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              context,
              'Nombre',
              client.fullName,
              onNavigate: onOpenClients,
              tooltip: 'Ir a Clientes',
            ),
            _buildDetailRow(
              context,
              'Cédula',
              client.documentId,
              onNavigate: onOpenClients,
              tooltip: 'Ir a Clientes',
            ),
            if (client.phone?.isNotEmpty ?? false)
              _buildDetailRow(
                context,
                'Teléfono',
                client.phone!,
                onNavigate: onOpenClients,
                tooltip: 'Ir a Clientes',
              ),
            if (client.address?.isNotEmpty ?? false)
              _buildDetailRow(
                context,
                'Dirección',
                client.address!,
                onNavigate: onOpenClients,
                tooltip: 'Ir a Clientes',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLotInfo(BuildContext context, lot) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              context,
              'Código',
              lot.displayCode,
              onNavigate: onOpenLots,
              tooltip: 'Ir a Solares',
            ),
            _buildDetailRow(
              context,
              'Manzana',
              lot.blockNumber,
              onNavigate: onOpenLots,
              tooltip: 'Ir a Solares',
            ),
            _buildDetailRow(
              context,
              'Solar',
              lot.lotNumber,
              onNavigate: onOpenLots,
              tooltip: 'Ir a Solares',
            ),
            _buildDetailRow(context, 'Área', '${lot.area.toStringAsFixed(2)} m²'),
            _buildDetailRow(
              context,
              'Precio por metro',
              'RD\$${lot.pricePerSquareMeter.toStringAsFixed(2)} /m²',
            ),
            _buildDetailRow(
              context,
              'Precio total',
              'RD\$${lot.totalPrice.toStringAsFixed(2)}',
            ),
            _buildDetailRow(context, 'Estado', lot.status.toUpperCase()),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleInfo(BuildContext context, sale) {
    final sellerName = _readText(sale['vendedor_nombre']);
    final creatorUser = _readText(sale['usuario_nombre']);
    final lotCode = _buildLotCode(sale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Venta ID: ${sale['id']}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(sale['estado']),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                sale['estado'] ?? 'DESCONOCIDO',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildDetailRow(
          context,
          'Fecha y hora venta',
          _formatDateTime(sale['fecha_venta']),
          onNavigate: onOpenSales,
          tooltip: 'Ir a Ventas',
        ),
        _buildDetailRow(
          context,
          'Fecha y hora registro',
          _formatDateTime(sale['fecha_creacion']),
          onNavigate: onOpenSales,
          tooltip: 'Ir a Ventas',
        ),
        _buildDetailRow(
          context,
          'Usuario creador',
          creatorUser,
          onNavigate: onOpenSales,
          tooltip: 'Ir a Ventas',
        ),
        _buildDetailRow(
          context,
          'Vendedor',
          sellerName,
          onNavigate: onOpenSales,
          tooltip: 'Ir a Ventas',
        ),
        _buildDetailRow(
          context,
          'Solar',
          lotCode,
          onNavigate: onOpenLots,
          tooltip: 'Ir a Solares',
        ),
        _buildDetailRow(
          context,
          'Precio total venta',
          'RD\$${(sale['precio_venta'] ?? 0).toStringAsFixed(2)}',
        ),
        _buildDetailRow(
          context,
          'Inicial mínimo requerido',
          'RD\$${_toDouble(sale['monto_inicial_requerido']).toStringAsFixed(2)}',
        ),
        _buildDetailRow(
          context,
          'Inicial real pagado',
          'RD\$${_toDouble(sale['monto_inicial_pagado']).toStringAsFixed(2)}',
        ),
        _buildDetailRow(
          context,
          'Inicial pendiente',
          'RD\$${_toDouble(sale['monto_inicial_pendiente']).toStringAsFixed(2)}',
        ),
        _buildDetailRow(
          context,
          'Financiado',
          'RD\$${_toDouble(sale['saldo_financiado']).toStringAsFixed(2)}',
        ),
        _buildDetailRow(
          context,
          'Pendiente',
          'RD\$${_toDouble(sale['saldo_pendiente']).toStringAsFixed(2)}',
          onNavigate: () => onOpenPayments?.call(_saleIdFromMap(sale)),
          tooltip: 'Ir a Pagos/Préstamos',
        ),
        if (sale['monto_apartado_minimo'] != null)
          _buildDetailRow(
            context,
            'Apartado mínimo',
            'RD\$${_toDouble(sale['monto_apartado_minimo']).toStringAsFixed(2)}',
          ),
        if (sale['fecha_limite_inicial'] != null)
          _buildDetailRow(
            context,
            'Fecha límite inicial',
            _formatDate(sale['fecha_limite_inicial']),
          ),
        _buildDetailRow(
          context,
          'Cuotas',
          _readInstallmentsLabel(sale),
          onNavigate: () => onOpenInstallments?.call(_saleIdFromMap(sale)),
          tooltip: 'Ir a Cuotas',
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _buildQuickAction(
              context,
              icon: Icons.person_outline,
              label: 'Cliente',
              onTap: onOpenClients,
              tooltip: 'Ir a Clientes',
            ),
            _buildQuickAction(
              context,
              icon: Icons.point_of_sale_outlined,
              label: 'Ventas',
              onTap: onOpenSales,
              tooltip: 'Ir a Ventas',
            ),
            _buildQuickAction(
              context,
              icon: Icons.event_note_outlined,
              label: 'Cuotas',
              onTap: () => onOpenInstallments?.call(_saleIdFromMap(sale)),
              tooltip: 'Ir a Cuotas',
            ),
            _buildQuickAction(
              context,
              icon: Icons.payments_outlined,
              label: 'Préstamo',
              onTap: () => onOpenPayments?.call(_saleIdFromMap(sale)),
              tooltip: 'Ir a Pagos/Préstamos',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstallmentInfo(BuildContext context, installment) {
    final isOverdue = DateTime.now().isAfter(installment.dueDate);
    final color = _getInstallmentStatusColor(installment.calculatedStatus, isOverdue);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuota #${installment.installmentNumber}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(installment.dueDate)} • Total: RD\$${installment.totalAmount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Pendiente: RD\$${installment.remainingAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(BuildContext context, Map<String, dynamic> payment) {
    final tipo = payment['tipo_pago'] as String? ?? 'cuota';
    final monto = (payment['monto_pagado'] as num?)?.toDouble() ?? 0.0;
    final fecha = _formatDateTime(payment['fecha_pago']);
    final metodo = _readText(payment['metodo_pago']);
    final cuota = payment['numero_cuota'];
    final ano = payment['ano_a_pagar'];
    final ref = _readText(payment['referencia']);
    final label = switch (tipo) {
      'apartado' => 'Pago de apartado',
      'abono_inicial' => 'Abono a inicial',
      'abono_capital' => 'Abono a capital',
      _ => cuota != null ? 'Cuota #$cuota' : 'Pago',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$fecha • $metodo${ano != null ? " • Año: $ano" : ""}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  'Ref: $ref',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            'RD\$${monto.toStringAsFixed(2)}',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: Colors.green),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    VoidCallback? onNavigate,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
          if (onNavigate != null)
            Opacity(
              opacity: 0.58,
              child: IconButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onNavigate();
                },
                tooltip: tooltip,
                icon: const Icon(Icons.open_in_new_outlined, size: 15),
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 20, height: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 0.62,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton.icon(
          onPressed: onTap == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onTap();
                },
          icon: Icon(icon, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'activa':
        return Colors.blue;
      case 'apartado':
        return Colors.orange;
      case 'inicial_incompleto':
        return Colors.deepOrange;
      case 'pagada':
        return Colors.green;
      case 'cancelada':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getInstallmentStatusColor(String status, bool isOverdue) {
    if (isOverdue && status != 'pagada') return Colors.red;
    switch (status) {
      case 'pagada':
        return Colors.green;
      case 'parcial':
        return Colors.orange;
      case 'vencida':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    final dateTime = date is DateTime ? date : DateTime.tryParse(date.toString());
    if (dateTime == null) return 'N/A';
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
  }

  String _formatDateTime(dynamic date) {
    if (date == null) return 'N/A';
    final dateTime = date is DateTime ? date : DateTime.tryParse(date.toString());
    if (dateTime == null) return 'N/A';
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString().padLeft(4, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'No especificado' : text;
  }

  String _buildLotCode(Map<String, dynamic> sale) {
    final block = sale['manzana_numero']?.toString() ?? '';
    final lot = sale['solar_numero']?.toString() ?? '';
    if (block.isNotEmpty || lot.isNotEmpty) {
      return 'M$block-S$lot';
    }

    final lotId = sale['solar_id']?.toString() ?? '';
    return lotId.isEmpty ? 'No especificado' : 'Solar #$lotId';
  }

  int? _saleIdFromMap(Map<String, dynamic> sale) {
    final raw = sale['id'];
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '');
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _readInstallmentsLabel(Map<String, dynamic> sale) {
    final status = _readText(sale['estado']).toLowerCase();
    final count = sale['cantidad_cuotas']?.toString() ?? '0';
    if (status == 'apartado' || status == 'inicial_incompleto') {
      return '$count planificadas, aún sin activar';
    }
    return '$count mensuales';
  }
}
