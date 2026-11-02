import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/sale_correction.dart';

typedef SaleCorrectionPreviewLoader =
    Future<SaleCorrectionPreview> Function({
      DateTime? saleDate,
      double? totalPrice,
      double? initialPaidAmount,
      int? installmentCount,
      double? monthlyInterestRate,
    });

typedef SaleCorrectionApplier =
    Future<Map<String, dynamic>> Function({
      required String reason,
      DateTime? saleDate,
      double? totalPrice,
      double? initialPaidAmount,
      int? installmentCount,
      double? monthlyInterestRate,
    });

/// FASE 03 — Diálogo único de corrección de venta (solo OWNER).
///
/// Muestra el impacto financiero antes de aplicar, exige motivo y bloquea la
/// confirmación cuando el backend no autoriza la operación (fail-closed).
class SaleCorrectionDialog extends StatefulWidget {
  const SaleCorrectionDialog({
    super.key,
    required this.action,
    required this.loadPreview,
    required this.apply,
    this.currentTotal,
    this.currentInitialPaid,
    this.currentInstallmentCount,
    this.currentInterestRate,
    this.saleLabel,
  });

  final String action;
  final SaleCorrectionPreviewLoader loadPreview;
  final SaleCorrectionApplier apply;
  final double? currentTotal;
  final double? currentInitialPaid;
  final int? currentInstallmentCount;
  final double? currentInterestRate;
  final String? saleLabel;

  @override
  State<SaleCorrectionDialog> createState() => _SaleCorrectionDialogState();
}

class _SaleCorrectionDialogState extends State<SaleCorrectionDialog> {
  final TextEditingController _reasonController = TextEditingController();
  late final TextEditingController _totalController;
  late final TextEditingController _initialController;
  late final TextEditingController _countController;
  late final TextEditingController _rateController;

  SaleCorrectionPreview? _preview;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  bool get _isFinancing =>
      widget.action == SaleCorrectionAction.updateFinancing;

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(
      text: widget.currentTotal?.toStringAsFixed(2) ?? '',
    );
    _initialController = TextEditingController(
      text: widget.currentInitialPaid?.toStringAsFixed(2) ?? '',
    );
    _countController = TextEditingController(
      text: widget.currentInstallmentCount?.toString() ?? '',
    );
    _rateController = TextEditingController(
      text: widget.currentInterestRate?.toStringAsFixed(2) ?? '0',
    );
    _reload();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _totalController.dispose();
    _initialController.dispose();
    _countController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController controller) {
    final text = controller.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final preview = await widget.loadPreview(
      totalPrice: _isFinancing ? _parse(_totalController) : null,
      initialPaidAmount: _isFinancing ? _parse(_initialController) : null,
      installmentCount: _isFinancing ? int.tryParse(_countController.text) : null,
      monthlyInterestRate: _isFinancing ? _parse(_rateController) : null,
    );
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
      await widget.apply(
        reason: reason,
        totalPrice: _isFinancing ? _parse(_totalController) : null,
        initialPaidAmount: _isFinancing ? _parse(_initialController) : null,
        installmentCount: _isFinancing ? int.tryParse(_countController.text) : null,
        monthlyInterestRate: _isFinancing ? _parse(_rateController) : null,
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

  Widget _impactPanel(SaleCorrectionPreview preview) {
    final impact = preview.impact;
    String money(double value) => 'RD\$ ${formatRdCurrency(value)}';
    return Container(
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
            strong: true,
          ),
          _row('Precio', '${money(impact.totalBefore)} → ${money(impact.totalAfter)}'),
          _row(
            'Inicial pagada',
            '${money(impact.initialPaidBefore)} → ${money(impact.initialPaidAfter)}',
          ),
          _row(
            'Financiado',
            '${money(impact.financedBefore)} → ${money(impact.financedAfter)}',
            strong: true,
          ),
          _row(
            'Saldo',
            '${money(impact.balanceBefore)} → ${money(impact.balanceAfter)}',
          ),
          _row(
            'Cuotas',
            '${impact.installmentCountBefore} → ${impact.installmentCountAfter}',
          ),
          if (impact.activePayments > 0)
            _row('Pagos activos', '${impact.activePayments}'),
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

    return AlertDialog(
      title: Text(
        SaleCorrectionAction.label(widget.action),
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.saleLabel != null)
                Text(
                  widget.saleLabel!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
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
              else if (preview != null) ...[
                _impactPanel(preview),
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
                    preview.message.isEmpty
                        ? (preview.allowed
                              ? 'Corrección permitida.'
                              : 'El servidor no autoriza esta corrección.')
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
              if (_isFinancing) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _totalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'Precio',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _initialController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'Inicial pagada',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _countController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'N. cuotas',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'Interés mensual %',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting ? null : _reload,
                    child: const Text(
                      'Calcular impacto',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                maxLength: 200,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Motivo de la corrección',
                  hintText: 'Ej.: reestructuración acordada con el cliente',
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
              : Text(SaleCorrectionAction.label(widget.action)),
        ),
      ],
    );
  }
}
