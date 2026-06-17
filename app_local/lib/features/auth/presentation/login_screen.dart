import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth_service.dart';
import 'auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;

  Future<void> _prefillDebugCredentials() async {
    final auth = context.read<AuthProvider>();
    AdminRecoveryCredentials? credentials;
    try {
      credentials = await auth.authService.getDebugAdminPrefillCredentials();
    } catch (_) {
      return;
    }
    if (!mounted || credentials == null) {
      return;
    }

    if (_emailController.text.trim().isEmpty) {
      _emailController.text = credentials.email;
    }
    if (_passwordController.text.isEmpty) {
      _passwordController.text = credentials.password;
    }
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prefillDebugCredentials();
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = context.read<AuthProvider>();
    await auth.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  Future<void> _openRecoveryDialog() async {
    final credentials = await showDialog<AdminRecoveryCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RecoveryAccessDialog(),
    );

    if (!mounted || credentials == null) {
      return;
    }

    setState(() {
      _emailController.text = credentials.email;
      _passwordController.text = credentials.password;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final errorMessage = auth.errorMessage;
    final backendMessage = auth.backendStatusMessage?.trim();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF5F7FA)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D2844),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18000000),
                            blurRadius: 28,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                children: [
                                  Container(
                                    width: 62,
                                    height: 62,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.wb_sunny_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  const Text(
                                    'Sistema Solares',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Iniciar sesion local',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.88,
                                      ),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (backendMessage != null &&
                                      backendMessage.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      backendMessage,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.70,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 24),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: errorMessage == null
                                    ? const SizedBox.shrink()
                                    : Container(
                                        key: ValueKey<String>(errorMessage),
                                        margin: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8F2436),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.error_outline,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                errorMessage,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              _LoginField(
                                controller: _emailController,
                                hintText: 'Correo o usuario',
                                icon: Icons.mail_outline,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.text,
                                onFieldSubmitted: (_) =>
                                    _passwordFocusNode.requestFocus(),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) {
                                    return 'Ingresa tu correo o usuario';
                                  }
                                  if (trimmed.contains('@') &&
                                      (!trimmed.contains('.') ||
                                          trimmed.startsWith('@') ||
                                          trimmed.endsWith('@'))) {
                                    return 'Ingresa un correo valido';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              _LoginField(
                                controller: _passwordController,
                                focusNode: _passwordFocusNode,
                                hintText: 'Contrasena',
                                icon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white.withValues(alpha: 0.78),
                                    size: 20,
                                  ),
                                ),
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                validator: (value) {
                                  if ((value ?? '').isEmpty) {
                                    return 'Ingresa tu contrasena';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: auth.isSigningIn ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF0D2844),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: auth.isSigningIn
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : const Text(
                                        'Entrar',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    onPressed: auth.isSigningIn
                                        ? null
                                        : _openRecoveryDialog,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: Colors.white.withValues(
                                        alpha: 0.48,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    child:
                                        const Text('Recuperar la contrasena'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.validator,
    this.focusNode,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final String? Function(String?) validator;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.82)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        errorStyle: const TextStyle(color: Color(0xFFFFC9D1)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFFA8B5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFFC9D1), width: 1.2),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class _RecoveryAccessDialog extends StatefulWidget {
  const _RecoveryAccessDialog();

  @override
  State<_RecoveryAccessDialog> createState() => _RecoveryAccessDialogState();
}

class _RecoveryAccessDialogState extends State<_RecoveryAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _recoveryCodeController = TextEditingController();
  final _nameController = TextEditingController(
    text: 'Administrador principal',
  );
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscureRecoveredPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _resetMode = false;
  String? _errorMessage;
  String? _infoMessage;
  AdminRecoveryCredentials? _credentials;

  @override
  void dispose() {
    _recoveryCodeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final auth = context.read<AuthProvider>();
    if (_resetMode) {
      final success = await auth.recoverAdminAccess(
        recoveryCode: _recoveryCodeController.text,
        nombre: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      if (success) {
        Navigator.of(context).pop(
          AdminRecoveryCredentials(
            nombre: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        );
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage =
            auth.errorMessage ??
            'No se pudo actualizar el acceso del administrador.';
      });
      return;
    }

    final credentials = await auth.revealAdminCredentials(
      recoveryCode: _recoveryCodeController.text,
    );

    if (!mounted) {
      return;
    }

    if (credentials != null) {
      setState(() {
        _isSubmitting = false;
        _credentials = credentials;
      });
      return;
    }

    if (auth.errorMessage ==
        AuthService.adminRecoverySnapshotUnavailableMessage) {
      setState(() {
        _isSubmitting = false;
        _resetMode = true;
        _errorMessage = null;
        _infoMessage =
            'Esta instalacion es anterior a la nueva recuperacion visible. Usa la misma clave para definir un nuevo correo y una nueva contrasena del administrador.';
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorMessage =
          auth.errorMessage ??
          'No se pudo recuperar el acceso en este momento.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final credentials = _credentials;

    return AlertDialog(
      title: const Text('Recuperar la contrasena'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  credentials == null && !_resetMode
                      ? 'Escribe la clave unica de recuperacion para ver el correo y la contrasena actuales del administrador principal.'
                      : _resetMode
                      ? 'Ingresa la clave unica y define el nuevo correo y la nueva contrasena del administrador principal.'
                      : 'Estos son los datos actuales de inicio de sesion protegidos por tu clave de recuperacion.',
                ),
                const SizedBox(height: 14),
                if (_infoMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCFE0FF)),
                    ),
                    child: Text(
                      _infoMessage!,
                      style: const TextStyle(color: Color(0xFF244A8F)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEF1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCCD4)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFF8F2436)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _recoveryCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Clave de recuperacion',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Ingresa la clave de recuperacion';
                    }
                    return null;
                  },
                ),
                if (_resetMode) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del administrador',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Ingresa el nombre del administrador';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo correo de acceso',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (value) {
                      final trimmed = (value ?? '').trim();
                      if (trimmed.isEmpty || !trimmed.contains('@')) {
                        return 'Ingresa un correo valido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'Nueva contrasena',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscureNewPassword = !_obscureNewPassword;
                          });
                        },
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().length < 8) {
                        return 'Usa al menos 8 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirmar contrasena',
                      prefixIcon: const Icon(Icons.verified_user_outlined),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Las contrasenas no coinciden';
                      }
                      return null;
                    },
                  ),
                ],
                if (credentials != null) ...[
                  const SizedBox(height: 16),
                  _RecoveryDataTile(
                    icon: Icons.person_outline,
                    label: 'Administrador',
                    value: credentials.nombre,
                  ),
                  const SizedBox(height: 10),
                  _RecoveryDataTile(
                    icon: Icons.mail_outline,
                    label: 'Correo de acceso',
                    value: credentials.email,
                  ),
                  const SizedBox(height: 10),
                  _RecoveryDataTile(
                    icon: Icons.lock_outline,
                    label: 'Contrasena actual',
                    value: _obscureRecoveredPassword
                        ? '••••••••••••'
                        : credentials.password,
                    trailing: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscureRecoveredPassword =
                              !_obscureRecoveredPassword;
                        });
                      },
                      icon: Icon(
                        _obscureRecoveredPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(credentials == null ? 'Cancelar' : 'Cerrar'),
        ),
        FilledButton(
          onPressed: _isSubmitting
              ? null
              : credentials == null
              ? _submit
              : () => Navigator.of(context).pop(credentials),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  credentials == null
                      ? _resetMode
                            ? 'Actualizar acceso'
                            : 'Ver datos'
                      : 'Usar estos datos',
                ),
        ),
      ],
    );
  }
}

class _RecoveryDataTile extends StatelessWidget {
  const _RecoveryDataTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAF1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF5E6A82)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5E6A82),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF132238),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
