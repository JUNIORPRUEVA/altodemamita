import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/lot.dart';

class LotFormDialog extends StatefulWidget {
  const LotFormDialog({
    super.key,
    this.initialLot,
    this.showStatusField = true,
  });

  final Lot? initialLot;
  final bool showStatusField;

  static Future<Lot?> show(
    BuildContext context, {
    Lot? initialLot,
    bool showStatusField = true,
  }) {
    return showDialog<Lot>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LotFormDialog(
        initialLot: initialLot,
        showStatusField: showStatusField,
      ),
    );
  }

  @override
  State<LotFormDialog> createState() => _LotFormDialogState();
}

class _LotFormDialogState extends State<LotFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _blockController;
  late final TextEditingController _lotNumberController;
  late final TextEditingController _areaController;
  late final TextEditingController _pricePerSquareMeterController;

  late String _status;

  bool get _isEditing => widget.initialLot != null;

  @override
  void initState() {
    super.initState();
    _blockController = TextEditingController(
      text: widget.initialLot?.blockNumber ?? '',
    );
    _lotNumberController = TextEditingController(
      text: widget.initialLot?.lotNumber ?? '',
    );
    _areaController = TextEditingController(
      text: widget.initialLot?.area.toString() ?? '0',
    );
    _pricePerSquareMeterController = TextEditingController(
      text: widget.initialLot?.pricePerSquareMeter.toString() ?? '0',
    );
    _status = widget.initialLot?.status ?? Lot.statuses.first;

    _areaController.addListener(_refreshComputedTotal);
    _pricePerSquareMeterController.addListener(_refreshComputedTotal);
  }

  @override
  void dispose() {
    _blockController.dispose();
    _lotNumberController.dispose();
    _areaController.dispose();
    _pricePerSquareMeterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.map_outlined),
      title: Text(_isEditing ? 'Editar solar' : 'Nuevo solar'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Define ubicación, tamaño, precio por metro y estado del solar. El precio total se calcula automáticamente.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _blockController,
                        decoration: const InputDecoration(labelText: 'Manzana'),
                        keyboardType: TextInputType.text,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Obligatorio';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lotNumberController,
                        decoration: const InputDecoration(labelText: 'Número'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Obligatorio';
                          }
                          if (int.tryParse(value.trim()) == null) {
                            return 'Válido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _areaController,
                        decoration: const InputDecoration(
                          labelText: 'Metros cuadrados',
                          suffixText: 'm²',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (_parseDecimal(value) < 0) {
                            return 'No negativo';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pricePerSquareMeterController,
                        decoration: const InputDecoration(
                          labelText: 'Precio por metro',
                          prefixText: 'RD\$ ',
                          suffixText: '/m²',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (_parseDecimal(value) < 0) {
                            return 'No negativo';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey(
                    'lot-total-${_computedTotalPrice.toStringAsFixed(2)}',
                  ),
                  initialValue: _computedTotalPrice.toStringAsFixed(2),
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Precio total calculado',
                    prefixText: 'RD\$ ',
                  ),
                ),
                if (widget.showStatusField) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: Lot.statuses
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _status = value;
                      });
                    },
                  ),
                ],
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
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Guardar cambios' : 'Crear solar'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final baseLot = widget.initialLot ?? Lot.empty();
    final lot = baseLot.copyWith(
      blockNumber: _blockController.text.trim(),
      lotNumber: _lotNumberController.text.trim(),
      area: _parseDecimal(_areaController.text),
      pricePerSquareMeter: _parseDecimal(_pricePerSquareMeterController.text),
      status: _status,
    );

    Navigator.of(context).pop(lot);
  }

  double get _computedTotalPrice {
    final area = _parseDecimal(_areaController.text);
    final unitPrice = _parseDecimal(_pricePerSquareMeterController.text);
    return ((area * unitPrice) * 100).roundToDouble() / 100;
  }

  void _refreshComputedTotal() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  double _parseDecimal(String? value) {
    final parsed = DecimalNumberParser.tryParse(value);
    if (parsed == null) {
      return 0;
    }

    return parsed;
  }
}
