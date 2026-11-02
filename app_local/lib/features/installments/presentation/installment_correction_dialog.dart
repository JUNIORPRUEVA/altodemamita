import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/installment_correction.dart';

/// Carga la previsualizacion autoritativa con los parametros elegidos.
typedef InstallmentPreviewLoader =
    Future<InstallmentCorrectionPreview> Function({
      DateTime? dueDate,
      double? principalAmount,
      double? interestAmount,
      int? installmentCount,
      DateTime? firstDueDate,
    });

/// Aplica la correccion en el backend.
typedef InstallmentCorrectionApplier =
    Future<Map<String, dynamic>> Function({
      required String reason,
      DateTime? dueDate,
      double? principalAmount,
      double? interestAmount,
      int? installmentCount,
      DateTime? firstDueDate,
    });

/// FASE 02 — Dialogo unico de correccion de cronograma (solo OWNER).
///
/// El backend es la autoridad: si la previsualizacion falla, la confirmacion
/// queda deshabilitada. El motivo es obligatorio y el impacto financiero se
/// muestra antes de aplicar.
class InstallmentCorrectionDialog extends StatefulWidget {
  const InstallmentCorrectionDialog({
    super.key,
    required this.action,
    required this.title,
    required this.loadPreview,
    required this.apply,
    this.installmentNumber,
    this.currentDueDate,
    this.currentPrincipal,
    this.currentInterest,
  });

  final String action;
  final String title;
  final InstallmentPreviewLoader loadPreview;
  final InstallmentCorrectionApplier apply;
  final int? installmentNumber;
  final DateTime? currentDueDate;
  final double? currentPrincipal;
  final double? currentInterest;

  @override
  State<InstallmentCorrectionDialog> createState() =>
      _InstallmentCorrectionDialogState();
}

class _InstallmentCorrectionDialogState
    extends State<InstallmentCorrectionDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _principalController = TextEditingController();
  final TextEditingController _interestController = TextEditingController();
  final TextEditingController _countController = TextEditingController();

  InstallmentCorrectionPreview? _preview;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  DateTime? _dueDate;
  DateTime? _firstDueDate;

  bool get _isDate => widget.action == InstallmentCorrectionAction.changeDueDate;
  bool get _isAmounts =>
      widget.action == InstallmentCorrectionAction.changeAmounts;
  bool get _isAdd => widget.action == InstallmentCorrectionAction.addInstallment;
  bool get _isReschedule =>
      widget.action == InstallmentCorrectionAction.reschedule;

  @override
  void initState() {
    super.initState();
    if (widget.currentPrincipal != null) {
      _principalController.text = widget.currentPrincipal!.toStringAsFixed(2);
    }
    if (widget.currentInterest != null) {
      _interestController.text = widget.currentInterest!.toStringAsFixed(2);
    }
    _countController.text = '12';
    _reload();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _principalController.dispose();
    _interestController.dispose();
    _countController.dispose();
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
      dueDate: _dueDate,
      principalAmount: _isAmounts || _isAdd ? _parse(_principalController) : null,
      interestAmount: _isAmounts ? _parse(_interestController) : null,
      installmentCount: _isReschedule ? int.tryParse(_countController.text) : null,
      firstDueDate: _firstDueDate,
    );
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loading = false;
    });
  }

  Future<void> _pickDate({required bool first}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (first ? _firstDueDate : _dueDate) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: first ? 'Primer vencimiento' : 'Nuevo vencimiento',
    );
    if (picked == null) return;
    setState(() {
      if (first) {
        _firstDueDate = picked;
      } else {
        _dueDate = picked;
      }
    });
    await _reload();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Indica el motivo de la correccion (min. 5 caracteres).');
      return;
    }
    if (_isDate && _dueDate == null) {
      setState(() => _error = 'Selecciona el nuevo vencimiento.');
      return;
    }
    if (_isReschedule && int.tryParse(_countController.text) == null) {
      setState(() => _error = 'Indica el numero de cuotas.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.apply(
        reason: reason,
        dueDate: _dueDate,
        principalAmount: _isAmounts || _isAdd ? _parse(_principalController) : null,
        interestAmount: _isAmounts ? _parse(_interestController) : null,
        installmentCount: _isReschedule ? int.tryParse(_countController.text) : null,
        firstDueDate: _firstDueDate,
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

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final date = DateTime.tryParse(iso);
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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

  Widget _impactPanel(InstallmentCorrectionPreview preview) {
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
          _row(
            'Capital pendiente',
            'RD\$ ${formatRdCurrency(impact.outstandingPrincipalBefore)} → '
                'RD\$ ${formatRdCurrency(impact.outstandingPrincipalAfter)}',
            strong: true,
          ),
          _row(
            'Proximo vencimiento',
            '${_fmtDate(impact.nextDueDateBefore)} → '
                '${_fmtDate(impact.nextDueDateAfter)}',
          ),
          _row(
            'Cuotas activas',
            '${impact.installmentCountBefore} → ${impact.installmentCountAfter}',
          ),
          _row(
            'Mora acumulada',
            'RD\$ ${formatRdCurrency(impact.grossLateFeesBefore)} → '
                'RD\$ ${formatRdCurrency(impact.grossLateFeesAfter)}',
          ),
          _row(
            'Mora exigible',
            'RD\$ ${formatRdCurrency(impact.outstandingLateFeesBefore)} → '
                'RD\$ ${formatRdCurrency(impact.outstandingLateFeesAfter)}',
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

    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.installmentNumber != null)
                Text(
                  'Cuota #${widget.installmentNumber}'
                  '${widget.currentDueDate == null ? '' : ' — vence ${_fmtDate(widget.currentDueDate!.toIso8601String())}'}',
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
                              ? 'Correccion permitida.'
                              : 'El servidor no autoriza esta correccion.')
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
              if (_isDate) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : () => _pickDate(first: false),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(
                    _dueDate == null
                        ? 'Seleccionar nuevo vencimiento'
                        : 'Nuevo vencimiento: ${_fmtDate(_dueDate!.toIso8601String())}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (_isAmounts || _isAdd) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _principalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: _isAdd ? 'Capital de la nueva cuota' : 'Capital',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_isAmounts) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _interestController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Interes',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
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
              if (_isReschedule) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
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
                      child: OutlinedButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => _pickDate(first: true),
                        icon: const Icon(Icons.event, size: 16),
                        label: Text(
                          _firstDueDate == null
                              ? 'Primer vencimiento'
                              : _fmtDate(_firstDueDate!.toIso8601String()),
                          style: const TextStyle(fontSize: 12),
                        ),
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
                  labelText: 'Motivo de la correccion',
                  hintText: 'Ej.: cliente solicito reprogramacion',
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
