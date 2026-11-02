import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/sale_correction.dart';

/// FASE 03B — Confirmación de cambio de cliente / solar con impacto real.
///
/// El impacto proviene del backend (preview por rollback transaccional). Si el
/// backend no autoriza la operación, la confirmación queda deshabilitada y se
/// muestra el motivo exacto. El motivo escrito es obligatorio.
class SaleAssociationConfirmDialog extends StatefulWidget {
  const SaleAssociationConfirmDialog({
    super.key,
    required this.title,
    required this.currentLabel,
    required this.targetLabel,
    required this.loadPreview,
    required this.apply,
  });

  final String title;
  final String currentLabel;
  final String targetLabel;
  final Future<SaleCorrectionPreview> Function() loadPreview;
  final Future<Map<String, dynamic>> Function(
    String reason,
    SaleCorrectionPreview preview,
  )
  apply;

  @override
  State<SaleAssociationConfirmDialog> createState() =>
      _SaleAssociationConfirmDialogState();
}

class _SaleAssociationConfirmDialogState
    extends State<SaleAssociationConfirmDialog> {
  final TextEditingController _reasonController = TextEditingController();
  SaleCorrectionPreview? _preview;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final preview = await widget.loadPreview();
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Indica el motivo (mín. 5 caracteres).');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.apply(reason, _preview!);
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: strong
                    ? const Color(0xFF9A3412)
                    : const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final allowed = preview?.allowed ?? false;
    final canSubmit =
        allowed &&
        !_loading &&
        !_submitting &&
        _reasonController.text.trim().length >= 5;
    final impact = preview?.impact;

    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row('Actual', widget.currentLabel),
              _row('Nuevo', widget.targetLabel, strong: true),
              const SizedBox(height: 8),
              if (_loading)
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
              else if (impact != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _row(
                        'Estado',
                        '${impact.statusBefore ?? '-'} → ${impact.statusAfter ?? '-'}',
                      ),
                      _row(
                        'Saldo',
                        'RD\$ ${formatRdCurrency(impact.balanceBefore)} → '
                            'RD\$ ${formatRdCurrency(impact.balanceAfter)}',
                      ),
                      _row(
                        'Cuotas activas',
                        '${impact.installmentCountBefore} → ${impact.installmentCountAfter}',
                      ),
                      if (impact.activePayments > 0)
                        _row(
                          'Pagos activos',
                          '${impact.activePayments} (bloquea importes y cliente)',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: preview!.allowed
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
                    preview.message.isEmpty
                        ? (preview.allowed
                              ? 'Cambio permitido.'
                              : 'El servidor no autoriza este cambio.')
                        : preview.message,
                    style: TextStyle(
                      fontSize: 11,
                      color: preview.allowed
                          ? const Color(0xFF065F46)
                          : const Color(0xFF991B1B),
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
                  labelText: 'Motivo del cambio',
                  hintText: 'Ej.: titular o solar mal capturado',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.title),
        ),
      ],
    );
  }
}
