import 'package:flutter/material.dart';

import '../../../../core/utils/dominican_formatters.dart';

/// Fila inferior de la tarjeta móvil de ventas: solar/fecha + montos + chevron.
///
/// Regla de presentación (acordada con el cliente):
/// - Los montos NUNCA se recortan con puntos suspensivos.
/// - Se miden antes de pintarse para reservar el ancho exacto que necesitan.
/// - Si "Precio" y "Pendiente" no caben completos, se muestra únicamente el
///   pendiente, que es el dato operativo más importante.
class SaleMobileAmountsRow extends StatelessWidget {
  const SaleMobileAmountsRow({
    super.key,
    required this.metaLabel,
    required this.price,
    required this.pending,
  });

  /// Código de solar + fecha de venta.
  final String metaLabel;

  final double price;
  final double pending;

  /// Separación horizontal entre bloques.
  static const double gap = 8;

  /// Ancho reservado al chevron de navegación.
  static const double chevronWidth = 20;

  /// Ancho mínimo reservado al código de solar + fecha.
  static const double minMetaWidth = 84;

  static const TextStyle labelStyle = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w600,
    color: Color(0xFF6B7A90),
  );

  static const TextStyle valueStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: Color(0xFF1F2937),
  );

  static const TextStyle metaStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    color: Color(0xFF6B7A90),
  );

  /// Ancho real que necesita un monto con su etiqueta, sin recortes.
  static double amountWidth(String label, String value) {
    final labelWidth = measureTextWidth(label, labelStyle);
    final valueWidth = measureTextWidth(value, valueStyle);
    return (labelWidth > valueWidth ? labelWidth : valueWidth) + 1;
  }

  /// `true` cuando "Precio" y "Pendiente" caben completos en [rowWidth].
  static bool fitsBoth({
    required double rowWidth,
    required double priceWidth,
    required double pendingWidth,
  }) {
    final available =
        rowWidth - chevronWidth - gap - minMetaWidth;
    return priceWidth + gap + pendingWidth <= available;
  }

  static double measureTextWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final priceText = formatRdMoney(price);
    final pendingText = formatRdMoney(pending);

    return LayoutBuilder(
      builder: (context, constraints) {
        final priceWidth = amountWidth('Precio', priceText);
        final pendingWidth = amountWidth('Pend.', pendingText);
        final showPrice = fitsBoth(
          rowWidth: constraints.maxWidth,
          priceWidth: priceWidth,
          pendingWidth: pendingWidth,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                metaLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle,
              ),
            ),
            const SizedBox(width: gap),
            if (showPrice) ...[
              _Amount(label: 'Precio', value: priceText, width: priceWidth),
              const SizedBox(width: gap),
            ],
            _Amount(label: 'Pend.', value: pendingText, width: pendingWidth),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ],
        );
      },
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;

  /// Ancho exacto medido para que el monto se vea completo.
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `scaleDown` evita cualquier recorte si el usuario agranda la
          // tipografía del sistema.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: SaleMobileAmountsRow.labelStyle,
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: SaleMobileAmountsRow.valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}
