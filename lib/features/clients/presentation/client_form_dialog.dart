import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/dominican_validators.dart';
import '../domain/client.dart';

class ClientFormDialog extends StatefulWidget {
  const ClientFormDialog({super.key, this.initialClient});

  final Client? initialClient;

  static Future<Client?> show(BuildContext context, {Client? initialClient}) {
    return showDialog<Client>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClientFormDialog(initialClient: initialClient),
    );
  }

  @override
  State<ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _documentIdController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  bool get _isEditing => widget.initialClient != null;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.initialClient?.fullName ?? '',
    );
    _documentIdController = TextEditingController(
      text: widget.initialClient?.documentId ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.initialClient?.phone ?? '',
    );
    _addressController = TextEditingController(
      text: widget.initialClient?.address ?? '',
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _documentIdController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.person_outline),
      title: Text(_isEditing ? 'Editar cliente' : 'Nuevo cliente'),
      content: SizedBox(
        width: 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Completa los datos principales del cliente para poder usarlo en ventas, pagos y reportes.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                  ),
                  validator: DominicanValidators.validateName,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _documentIdController,
                  decoration: const InputDecoration(
                    labelText: 'Cédula',
                    helperText:
                        'Digite solo números. Puede ser cédula, pasaporte u otro documento numérico.',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: DominicanValidators.validateFlexibleDocumentId,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    helperText:
                        'Digite solo números. Puede ser un número local o extranjero.',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: DominicanValidators.validateFlexiblePhone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                  ),
                  maxLines: 2,
                  validator: DominicanValidators.validateAddress,
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
          child: Text(_isEditing ? 'Guardar cambios' : 'Crear cliente'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final baseClient = widget.initialClient ?? Client.empty();
    final documentId = DominicanValidators.digitsOnly(
      _documentIdController.text,
    );
    final client = baseClient.copyWith(
      fullName: _fullNameController.text.trim(),
      documentId: documentId,
      phone: _normalizePhone(_phoneController.text),
      address: _formatAddress(_addressController.text),
    );

    Navigator.of(context).pop(client);
  }

  String? _normalizePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final digits = DominicanValidators.digitsOnly(trimmed);
    return digits.isEmpty ? null : digits;
  }

  String? _formatAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DominicanValidators.normalizeAddress(trimmed);
  }
}
