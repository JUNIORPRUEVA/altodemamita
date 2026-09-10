import 'package:flutter/material.dart';

/// Motivos canonicos de anulacion de pago, en lenguaje operativo.
///
/// Este componente es EXCLUSIVO de la ANULACION de un pago. No debe usarse
/// para registrar pagos, aplicar cuotas, abonar capital ni registrar iniciales:
/// esos flujos conservan su propio formulario (`PaymentFormDialog`).
class PaymentAnnulReasons {
  const PaymentAnnulReasons._();

  static const String registeredByMistake = 'Pago registrado por error';
  static const String wrongAmount = 'Monto incorrecto';
  static const String wrongMethod = 'Método de pago incorrecto';
  static const String duplicated = 'Pago duplicado';
  static const String other = 'Otro';

  static const List<String> all = <String>[
    registeredByMistake,
    wrongAmount,
    wrongMethod,
    duplicated,
    other,
  ];

  /// Texto de ayuda mostrado mientras no hay motivo elegido.
  static const String placeholder = 'Seleccione un motivo';

  /// Motivo final que se envia al backend.
  ///
  /// Devuelve `null` cuando no hay una seleccion valida (sin motivo, o "Otro"
  /// sin descripcion), de modo que nunca se envia una anulacion sin motivo.
  /// Para "Otro" se conserva la trazabilidad con el prefijo `Otro: `.
  static String? resolve(String? selected, String customDescription) {
    final value = selected?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    if (value != other) {
      return value;
    }
    final custom = customDescription.trim();
    if (custom.isEmpty) {
      return null;
    }
    return '$other: $custom';
  }
}

/// Etiqueta de concepto usada en la confirmacion de anulacion.
String paymentAnnulConceptLabel(String paymentType, int? installmentNumber) {
  switch (paymentType) {
    case 'inicial':
    case 'abono_inicial':
      return 'Abono a inicial';
    case 'apartado':
      return 'Abono a apartado';
    case 'abono_capital':
      return 'Abono a capital';
    case 'cuota':
      return installmentNumber == null
          ? 'Cuota'
          : 'Cuota $installmentNumber';
    default:
      return paymentType.isEmpty ? 'Pago' : paymentType;
  }
}

class PaymentAnnulResult {
  const PaymentAnnulResult({required this.reason, this.adminAuthorizationId});

  final String reason;
  final String? adminAuthorizationId;
}

typedef PaymentAnnulAuthorizer =
    Future<({String? authorizationId, String? error})> Function(
      String email,
      String password,
    );

/// Dialogo unico de anulacion de pago.
///
/// Estado inicial: SIN motivo seleccionado (placeholder "Seleccione un motivo").
/// El boton de confirmacion permanece deshabilitado hasta que exista un motivo
/// valido, y el backend solo recibe motivos limpios.
class PaymentAnnulDialog extends StatefulWidget {
  const PaymentAnnulDialog({
    super.key,
    required this.clientName,
    required this.concept,
    required this.amount,
    required this.paymentDate,
    required this.requiresAdminAuthorization,
    required this.onAuthorize,
  });

  final String clientName;
  final String concept;
  final String amount;
  final String paymentDate;
  final bool requiresAdminAuthorization;
  final PaymentAnnulAuthorizer onAuthorize;

  @override
  State<PaymentAnnulDialog> createState() => _PaymentAnnulDialogState();
}

class _PaymentAnnulDialogState extends State<PaymentAnnulDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otherReasonController = TextEditingController();

  /// Sin seleccion por defecto: el operador debe elegir.
  String? _selectedReason;

  String? _error;
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otherReasonController.dispose();
    super.dispose();
  }

  String? get _resolvedReason =>
      PaymentAnnulReasons.resolve(_selectedReason, _otherReasonController.text);

  bool get _canConfirm => !_submitting && _resolvedReason != null;

  Future<void> _submit() async {
    final reason = _resolvedReason;
    if (reason == null) {
      setState(
        () => _error = 'Selecciona un motivo para anular el pago.',
      );
      return;
    }

    String? authorizationId;
    if (widget.requiresAdminAuthorization) {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        setState(() {
          _error = 'Introduce el usuario y la contrasena del administrador.';
        });
        return;
      }
      setState(() {
        _submitting = true;
        _error = null;
      });
      final result = await widget.onAuthorize(email, password);
      if (!mounted) {
        return;
      }
      if (result.authorizationId == null) {
        setState(() {
          _submitting = false;
          _error =
              result.error ??
              'Las credenciales del administrador no son validas.';
        });
        return;
      }
      authorizationId = result.authorizationId;
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      PaymentAnnulResult(reason: reason, adminAuthorizationId: authorizationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOther = _selectedReason == PaymentAnnulReasons.other;

    return AlertDialog(
      title: const Text('Anular pago'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dialogDetail('Cliente', widget.clientName),
              _dialogDetail('Concepto', widget.concept),
              _dialogDetail('Monto', widget.amount),
              _dialogDetail('Fecha', widget.paymentDate),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF0D9A8)),
                ),
                child: const Text(
                  'Esta acción revertirá el efecto financiero del pago.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8A6A1F)),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Motivo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                hint: const Text(
                  PaymentAnnulReasons.placeholder,
                  style: TextStyle(fontSize: 13, color: Color(0xFF8893AA)),
                ),
                items: [
                  for (final reason in PaymentAnnulReasons.all)
                    DropdownMenuItem<String>(
                      value: reason,
                      child: Text(reason, style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        setState(() {
                          _selectedReason = value;
                          _error = null;
                        });
                      },
              ),
              if (_selectedReason == null) ...[
                const SizedBox(height: 6),
                const Text(
                  'Selecciona un motivo para anular el pago.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF556079)),
                ),
              ],
              if (isOther) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _otherReasonController,
                  enabled: !_submitting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Especifique el motivo',
                    isDense: true,
                  ),
                ),
              ],
              if (widget.requiresAdminAuthorization) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF3FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC9D8F5)),
                  ),
                  child: const Text(
                    'Necesitas autorizacion de un administrador para anular este pago.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF2C5282)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Usuario administrador',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  enabled: !_submitting,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contrasena del administrador',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB3261E),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canConfirm ? _submit : null,
          child: Text(_submitting ? 'Validando...' : 'Anular pago'),
        ),
      ],
    );
  }

  Widget _dialogDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8893AA)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
