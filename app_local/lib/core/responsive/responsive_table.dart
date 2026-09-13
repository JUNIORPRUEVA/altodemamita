import 'package:flutter/material.dart';

import 'app_breakpoints.dart';

/// Estrategia de presentación de registros tabulares.
enum ResponsiveTableStrategy {
  /// Tabla de columnas (layout de escritorio existente). No se altera.
  table,

  /// Tarjetas apiladas: cada registro se convierte en una tarjeta legible.
  cards,
}

/// Decide, de forma centralizada, si una colección de registros debe
/// renderizarse como tabla o como lista de tarjetas.
///
/// Regla acordada: una tabla ancha NO se reduce hasta quedar ilegible.
/// En móvil se convierte en tarjetas; en tableta/escritorio se mantiene la
/// tabla existente.
class ResponsiveTableSwitch extends StatelessWidget {
  const ResponsiveTableSwitch({
    super.key,
    required this.table,
    required this.cards,
    this.forceStrategy,
    this.minTableWidth,
  });

  /// Tabla actual (escritorio). Se devuelve sin modificar.
  final Widget table;

  /// Lista de tarjetas equivalente para pantallas pequeñas.
  final Widget cards;

  /// Fuerza una estrategia concreta (útil en pruebas o pantallas puntuales).
  final ResponsiveTableStrategy? forceStrategy;

  /// Ancho mínimo necesario para que la tabla sea legible. Si el ancho real
  /// es menor, se usan tarjetas aunque la clasificación sea de escritorio.
  final double? minTableWidth;

  static ResponsiveTableStrategy strategyFor(
    BuildContext context, {
    double minimumTableWidth = AppBreakpoints.tabletMax,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= minimumTableWidth
        ? ResponsiveTableStrategy.table
        : ResponsiveTableStrategy.cards;
  }

  @override
  Widget build(BuildContext context) {
    final requested = forceStrategy ??
        strategyFor(context, minimumTableWidth: minTableWidth ?? tabletThreshold);

    final effective = requested == ResponsiveTableStrategy.table &&
            minTableWidth != null &&
            MediaQuery.sizeOf(context).width < minTableWidth!
        ? ResponsiveTableStrategy.cards
        : requested;

    return effective == ResponsiveTableStrategy.table ? table : cards;
  }

  static const double tabletThreshold = AppBreakpoints.tabletMax;
}

/// Tarjeta de registro reutilizable para la estrategia móvil.
///
/// Presenta primero la información esencial y conserva un punto de entrada
/// para acciones secundarias (normalmente un menú `⋮`).
class ResponsiveRecordCard extends StatelessWidget {
  const ResponsiveRecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.fields = const [],
    this.trailing,
    this.onTap,
    this.actions = const [],
    this.highlighted = false,
  });

  /// Nombre principal del registro (p. ej. el cliente).
  final String title;

  /// Línea secundaria corta (p. ej. identificación).
  final String? subtitle;

  /// Pares etiqueta/valor mostrados como filas etiquetadas.
  final List<ResponsiveRecordField> fields;

  /// Elemento de estado a la derecha (chip, badge...).
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Acciones secundarias mostradas al final de la tarjeta.
  final List<Widget> actions;

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: highlighted
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final field in fields) field,
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila etiqueta/valor de [ResponsiveRecordCard].
///
/// Garantiza que el valor nunca se corte: la etiqueta es fija y el valor se
/// expande y ajusta en varias líneas si es necesario.
class ResponsiveRecordField extends StatelessWidget {
  const ResponsiveRecordField({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 96,
    this.valueBuilder,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final double labelWidth;
  final WidgetBuilder? valueBuilder;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = (emphasis
            ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
            : theme.textTheme.bodyMedium)
        ?.copyWith(color: theme.colorScheme.onSurface);

    if (valueBuilder != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label, style: labelStyle),
            ),
            Expanded(child: valueBuilder!(context)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: labelStyle),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
