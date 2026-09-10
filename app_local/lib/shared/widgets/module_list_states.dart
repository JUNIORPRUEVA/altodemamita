import 'package:flutter/material.dart';

/// Barra de estado no bloqueante para listados cache-first.
///
/// - Mientras hay datos visibles y refresca en segundo plano: chip sutil
///   "Actualizando…".
/// - Si el ultimo refresh fallo con datos visibles: aviso discreto con
///   "Reintentar" (jamas pantalla fatal).
class ModuleStatusBanner extends StatelessWidget {
  const ModuleStatusBanner({
    super.key,
    required this.isRefreshing,
    required this.refreshFailed,
    this.onRetry,
    this.moduleLabel,
  });

  final bool isRefreshing;
  final bool refreshFailed;
  final VoidCallback? onRetry;
  final String? moduleLabel;

  @override
  Widget build(BuildContext context) {
    if (refreshFailed) {
      final label = moduleLabel == null || moduleLabel!.isEmpty
          ? ''
          : ' $moduleLabel';
      return Material(
        color: const Color(0xFFFFF7E6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 16,
                color: Color(0xFFB54708),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No pudimos actualizar$label. Mostrando los datos guardados.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A4A00)),
                ),
              ),
              if (onRetry != null)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onRetry,
                  child: const Text(
                    'Reintentar',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (isRefreshing) {
      return Container(
        color: const Color(0xFFF4F7FB),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            SizedBox(width: 8),
            Text(
              'Actualizando…',
              style: TextStyle(fontSize: 12, color: Color(0xFF5E6B87)),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Estado de carga inicial SIN datos (skeleton). Nunca "vacio".
class ModuleListLoadingView extends StatelessWidget {
  const ModuleListLoadingView({super.key, this.label = 'Cargando…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7494)),
          ),
        ],
      ),
    );
  }
}

/// Busqueda fallida sin resultados (recuperable, no fatal de modulo).
class ModuleSearchFailedView extends StatelessWidget {
  const ModuleSearchFailedView({
    super.key,
    required this.onRetry,
    this.message = 'No pudimos completar la búsqueda.',
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_outlined, size: 44, color: Color(0xFFB54708)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF5E5A52)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
