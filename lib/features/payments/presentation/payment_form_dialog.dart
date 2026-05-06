import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../../installments/domain/installment.dart';
import '../domain/payment_draft.dart';
import '../domain/payment_sale_option.dart';

class PaymentFormDialog extends StatefulWidget {
  const PaymentFormDialog({
    super.key,
    required this.sale,
    required this.defaultPaymentMethod,
    this.registeredByUserId,
    this.actionableInstallment,
    this.overdueInstallments = const [],
    this.initialPaymentType,
  });

  final PaymentSaleOption sale;
  final String defaultPaymentMethod;
  final int? registeredByUserId;
  final Installment? actionableInstallment;

  /// Installments with status 'vencida' for the selected sale.
  final List<Installment> overdueInstallments;

  /// Optional initial payment type to pre-select (e.g. 'cuota_vencida').
  final String? initialPaymentType;

  static Future<PaymentDraft?> show(
    BuildContext context, {
    required PaymentSaleOption sale,
    required String defaultPaymentMethod,
    int? registeredByUserId,
    Installment? actionableInstallment,
    List<Installment> overdueInstallments = const [],
    String? initialPaymentType,
  }) {
    return showDialog<PaymentDraft>(
      context: context,
      builder: (dialogContext) => PaymentFormDialog(
        sale: sale,
        defaultPaymentMethod: defaultPaymentMethod,
        registeredByUserId: registeredByUserId,
        actionableInstallment: actionableInstallment,
        overdueInstallments: overdueInstallments,
        initialPaymentType: initialPaymentType,
      ),
    );
  }

  @override
  State<PaymentFormDialog> createState() => _PaymentFormDialogState();
}

class _PaymentFormDialogState extends State<PaymentFormDialog> {
  static const List<String> _paymentMethods = [
    'efectivo',
    'transferencia',
    'cheque',
    'tarjeta',
  ];

  final _formKey = GlobalKey<FormState>();
  static final RdCurrencyInputFormatter _amountFormatter =
      RdCurrencyInputFormatter();
  late final TextEditingController _amountController;
  late final TextEditingController _yearToPayController;
  late String _selectedPaymentMethod;
  late String _selectedPaymentType;
  int? _selectedOverdueInstallmentId;
  late DateTime _paymentDate;
  bool _printReceiptAutomatically = false;

  @override
  void initState() {
    super.initState();
    _paymentDate = DateTime.now();

    // Determine initial payment type
    if (!widget.sale.isFinancingActive) {
      _selectedPaymentType = 'abono_inicial';
    } else if (widget.initialPaymentType != null &&
        _availablePaymentTypes().contains(widget.initialPaymentType)) {
      _selectedPaymentType = widget.initialPaymentType!;
    } else if (widget.overdueInstallments.isNotEmpty) {
      _selectedPaymentType = 'cuota_vencida';
      _selectedOverdueInstallmentId = widget.overdueInstallments.first.id;
    } else if (widget.actionableInstallment != null) {
      _selectedPaymentType = 'cuota';
    } else {
      _selectedPaymentType = 'abono_capital';
    }

    // Prefill amount based on context
    double? prefillAmount;
    if (!widget.sale.isFinancingActive) {
      if (widget.sale.pendingInitialPayment > 0.009) {
        prefillAmount = widget.sale.pendingInitialPayment;
      }
    } else if (_selectedPaymentType == 'cuota_vencida' &&
        widget.overdueInstallments.isNotEmpty) {
      prefillAmount = widget.overdueInstallments.first.remainingAmount;
    } else if (_selectedPaymentType == 'cuota' &&
        widget.actionableInstallment != null) {
      prefillAmount = null; // do not auto-fill for current installment
    }

    _amountController = TextEditingController(
      text: prefillAmount != null
          ? _amountFormatter.formatValue(prefillAmount)
          : '',
    );
    _yearToPayController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final normalizedDefaultMethod = widget.defaultPaymentMethod
        .trim()
        .toLowerCase();
    _selectedPaymentMethod = _paymentMethods.contains(normalizedDefaultMethod)
        ? normalizedDefaultMethod
        : _paymentMethods.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _yearToPayController.dispose();
    super.dispose();
  }

  List<String> _availablePaymentTypes() {
    if (!widget.sale.isFinancingActive) return ['abono_inicial'];
    final types = <String>[];
    if (widget.overdueInstallments.isNotEmpty) {
      types.add('cuota_vencida');
      if (widget.overdueInstallments.length > 1) {
        types.add('todas_cuotas_vencidas');
      }
    }
    if (widget.actionableInstallment != null) types.add('cuota');
    types.add('abono_capital');
    return types;
  }

  String _paymentTypeLabel(String type) {
    return switch (type) {
      'cuota_vencida' => 'Cuota vencida',
      'todas_cuotas_vencidas' => 'Todas las cuotas vencidas',
      'cuota' => 'Cuota actual',
      'abono_capital' => 'Pago a capital',
      'abono_inicial' => 'Abono al inicial',
      _ => type,
    };
  }

  Installment? get _effectiveInstallment {
    if (_selectedPaymentType == 'cuota_vencida' &&
        widget.overdueInstallments.isNotEmpty) {
      if (_selectedOverdueInstallmentId == null) {
        return widget.overdueInstallments.first;
      }
      for (final installment in widget.overdueInstallments) {
        if (installment.id == _selectedOverdueInstallmentId) {
          return installment;
        }
      }
      return widget.overdueInstallments.first;
    }
    if (_selectedPaymentType == 'cuota') {
      return widget.actionableInstallment;
    }
    return null;
  }

  bool get _isCapitalBlocked =>
      _selectedPaymentType == 'abono_capital' &&
      widget.overdueInstallments.isNotEmpty;

  void _onPaymentTypeChanged(String? newType) {
    if (newType == null) return;
    setState(() {
      _selectedPaymentType = newType;
      // Prefill amount when switching types
      if (newType == 'cuota_vencida' && widget.overdueInstallments.isNotEmpty) {
        _selectedOverdueInstallmentId ??= widget.overdueInstallments.first.id;
        _amountController.text = _amountFormatter
            .formatValue(_effectiveInstallment!.remainingAmount);
      } else if (newType == 'todas_cuotas_vencidas' &&
          widget.overdueInstallments.isNotEmpty) {
        final total = widget.overdueInstallments.fold(
          0.0,
          (sum, i) => sum + i.remainingAmount,
        );
        _amountController.text = _amountFormatter.formatValue(total);
      } else if (newType == 'cuota' &&
          widget.actionableInstallment != null) {
        // Don't auto-fill cuota to avoid overwriting user input
      } else if (newType == 'abono_capital') {
        // Clear only if previous was prefilled
      }
    });
  }

  void _applyOverdueInstallment(Installment installment) {
    setState(() {
      _selectedPaymentType = 'cuota_vencida';
      _selectedOverdueInstallmentId = installment.id;
      _amountController.text =
          _amountFormatter.formatValue(installment.remainingAmount);
    });
  }

  void _applyAllOverdueInstallments() {
    final total = widget.overdueInstallments.fold(
      0.0,
      (sum, i) => sum + i.remainingAmount,
    );
    setState(() {
      _selectedPaymentType = 'todas_cuotas_vencidas';
      _amountController.text = _amountFormatter.formatValue(total);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFinancingActive = widget.sale.isFinancingActive;
    final effectiveInstallment = _effectiveInstallment;
    final amount = _parseDouble(_amountController.text) ?? 0;
    final hasAmount = amount > 0.009;

    final installmentApplied = !isFinancingActive || effectiveInstallment == null
        ? 0.0
        : amount.clamp(0.0, effectiveInstallment.remainingAmount);
    final capitalApplied = isFinancingActive
        ? (amount - installmentApplied).clamp(0.0, double.infinity)
        : 0.0;
    final currentPendingAmount = isFinancingActive
        ? widget.sale.pendingBalance
        : widget.sale.pendingInitialPayment;
    final projectedPendingAmount =
        (currentPendingAmount - amount).clamp(0.0, double.infinity);

    final dialogTitle = !isFinancingActive
        ? (widget.sale.paidInitialPayment <= 0.009
              ? 'Pagar apartado del inicial'
              : 'Pagar completivo del inicial')
        : 'Registrar pago';

    final screenSize = MediaQuery.sizeOf(context);
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final useCompactTwoColumnLayout = isWindows || screenSize.width >= 860;
    final panelWidth = isWindows
      ? math.min(960.0, screenSize.width - 16.0)
      : math.min(700.0, screenSize.width - 24.0);
    final insetPadding = isWindows
      ? EdgeInsets.fromLTRB(
          math.max(8.0, screenSize.width - panelWidth - 8.0),
          8,
          8,
          8,
        )
      : const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
    final maxDialogHeight = isWindows
      ? screenSize.height - 16.0
      : screenSize.height - 24.0;

    final theme = Theme.of(context);
    final availableTypes = _availablePaymentTypes();

    final formBody = Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirma el monto, el método de pago y la fecha para generar el recibo correctamente.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.sale.clientName} • ${widget.sale.lotDisplayCode}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              isFinancingActive
                  ? 'Saldo pendiente del plan: ${_money(widget.sale.pendingBalance)}'
                  : 'Inicial pendiente: ${_money(widget.sale.pendingInitialPayment)} de ${_money(widget.sale.requiredInitialPayment)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF556079)),
            ),
            if (isFinancingActive && availableTypes.length > 1) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedPaymentType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de pago',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: availableTypes
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(_paymentTypeLabel(type)),
                      ),
                    )
                    .toList(),
                onChanged: _onPaymentTypeChanged,
              ),
            ],
            if (_isCapitalBlocked) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE53E3E)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFE53E3E),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No puedes aplicar pago a capital porque este cliente tiene cuotas vencidas. Primero debes saldar las cuotas atrasadas.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFE53E3E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isFinancingActive && effectiveInstallment != null) ...[
              const SizedBox(height: 8),
              Text(
                _selectedPaymentType == 'cuota_vencida'
                    ? 'Cuota vencida #${effectiveInstallment.installmentNumber} — vence ${_formatDate(effectiveInstallment.dueDate)} — restante ${_money(effectiveInstallment.remainingAmount)}'
                    : 'Cuota exigible #${effectiveInstallment.installmentNumber} — restante ${_money(effectiveInstallment.remainingAmount)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF556079)),
              ),
            ],
            if (isFinancingActive && effectiveInstallment == null && !_isCapitalBlocked) ...[
              const SizedBox(height: 8),
              Text(
                _selectedPaymentType == 'abono_capital'
                    ? 'El pago se aplicará directamente al saldo de capital.'
                    : _selectedPaymentType == 'todas_cuotas_vencidas'
                    ? 'Se aplicará el pago a ${widget.overdueInstallments.length} cuota${widget.overdueInstallments.length == 1 ? '' : 's'} vencida${widget.overdueInstallments.length == 1 ? '' : 's'} en orden.'
                    : 'No hay cuota vencida o exigible hoy.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF556079)),
              ),
            ],
            if (isFinancingActive) ...[
              const SizedBox(height: 16),
              _buildOverdueInstallmentsSection(),
            ],
            const SizedBox(height: 16),
            if (!useCompactTwoColumnLayout) ...[
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixIcon: Icon(Icons.attach_money_outlined),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_amountFormatter],
                validator: (value) {
                  final parsed = _parseDouble(value);
                  if (parsed == null || parsed <= 0) {
                    return 'Ingrese un monto válido mayor que cero';
                  }
                  if (!isFinancingActive &&
                      parsed - widget.sale.pendingInitialPayment > 0.009) {
                    return 'No puede exceder el inicial pendiente';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedPaymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Método',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                items: _paymentMethods
                    .map(
                      (method) => DropdownMenuItem<String>(
                        value: method,
                        child: Text(_capitalize(method)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedPaymentMethod = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickPaymentDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_formatDate(_paymentDate)),
              ),
              const SizedBox(height: 12),
              if (isFinancingActive) ...[
                TextFormField(
                  controller: _yearToPayController,
                  decoration: const InputDecoration(
                    labelText: 'Año a pagar (opcional)',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                    hintText: 'Ej: 2025',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed < 2000 || parsed > 2100) {
                      return 'Año válido entre 2000-2100';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'Monto',
                        prefixIcon: Icon(Icons.attach_money_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [_amountFormatter],
                      validator: (value) {
                        final parsed = _parseDouble(value);
                        if (parsed == null || parsed <= 0) {
                          return 'Monto inválido';
                        }
                        if (!isFinancingActive &&
                            parsed - widget.sale.pendingInitialPayment >
                                0.009) {
                          return 'Excede inicial';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedPaymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Método',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items: _paymentMethods
                          .map(
                            (method) => DropdownMenuItem<String>(
                              value: method,
                              child: Text(_capitalize(method)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedPaymentMethod = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Obligatorio';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPaymentDate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_formatDate(_paymentDate)),
                    ),
                  ),
                  if (isFinancingActive) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _yearToPayController,
                        decoration: const InputDecoration(
                          labelText: 'Año a pagar (opcional)',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          hintText: 'Ej: 2025',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null || parsed < 2000 || parsed > 2100) {
                            return 'Año inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
            ],
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Imprimir tique automáticamente'),
              subtitle: const Text(
                'Si activas esta opción, al guardar el pago se abre e imprime el recibo.',
              ),
              value: _printReceiptAutomatically,
              onChanged: (value) {
                setState(() {
                  _printReceiptAutomatically = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumen del recibo',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!hasAmount)
                    Text(
                      'Ingrese un monto para ver el resumen del pago.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else ...[
                    _summaryRow('Recibido de', widget.sale.clientName),
                    _summaryRow('Solar', widget.sale.lotDisplayCode),
                    _summaryRow('Fecha', _formatDate(_paymentDate)),
                    _summaryRow('Método', _capitalize(_selectedPaymentMethod)),
                    _summaryRow(
                      'Tipo',
                      isFinancingActive
                          ? _paymentTypeLabel(_selectedPaymentType)
                          : _initialPaymentKindLabel(amount),
                    ),
                    _summaryRow(
                      'Concepto',
                      !isFinancingActive
                          ? _initialPaymentKindLabel(amount)
                          : _selectedPaymentType == 'todas_cuotas_vencidas'
                          ? '${widget.overdueInstallments.length} cuotas vencidas: ${widget.overdueInstallments.map((i) => '#${i.installmentNumber}').join(', ')}'
                          : effectiveInstallment == null
                          ? 'Abono a capital'
                          : amount > effectiveInstallment.remainingAmount
                          ? 'Cuota #${effectiveInstallment.installmentNumber} + abono a capital'
                          : 'Cuota #${effectiveInstallment.installmentNumber}',
                    ),
                    _summaryRow('Pago a registrar', _money(amount)),
                    _summaryRow(
                      isFinancingActive
                          ? 'Saldo actual del plan'
                          : 'Inicial pendiente actual',
                      _money(currentPendingAmount),
                    ),
                    _summaryRow(
                      isFinancingActive
                          ? 'Saldo luego del pago'
                          : 'Inicial luego del pago',
                      _money(projectedPendingAmount),
                      highlight: true,
                    ),
                    if (installmentApplied > 0.009)
                      _summaryRow(
                        'Cubre cuota',
                        'Cuota #${effectiveInstallment!.installmentNumber} → ${_money(installmentApplied)}',
                      ),
                    if (capitalApplied > 0.009 &&
                        _selectedPaymentType != 'todas_cuotas_vencidas')
                      _summaryRow('Abono a capital', _money(capitalApplied)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final canSave = !_isCapitalBlocked;

    final dialog = Dialog(
      insetPadding: insetPadding,
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: panelWidth,
          maxHeight: maxDialogHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      dialogTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: formBody),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canSave ? _submit : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar pago'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!isWindows) {
      return dialog;
    }
    return Align(alignment: Alignment.centerRight, child: dialog);
  }

  Widget _buildOverdueInstallmentsSection() {
    final overdueInstallments = widget.overdueInstallments;
    if (overdueInstallments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4EAF2)),
        ),
        child: const Text(
          'No hay cuotas vencidas para esta venta. Puedes registrar cuota actual o pago a capital.',
          style: TextStyle(fontSize: 13, color: Color(0xFF556079)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8B4B4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFE53E3E),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cuotas atrasadas (${overdueInstallments.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
                if (overdueInstallments.length > 1) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 30,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB91C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _applyAllOverdueInstallments,
                      icon: const Icon(Icons.playlist_add_check, size: 14),
                      label: Text(
                        'Pagar todas (${_money(overdueInstallments.fold(0.0, (s, i) => s + i.remainingAmount))})',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8B4B4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 820;
                final itemWidth = twoColumns
                    ? (constraints.maxWidth - 8) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: overdueInstallments.map((installment) {
                    final selected = installment.id == _selectedOverdueInstallmentId;
                    return SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFFFEFEF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFE53E3E)
                                : const Color(0xFFE4EAF2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Cuota #${installment.installmentNumber} · ${_formatDate(installment.dueDate)} · ${_money(installment.remainingAmount)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A2235),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              height: 30,
                              child: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                onPressed: () => _applyOverdueInstallment(installment),
                                child: const Text(
                                  'Aplicar',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      _paymentDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _paymentDate.hour,
        _paymentDate.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final isFinancingActive = widget.sale.isFinancingActive;
    Navigator.of(context).pop(
      PaymentDraft(
        saleId: widget.sale.saleId,
        paymentDate: _paymentDate,
        amountPaid: _parseDouble(_amountController.text)!,
        paymentMethod: _selectedPaymentMethod,
        registeredByUserId: widget.registeredByUserId,
        yearToPay: !isFinancingActive ||
                _yearToPayController.text.trim().isEmpty
            ? null
            : _yearToPayController.text.trim(),
        printReceiptAutomatically: _printReceiptAutomatically,
        paymentTypeOverride: isFinancingActive ? _selectedPaymentType : null,
      ),
    );
  }

  double? _parseDouble(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return parseRdCurrency(value);
  }

  String _money(double value) => 'RD\$ ${formatRdCurrency(value)}';

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _initialPaymentKindLabel(double amount) {
    if (widget.sale.paidInitialPayment <= 0.009) return 'Apartado';
    if (amount >= widget.sale.pendingInitialPayment - 0.009) {
      return 'Abono a inicial que completa activación';
    }
    return 'Abono a inicial';
  }

  Widget _summaryRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: highlight ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                color: highlight ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
