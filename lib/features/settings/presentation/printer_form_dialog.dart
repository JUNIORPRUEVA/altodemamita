import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../data/printer_repository.dart';
import '../domain/printer_config.dart';

class PrinterFormDialog extends StatefulWidget {
  const PrinterFormDialog({
    super.key,
    this.initialPrinter,
    required this.printerRepository,
  });

  final PrinterConfig? initialPrinter;
  final PrinterRepository printerRepository;

  static Future<PrinterConfig?> show(
    BuildContext context, {
    PrinterConfig? initialPrinter,
    required PrinterRepository printerRepository,
  }) {
    return showDialog<PrinterConfig>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrinterFormDialog(
        initialPrinter: initialPrinter,
        printerRepository: printerRepository,
      ),
    );
  }

  @override
  State<PrinterFormDialog> createState() => _PrinterFormDialogState();
}

class _PrinterFormDialogState extends State<PrinterFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreController;
  late final TextEditingController _modeloController;

  late String _selectedTipo;
  late bool _esPredeterminada;
  bool _isPickingPrinter = false;
  Printer? _selectedSystemPrinter;

  bool get _isEditing => widget.initialPrinter != null;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: widget.initialPrinter?.nombre ?? '',
    );
    _modeloController = TextEditingController(
      text: widget.initialPrinter?.modelo ?? '',
    );
    _selectedTipo = widget.initialPrinter?.tipo ?? 'térmica';
    _esPredeterminada = widget.initialPrinter?.esPredeterminada ?? false;
    final configMap = widget.initialPrinter?.configuracionMap;
    if (configMap != null && configMap.isNotEmpty) {
      try {
        _selectedSystemPrinter = Printer.fromMap(configMap);
      } catch (_) {
        _selectedSystemPrinter = null;
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _modeloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar impresora' : 'Nueva impresora'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombreController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modeloController,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: PrinterConfig.tipos
                      .map(
                        (tipo) =>
                            DropdownMenuItem(value: tipo, child: Text(tipo)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedTipo = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Impresora del sistema',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDCE3EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedSystemPrinter?.name ??
                            'Ninguna impresora seleccionada',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedSystemPrinter?.model ??
                            'Selecciona una impresora del sistema para habilitar la impresión rápida.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if ((_selectedSystemPrinter?.location ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Ubicación: ${_selectedSystemPrinter!.location!}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _isPickingPrinter
                                ? null
                                : _pickSystemPrinter,
                            icon: _isPickingPrinter
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.print_outlined),
                            label: Text(
                              _selectedSystemPrinter == null
                                  ? 'Seleccionar impresora'
                                  : 'Cambiar impresora',
                            ),
                          ),
                          if (_selectedSystemPrinter != null)
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedSystemPrinter = null;
                                });
                              },
                              icon: const Icon(Icons.close_outlined),
                              label: const Text('Quitar selección'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Impresora predeterminada'),
                  value: _esPredeterminada,
                  onChanged: (value) {
                    setState(() {
                      _esPredeterminada = value;
                    });
                  },
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
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Guardar cambios' : 'Crear impresora'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    PrinterConfig printer;
    if (_selectedSystemPrinter != null) {
      printer = widget.printerRepository
          .mergeSystemPrinter(
            printer: _selectedSystemPrinter!,
            current: widget.initialPrinter,
            tipo: _selectedTipo,
            esPredeterminada: _esPredeterminada,
          )
          .copyWith(
            nombre: _nombreController.text.trim(),
            modelo: _modeloController.text.trim(),
          );
    } else {
      final basePrinter = widget.initialPrinter ?? PrinterConfig.empty();
      printer = basePrinter.copyWith(
        nombre: _nombreController.text.trim(),
        modelo: _modeloController.text.trim(),
        tipo: _selectedTipo,
        esPredeterminada: _esPredeterminada,
        fechaActualizacion: DateTime.now(),
      );
    }

    Navigator.of(context).pop(printer);
  }

  Future<void> _pickSystemPrinter() async {
    setState(() {
      _isPickingPrinter = true;
    });

    try {
      final printer = await Printing.pickPrinter(
        context: context,
        title: 'Selecciona la impresora para impresión rápida',
      );
      if (!mounted || printer == null) {
        return;
      }

      setState(() {
        _selectedSystemPrinter = printer;
        _nombreController.text = printer.name;
        _modeloController.text = (printer.model ?? '').trim().isEmpty
            ? printer.name
            : printer.model!;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'seleccionar la impresora',
        error,
        module: 'configuracion',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingPrinter = false;
        });
      }
    }
  }
}
