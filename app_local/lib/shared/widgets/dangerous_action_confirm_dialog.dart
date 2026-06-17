import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/auth_provider.dart';

/// Diálogo de confirmación para acciones peligrosas (ej. reclamar la PC
/// primaria). Muestra una advertencia detallada y exige re-verificar la
/// contraseña del usuario actualmente autenticado.
///
/// Devuelve `true` si el usuario confirmó y la contraseña es válida.
class DangerousActionConfirmDialog extends StatefulWidget {
  const DangerousActionConfirmDialog({
    super.key,
    required this.title,
    required this.warning,
    required this.confirmLabel,
  });

  final String title;
  final String warning;
  final String confirmLabel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String warning,
    String confirmLabel = 'Confirmar acción',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DangerousActionConfirmDialog(
        title: title,
        warning: warning,
        confirmLabel: confirmLabel,
      ),
    );
    return result ?? false;
  }

  @override
  State<DangerousActionConfirmDialog> createState() =>
      _DangerousActionConfirmDialogState();
}

class _DangerousActionConfirmDialogState
    extends State<DangerousActionConfirmDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _verifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthProvider>();
    final currentUserId = auth.currentUser?.id;
    if (currentUserId == null) {
      setState(() {
        _verifying = false;
        _errorMessage = 'No hay sesión activa.';
      });
      return;
    }

    bool ok = false;
    try {
      ok = await auth.authService.verifyPasswordForUser(
        userId: currentUserId,
        password: _passwordController.text,
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() {
        _verifying = false;
        _errorMessage = 'Contraseña incorrecta. Vuelve a intentar.';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: Color(0xFFC2410C),
        size: 36,
      ),
      title: Text(
        widget.title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF1C285)),
                ),
                child: Text(
                  widget.warning,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF6B3000),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Para continuar, escribe tu contraseña:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                autofocus: true,
                onFieldSubmitted: (_) => _onConfirm(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  errorText: _errorMessage,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa tu contraseña';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _verifying ? null : _onConfirm,
          icon: _verifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.shield_outlined, size: 18),
          label: Text(_verifying ? 'Verificando...' : widget.confirmLabel),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC2410C)),
        ),
      ],
    );
  }
}
