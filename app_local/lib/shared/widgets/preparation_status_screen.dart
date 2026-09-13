import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PreparationStatusScreen extends StatelessWidget {
  const PreparationStatusScreen({
    super.key,
    this.status = PreparationStatus.loading,
    this.onRetry,
    this.onClose,
  });

  final PreparationStatus status;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  static const title = 'Preparando Sistema Solares';
  static const windowsMessage =
      'Estamos preparando la aplicación en esta PC.\n'
      'Esto puede tardar unos segundos.';
  static const deviceMessage =
      'Estamos preparando la aplicación en este dispositivo.\n'
      'Esto puede tardar unos segundos.';
  static const loadingText = 'Cargando información...';
  static const organizingText = 'Organizando tus datos...';
  static const readyText = 'Todo listo. Iniciando...';
  static const errorTitle = 'No pudimos terminar la preparación.';
  static const errorMessage = 'Verifica tu conexión e inténtalo nuevamente.';

  static bool get isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    final isError = status == PreparationStatus.error;
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = size.width < 420 ? 20.0 : 28.0;
    final cardPadding = size.width < 420 ? 22.0 : 30.0;
    final iconColor = isError
        ? const Color(0xFFB3261E)
        : const Color(0xFF0D5EAF);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 24,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(cardPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _BrandMark(color: iconColor, isError: isError),
                            const SizedBox(height: 22),
                            Text(
                              isError ? errorTitle : title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFF102033),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isError
                                  ? errorMessage
                                  : isWindowsDesktop
                                  ? windowsMessage
                                  : deviceMessage,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: const Color(0xFF536174),
                                    height: 1.35,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            if (isError)
                              _ErrorActions(onRetry: onRetry, onClose: onClose)
                            else ...[
                              const SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                status.label,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF1F4B7A),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ],
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

enum PreparationStatus {
  loading(PreparationStatusScreen.loadingText),
  organizing(PreparationStatusScreen.organizingText),
  ready(PreparationStatusScreen.readyText),
  error('');

  const PreparationStatus(this.label);

  final String label;
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.color, required this.isError});

  final Color color;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isError ? Icons.wifi_off_rounded : Icons.business_rounded,
        color: color,
        size: 30,
      ),
    );
  }
}

class _ErrorActions extends StatelessWidget {
  const _ErrorActions({required this.onRetry, required this.onClose});

  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
        if (onClose != null)
          OutlinedButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cerrar'),
          ),
      ],
    );
  }
}
