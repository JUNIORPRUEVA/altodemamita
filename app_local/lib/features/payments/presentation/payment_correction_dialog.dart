import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/payment_correction.dart';

/// Carga la previsualizacion autoritativa con los parametros elegidos.
typedef CorrectionPreviewLoader =
    Future<PaymentCorrectionPreview> Function({
      DateTime? newDate,
      double? newAmount,
    });

/// Aplica la correccion en el backend.
typedef CorrectionApplier =
    Future<Map<String, dynamic>> Function({
      required String reason,
      DateTime? newDate,
      double? newAmount,
    });

/// FASE 01C — Dialogo unico de correccion de un pago historico.
///
/// Reglas de seguridad que este dialogo RESPETA (no las decide):
/// - Solo se muestra cuando el usuario es administrador.
/// - El backend es la autoridad: si la previsualizacion devuelve
///   `allowed: false`, el boton de confirmar queda deshabilitado y se muestra
///   el motivo exacto devuelto por el servidor.
/// - El motivo es obligatorio.
/// - El monto/fecha solo se envian si la accion los requiere.
class PaymentCorrectionDialog extends StatefulWidget {
  const PaymentCorrectionDialog({
    super.key,
    required this.action,
    required this.clientName,
    required this.concept,
    required this.amountLabel,
    required this.paymentDateLabel,
    required this.loadPreview,
    required this.apply,
  });

  final String action;
  final String clientName;
  final String concept;
  final String amountLabel;
  final String paymentDateLabel;
  final CorrectionPreviewLoader loadPreview;
  final CorrectionApplier apply;

  @override
  State<PaymentCorrectionDialog> createState() =>
      _PaymentCorrectionDialogState();
}

class _PaymentCorrectionDialogState extends State<PaymentCorrectionDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  PaymentCorrectionPreview? _preview;
  bool _loadingPreview = true;
  bool _submitting = false;
  String? _error;
  DateTime? _newDate;
  double? _newAmount;

  /// Evita pedir la previsualizacion en cada tecla mientras se escribe el monto.
  Timer? _amountDebounce;

  bool get _isDateAction => widget.action == PaymentCorrectionAction.changeDate;
  bool get _isAmountAction =>
      widget.action == PaymentCorrectionAction.correctAmount;

  @override
  void initState() {
    super.initState();
    _reloadPreview();
  }

  @override
  void dispose() {
    _amountDebounce?.cancel();
    _reasonController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _reloadPreview() async {
    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    final preview = await widget.loadPreview(
      newDate: _newDate,
      newAmount: _newAmount,
    );
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loadingPreview = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Nueva fecha efectiva del pago',
    );
    if (picked == null) return;
    setState(() => _newDate = picked);
    await _reloadPreview();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(
        () => _error = 'Indica el motivo de la correccion (min. 5 caracteres).',
      );
      return;
    }
    if (_isDateAction && _newDate == null) {
      setState(() => _error = 'Selecciona la nueva fecha efectiva.');
      return;
    }
    if (_isAmountAction && _newAmount == null) {
      setState(() => _error = 'Indica el monto correcto.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.apply(
        reason: reason,
        newDate: _newDate,
        newAmount: _newAmount,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _row(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: strong ? const Color(0xFF9A3412) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _impactCard(PaymentCorrectionPreview preview) {
    final impact = preview.impact;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          if (_isDateAction) ...[
            _row('Fecha actual', widget.paymentDateLabel),
            _row(
              'Nueva fecha',
              _newDate == null
                  ? '(selecciona una fecha)'
                  : _formatDate(_newDate!),
              strong: true,
            ),
          ] else if (_isAmountAction) ...[
            _row('Monto actual', widget.amountLabel),
            _row(
              'Monto corregido',
              _newAmount == null
                  ? '(indica el monto)'
                  : 'RD\$ ${formatRdCurrency(_newAmount!)}',
              strong: true,
            ),
            _row(
              'Se registra un pago de reemplazo',
              'El pago original queda anulado',
            ),
          ] else ...[
            if (impact.paidAmountBefore > 0)
              _row(
                'Pagado en la cuota',
                'RD\$ ${formatRdCurrency(impact.paidAmountBefore)} → '
                    'RD\$ ${formatRdCurrency(impact.paidAmountAfter)}',
              ),
            _row(
              'Saldo de la venta',
              'RD\$ ${formatRdCurrency(impact.saleBalanceBefore)} → '
                  'RD\$ ${formatRdCurrency(impact.saleBalanceAfter)}',
              strong: true,
            ),
            _row(
              'Monto devuelto al saldo',
              'RD\$ ${formatRdCurrency(impact.amountRestoredToBalance)}',
            ),
          ],
          if (impact.lateFeeNote != null) ...[
            const SizedBox(height: 6),
            Text(
              impact.lateFeeNote!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final allowed = preview?.allowed ?? false;
    final canConfirm =
        allowed &&
        !_loadingPreview &&
        !_submitting &&
        _reasonController.text.trim().length >= 5;

    return AlertDialog(
      title: Text(
        PaymentCorrectionAction.label(widget.action),
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.clientName} — ${widget.concept}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              if (_loadingPreview)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (preview != null) ...[
                _impactCard(preview),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: preview.allowed
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: preview.allowed
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Text(
                    preview.allowed
                        ? (preview.message.isEmpty
                              ? 'Correccion permitida.'
                              : preview.message)
                        : (preview.message.isEmpty
                              ? 'El servidor no autoriza esta correccion.'
                              : preview.message),
                    style: TextStyle(
                      fontSize: 11,
                      color: preview.allowed
                          ? const Color(0xFF065F46)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
              if (_isDateAction) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickDate,
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(
                    _newDate == null
                        ? 'Seleccionar nueva fecha'
                        : 'Nueva fecha: ${_formatDate(_newDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (_isAmountAction) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Monto correcto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  // Sin esto el monto solo se registraba al pulsar Enter y el
                  // formulario seguia marcando "(indica el monto)" al escribir.
                  onChanged: (value) {
                    final parsed = double.tryParse(value.replaceAll(',', '.'));
                    setState(() => _newAmount = parsed);
                    _amountDebounce?.cancel();
                    _amountDebounce = Timer(
                      const Duration(milliseconds: 600),
                      _reloadPreview,
                    );
                  },
                  onSubmitted: (value) {
                    final parsed = double.tryParse(value.replaceAll(',', '.'));
                    if (parsed == null) return;
                    setState(() => _newAmount = parsed);
                    _reloadPreview();
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            final parsed = double.tryParse(
                              _amountController.text.replaceAll(',', '.'),
                            );
                            if (parsed == null) {
                              setState(() => _error = 'El monto no es valido.');
                              return;
                            }
                            setState(() => _newAmount = parsed);
                            _reloadPreview();
                          },
                    child: const Text(
                      'Calcular impacto',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _reasonController,
                maxLength: 200,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Motivo de la correccion',
                  hintText: 'Ej.: monto capturado por error',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() => _error = null);
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
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canConfirm ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(PaymentCorrectionAction.label(widget.action)),
        ),
      ],
    );
  }
}
