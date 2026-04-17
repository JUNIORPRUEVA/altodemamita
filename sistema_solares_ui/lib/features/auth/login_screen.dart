import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/auth/auth_controller.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorText;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authController = context.read<AuthController>();
    setState(() {
      _errorText = null;
    });
    try {
      await authController.signIn(
        identifier: _identifierController.text,
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      context.go('/dashboard');
    } on ApiException catch (error) {
      setState(() {
        _errorText = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final errorMessage = _errorText ?? authController.errorMessage;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF102C46), Color(0xFF16324F), Color(0xFF214A69)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 760;
            final maxCardWidth = isMobile ? 440.0 : 520.0;
            final horizontalPadding = isMobile ? 20.0 : 32.0;
            final cardPadding = isMobile
                ? const EdgeInsets.fromLTRB(22, 26, 22, 22)
                : const EdgeInsets.fromLTRB(34, 36, 34, 30);

            return Stack(
              children: [
                const Positioned(
                  top: -120,
                  left: -40,
                  child: _BackgroundOrb(
                    size: 280,
                    colors: [Color(0x3DE7F2FF), Color(0x00E7F2FF)],
                  ),
                ),
                const Positioned(
                  right: -80,
                  bottom: -120,
                  child: _BackgroundOrb(
                    size: 360,
                    colors: [Color(0x262CC06B), Color(0x002CC06B)],
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxCardWidth),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F6F1),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0xFFE6DECF)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x28000000),
                                blurRadius: 42,
                                offset: Offset(0, 22),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: cardPadding,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _BrandMark(),
                                  SizedBox(height: isMobile ? 20 : 24),
                                  Text(
                                    'Iniciar sesion',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      color: const Color(0xFF16324F),
                                      fontSize: isMobile ? 30 : 34,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 22 : 26),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: errorMessage == null
                                        ? const SizedBox.shrink()
                                        : Container(
                                            key: ValueKey<String>(errorMessage),
                                            margin: const EdgeInsets.only(bottom: 18),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFEEF1),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: const Color(0xFFF2BCC5),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.error_outline,
                                                  size: 18,
                                                  color: Color(0xFFB42318),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    errorMessage,
                                                    style: const TextStyle(
                                                      color: Color(0xFF8F2436),
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                  ),
                                  _LoginField(
                                    controller: _identifierController,
                                    hintText: 'Correo o usuario',
                                    icon: Icons.person_outline,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) {},
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Ingresa tu correo o usuario';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _LoginField(
                                    controller: _passwordController,
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
                                        color: const Color(0xFF6A7684),
                                        size: 20,
                                      ),
                                    ),
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => authController.isBusy ? null : _submit(),
                                    validator: (value) {
                                      if ((value ?? '').isEmpty) {
                                        return 'Ingresa tu contrasena';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: authController.isBusy ? null : _submit,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(56),
                                      backgroundColor: const Color(0xFF16324F),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: authController.isBusy
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BackgroundOrb extends StatelessWidget {
  const _BackgroundOrb({
    required this.size,
    required this.colors,
  });

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF214A69), Color(0xFF16324F)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1E16324F),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.wb_sunny_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Sistema Solares',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF16324F),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.validator,
    this.obscureText = false,
    this.suffixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final String? Function(String?) validator;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        color: Color(0xFF173450),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF8B97A7)),
        prefixIcon: Icon(icon, color: const Color(0xFF6A7684)),
        filled: true,
        fillColor: const Color(0xFFFFFCF7),
        errorStyle: const TextStyle(color: Color(0xFFB42318)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD8D1C4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF16324F), width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE05353)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE05353), width: 1.2),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
