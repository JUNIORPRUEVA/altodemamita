import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/authoritative_late_fee.dart';

/// Dialogo de condonacion de mora (solo OWNER).
///
/// Muestra el IMPACTO FINANCIERO antes de confirmar y exige un motivo: el
/// backend rechaza la operacion sin motivo (`WAIVER_REASON_REQUIRED`) y
/// recalcula el monto el mismo, por lo que aqui solo se presenta la cifra
/// autoritativa que se va a condonar.
class LateFeeWaiverDialog extends StatefulWidget {
  const LateFeeWaiverDialog({
    super.key,
    required this.clientName,
    required this.saleLabel,
    required this.summary,
  });

  final String clientName;
  final String saleLabel;
  final AuthoritativeLateFeeSummary summary;

  @override
  State<LateFeeWaiverDialog> createState() => _LateFeeWaiverDialogState();
}

class _LateFeeWaiverDialogState extends State<LateFeeWaiverDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  String? _error;
  bool _partial = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String get _reason => _reasonController.text.trim();

  double get _outstanding => widget.summary.outstandingLateFees;

  /// Monto efectivo a condonar segun el modo elegido.
  double? get _requestedAmount {
    if (!_partial) return null;
    final parsed = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0) return null;
    return parsed > _outstanding ? _outstanding : parsed;
  }

  double get _waivedPreview => _requestedAmount ?? _outstanding;

  double get _outstandingAfter =>
      _outstanding - _waivedPreview < 0 ? 0 : _outstanding - _waivedPreview;

  bool get _canConfirm =>
      _reason.length >= 5 && (!_partial || _requestedAmount != null);

  void _confirm() {
    if (!_canConfirm) {
      setState(
        () => _error = _partial
            ? 'Indica un monto a condonar mayor que cero.'
            : 'Indica el motivo de la condonacion (min. 5 caracteres).',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop((reason: _reason, waivedAmount: _requestedAmount));
  }

  Widget _impactRow(String label, double amount, {bool emphasized = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF334155),
              ),
            ),
          ),
          Text(
            'RD\$ ${formatRdCurrency(amount)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              color: emphasized
                  ? const Color(0xFF9A3412)
                  : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return AlertDialog(
      title: const Text('Condonar mora', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.clientName} — ${widget.saleLabel}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _impactRow('Mora acumulada (bruta)', summary.grossLateFees),
                    _impactRow('Mora ya cobrada', summary.collectedLateFees),
                    _impactRow(
                      'Mora condonada vigente',
                      summary.waivedLateFees,
                    ),
                    const Divider(height: 12),
                    _impactRow(
                      'Mora exigible actual',
                      summary.outstandingLateFees,
                      emphasized: true,
                    ),
                    if (_partial) ...[
                      _impactRow('Se condonara (parcial)', _waivedPreview),
                      _impactRow(
                        'Exigible despues de condonar',
                        _outstandingAfter,
                        emphasized: true,
                      ),
                    ] else
                      _impactRow('Exigible despues de condonar', 0),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _partial,
                    onChanged: (value) => setState(() {
                      _partial = value ?? false;
                      _error = null;
                    }),
                  ),
                  const Expanded(
                    child: Text(
                      'Condonar solo una parte de la mora',
                      style: TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
              if (_partial) ...[
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Monto a condonar',
                    helperText:
                        'Maximo RD\$ ${formatRdCurrency(summary.outstandingLateFees)}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _partial
                    ? 'Se condonara el monto indicado al confirmar. La mora restante '
                          'sigue exigible y la que se genere despues se acumula.'
                    : 'Se condonara la mora exigible al momento de confirmar '
                          '(RD\$ ${formatRdCurrency(summary.outstandingLateFees)}). '
                          'La mora que se genere despues seguira acumulandose.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLength: 200,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Motivo de la condonacion',
                  hintText: 'Ej.: acuerdo comercial con el cliente',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  } else {
                    setState(() {});
                  }
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canConfirm ? _confirm : null,
          child: const Text('Condonar mora'),
        ),
      ],
    );
  }
}
