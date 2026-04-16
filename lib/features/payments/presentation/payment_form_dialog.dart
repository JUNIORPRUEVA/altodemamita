import 'package:flutter/material.dart';

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
  });

  final PaymentSaleOption sale;
  final String defaultPaymentMethod;
  final int? registeredByUserId;
  final Installment? actionableInstallment;

  static Future<PaymentDraft?> show(
    BuildContext context, {
    required PaymentSaleOption sale,
    required String defaultPaymentMethod,
    int? registeredByUserId,
    Installment? actionableInstallment,
  }) {
    return showDialog<PaymentDraft>(
      context: context,
      builder: (dialogContext) => PaymentFormDialog(
        sale: sale,
        defaultPaymentMethod: defaultPaymentMethod,
        registeredByUserId: registeredByUserId,
        actionableInstallment: actionableInstallment,
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
  late final TextEditingController _amountController;
  late final TextEditingController _yearToPayController;
  late String _selectedPaymentMethod;
  late DateTime _paymentDate;
  bool _printReceiptAutomatically = false;

  @override
  void initState() {
    super.initState();
    _paymentDate = DateTime.now();
    _amountController = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
    final isFinancingActive = widget.sale.isFinancingActive;
    final actionableInstallment = widget.actionableInstallment;
    final amount = _parseDouble(_amountController.text) ?? 0;
    final installmentApplied =
        !isFinancingActive || actionableInstallment == null
        ? 0.0
        : amount.clamp(0.0, actionableInstallment.remainingAmount);
    final capitalApplied = isFinancingActive
        ? (amount - installmentApplied).clamp(0.0, double.infinity)
        : 0.0;

    return AlertDialog(
      icon: const Icon(Icons.payments_outlined),
      title: const Text('Registrar pago'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                ),
                const SizedBox(height: 8),
                Text(
                  isFinancingActive
                      ? 'Saldo financiado pendiente: ${widget.sale.pendingBalance.toStringAsFixed(2)}'
                      : 'Inicial pendiente: ${widget.sale.pendingInitialPayment.toStringAsFixed(2)} de ${widget.sale.requiredInitialPayment.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                Text(
                  !isFinancingActive
                      ? 'Este pago se registrará como apartado o abono a inicial. Las cuotas no operan hasta completar el inicial.'
                      : actionableInstallment == null
                      ? 'No hay cuota vencida o exigible hoy. El pago se aplicara directo a capital.'
                      : 'Cuota exigible: #${actionableInstallment.installmentNumber} por ${actionableInstallment.remainingAmount.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    prefixIcon: Icon(Icons.attach_money_outlined),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final parsed = _parseDouble(value);
                    if (parsed == null || parsed <= 0) {
                      return 'Monto válido';
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
                    if (value == null) {
                      return;
                    }
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
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                      _summaryRow('Recibido de', widget.sale.clientName),
                      _summaryRow('Solar', widget.sale.lotDisplayCode),
                      _summaryRow('Fecha', _formatDate(_paymentDate)),
                      _summaryRow(
                        'Método',
                        _capitalize(_selectedPaymentMethod),
                      ),
                      _summaryRow(
                        'Concepto',
                        !isFinancingActive
                            ? (_initialPaymentKindLabel(amount))
                            : actionableInstallment == null
                            ? 'Abono a capital'
                            : amount > actionableInstallment.remainingAmount
                            ? 'Cuota #${actionableInstallment.installmentNumber} + abono a capital'
                            : 'Cuota #${actionableInstallment.installmentNumber}',
                      ),
                      _summaryRow(
                        'Monto total',
                        'RD\$ ${amount.toStringAsFixed(2)}',
                      ),
                      if (installmentApplied > 0)
                        _summaryRow(
                          'Aplicado a cuota',
                          'RD\$ ${installmentApplied.toStringAsFixed(2)}',
                        ),
                      if (!isFinancingActive)
                        _summaryRow(
                          'Aplicado a inicial',
                          'RD\$ ${amount.toStringAsFixed(2)}',
                        ),
                      if (capitalApplied > 0)
                        _summaryRow(
                          'Aplicado a capital',
                          'RD\$ ${capitalApplied.toStringAsFixed(2)}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar pago')),
      ],
    );
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }

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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      PaymentDraft(
        saleId: widget.sale.saleId,
        paymentDate: _paymentDate,
        amountPaid: _parseDouble(_amountController.text)!,
        paymentMethod: _selectedPaymentMethod,
        registeredByUserId: widget.registeredByUserId,
        yearToPay:
            !widget.sale.isFinancingActive ||
                _yearToPayController.text.trim().isEmpty
            ? null
            : _yearToPayController.text.trim(),
        printReceiptAutomatically: _printReceiptAutomatically,
      ),
    );
  }

  double? _parseDouble(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return double.tryParse(value.replaceAll(',', '.').trim());
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _initialPaymentKindLabel(double amount) {
    if (widget.sale.paidInitialPayment <= 0.009) {
      return 'Apartado';
    }
    if (amount >= widget.sale.pendingInitialPayment - 0.009) {
      return 'Abono a inicial que completa activación';
    }
    return 'Abono a inicial';
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
