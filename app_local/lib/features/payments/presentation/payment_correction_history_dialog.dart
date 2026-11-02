import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';

/// FASE 01D — Traza administrativa de un pago (SOLO LECTURA).
///
/// El backend entrega las entradas ya ordenadas cronologicamente. Este dialogo
/// no permite modificar nada: es evidencia para el OWNER.
class PaymentCorrectionHistoryDialog extends StatelessWidget {
  const PaymentCorrectionHistoryDialog({super.key, required this.data});

  final Map<String, dynamic> data;

  static String _kindLabel(String kind, String action) {
    switch (kind) {
      case 'created':
        return 'Alta del pago';
      case 'correction':
        return action == 'replacement'
            ? 'Pago de reemplazo registrado'
            : 'Correccion aplicada';
      case 'annulment':
        return 'Pago anulado';
      case 'authoritative_operation':
        return 'Operacion autoritativa';
      case 'replacement':
        return 'Pago de reemplazo';
      default:
        return kind.isEmpty ? 'Evento' : kind;
    }
  }

  String _formatDate(Object? raw) {
    final value = DateTime.tryParse((raw ?? '').toString());
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  Widget _entry(Map<String, dynamic> entry) {
    final kind = (entry['kind'] ?? '').toString();
    final action = (entry['action'] ?? '').toString();
    final reason = (entry['reason'] ?? '').toString().trim();
    final amount = entry['amount'];
    final performedBy = (entry['performedByUserId'] ?? '').toString().trim();
    final detail = (entry['detail'] ?? '').toString().trim();
    final before = entry['saleBalanceBefore'];
    final after = entry['saleBalanceAfter'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _kindLabel(kind, action),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                ),
              ),
              Text(
                _formatDate(entry['at']),
                style: const TextStyle(fontSize: 11, color: Color(0xFF7C89A3)),
              ),
            ],
          ),
          if (reason.isNotEmpty)
            Text(
              'Motivo: $reason',
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          if (amount != null)
            Text(
              'Monto: RD\$ ${formatRdCurrency((amount as num).toDouble())}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          if (before != null && after != null)
            Text(
              'Saldo de la venta: RD\$ ${formatRdCurrency((before as num).toDouble())}'
              ' → RD\$ ${formatRdCurrency((after as num).toDouble())}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          if (performedBy.isNotEmpty)
            Text(
              'Usuario: $performedBy',
              style: const TextStyle(fontSize: 11, color: Color(0xFF7C89A3)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payment = (data['payment'] as Map?) ?? const {};
    final rawHistory = data['history'];
    final history = rawHistory is List
        ? rawHistory
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];

    return AlertDialog(
      title: const Text('Auditoria del pago', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pago ${(payment['paymentType'] ?? '').toString()} — '
              'RD\$ ${formatRdCurrency(((payment['amount'] as num?) ?? 0).toDouble())}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 6),
            if (history.isEmpty)
              const Text(
                'Sin eventos registrados para este pago.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7C89A3)),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in history) ...[
                        _entry(entry),
                        const Divider(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
          ],
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
