import 'package:flutter/material.dart';

import '../../core/utils/dominican_formatters.dart';

/// ============================================================================
/// SISTEMA SOLARES - COMPONENTES COMPARTIDOS DEL LAYOUT COMPACTO (PWA/MOBILE)
/// ============================================================================
///
/// Replican 1:1 el lenguaje visual de la pantalla VENTAS (patrón maestro):
/// superficies blancas, tarjetas con borde fino y radio 12, tipografía clara,
/// chips suaves, iconos lineales y sombras discretas.
///
/// SOLO se usan en el layout compacto (< 1024 px). El escritorio no los usa.
class MobileUi {
  const MobileUi._();

  // ── Colores (identidad actual del sistema) ──
  static const Color primary = Color(0xFF123A5E);
  static const Color primarySoft = Color(0xFFEAF2FA);
  static const Color background = Color(0xFFF6F3ED);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF12243A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF8893AA);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFE4EAF2);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB54708);
  static const Color danger = Color(0xFFB42318);
  static const Color info = Color(0xFF1565C0);

  // ── Espaciado (igual que Ventas) ──
  static const double listPadding = 10;
  static const double pagePadding = 16;
  static const double rowGap = 8;

  // ── Radios ──
  static const double radiusCard = 8;
  static const double radiusField = 8;

  // ── Tipografía ──
  static const TextStyle itemTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w900,
    color: textPrimary,
  );
  static const TextStyle itemSubtitle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: textSecondary,
  );
  static const TextStyle itemMeta = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
  );
  static const TextStyle amount = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w900,
    color: textPrimary,
  );
  static const TextStyle amountSmall = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w900,
    color: textPrimary,
  );
  static const TextStyle amountLabel = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    color: textSecondary,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: textMuted,
    letterSpacing: 0.8,
  );
  static const TextStyle detailLabel = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: Color(0xFF667085),
  );
  static const TextStyle detailValue = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  /// Monto con separador de miles: `RD$750,000.00`.
  static String money(num value) => formatRdMoney(value);

  /// Fecha estable en español: `06/03/2026`.
  static String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  /// Moneda sin el prefijo `RD$` (para columnas donde el símbolo se repite).
  static String plainMoney(num value) => formatRdCurrency(value);
}

/// Decora las tarjetas del layout compacto (idéntico a la tarjeta de Ventas).
BoxDecoration mobileCardDecoration({Color color = MobileUi.surface}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(MobileUi.radiusCard),
    border: Border.all(color: MobileUi.border),
  );
}

/// Avatar circular con la inicial (idéntico al de la lista de Ventas).
class MobileInitialAvatar extends StatelessWidget {
  const MobileInitialAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.color = MobileUi.primary,
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Chip compacto de estado (idéntico a la píldora de la tarjeta de Ventas).
class MobileStatusChip extends StatelessWidget {
  const MobileStatusChip({
    super.key,
    required this.label,
    this.color = MobileUi.textSecondary,
    this.compact = true,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 10.5 : 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Fila de entidad del layout compacto (tarjeta ligera como la de Ventas).
class MobileEntityRow extends StatelessWidget {
  const MobileEntityRow({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.leading,
    this.trailing,
    this.menu,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? leading;
  final Widget? trailing;
  final Widget? menu;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MobileUi.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MobileUi.radiusCard),
        side: const BorderSide(color: MobileUi.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileUi.itemTitle,
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileUi.itemSubtitle,
                      ),
                    ],
                    if ((meta ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileUi.itemMeta,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (menu != null)
                menu!
              else if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: MobileUi.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menú `⋮` de acciones secundarias (idéntico al de las tarjetas de Ventas).
class MobileRowMenu<T> extends StatelessWidget {
  const MobileRowMenu({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip = 'Acciones',
  });

  final List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder;
  final ValueChanged<T> onSelected;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: MobileUi.textSecondary,
        ),
        onSelected: onSelected,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Carga inicial (idéntica al loader de Ventas).
class MobileLoadingView extends StatelessWidget {
  const MobileLoadingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

/// Estado vacío confirmado (mismo lenguaje que el de Ventas).
class MobileEmptyState extends StatelessWidget {
  const MobileEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 34, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if ((message ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message!.trim(),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Búsqueda sin resultados (idéntica a la de Ventas).
class MobileEmptySearchView extends StatelessWidget {
  const MobileEmptySearchView({
    super.key,
    required this.message,
    this.onClear,
    this.clearLabel = 'Limpiar búsqueda',
  });

  final String message;
  final VoidCallback? onClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (onClear != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  label: Text(clearLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Búsqueda fallida sin datos (recuperable, idéntica a la de Ventas).
class MobileSearchFailedView extends StatelessWidget {
  const MobileSearchFailedView({
    super.key,
    required this.title,
    this.message,
    required this.onRetry,
  });

  final String title;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if ((message ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!.trim(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso discreto de refresh fallido con datos visibles (igual que Ventas).
class MobileRefreshFailedBanner extends StatelessWidget {
  const MobileRefreshFailedBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF7E6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: Color(0xFF8A5A00),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'No pudimos actualizar. Mostrando datos guardados.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B4A00)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Barra fina de refresh en segundo plano (igual que Ventas).
class MobileRefreshingBar extends StatelessWidget {
  const MobileRefreshingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF2F6FB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Actualizando…',
            style: TextStyle(fontSize: 12, color: Color(0xFF4A5A72)),
          ),
        ],
      ),
    );
  }
}
