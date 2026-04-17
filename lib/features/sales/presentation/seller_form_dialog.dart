import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../../../core/utils/dominican_validators.dart';
import '../domain/seller.dart';

class SellerFormDialog extends StatefulWidget {
  const SellerFormDialog({super.key, this.initialSeller});

  final Seller? initialSeller;

  static Future<Seller?> show(BuildContext context, {Seller? initialSeller}) {
    return showDialog<Seller>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SellerFormDialog(initialSeller: initialSeller),
    );
  }

  @override
  State<SellerFormDialog> createState() => _SellerFormDialogState();
}

class _SellerFormDialogState extends State<SellerFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _documentIdController;
  late final TextEditingController _phoneController;

  bool get _isEditing => widget.initialSeller != null;

  String? _validateDocumentId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La cédula es obligatoria.';
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialSeller?.name ?? '',
    );
    _documentIdController = TextEditingController(
      text: widget.initialSeller?.documentId ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.initialSeller?.phone ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _documentIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.badge_outlined),
      title: Text(_isEditing ? 'Editar vendedor' : 'Nuevo vendedor'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registra la información comercial del vendedor para asignarlo a nuevas ventas.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  inputFormatters: [NameFormatter()],
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _documentIdController,
                  decoration: const InputDecoration(labelText: 'Cédula'),
                  validator: _validateDocumentId,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  inputFormatters: [DominicanPhoneFormatter()],
                  validator: DominicanValidators.validateDominicanPhone,
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
          child: Text(_isEditing ? 'Guardar cambios' : 'Crear vendedor'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final seller = Seller(
      id: widget.initialSeller?.id,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      documentId: _documentIdController.text.trim(),
      createdAt: widget.initialSeller?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.of(context).pop(seller);
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre es obligatorio.';
    }

    if (value.trim().length < 3) {
      return 'El nombre debe tener al menos 3 caracteres.';
    }

    return null;
  }
}
