import 'package:flutter/material.dart';

import '../../../../core/utils/dominican_formatters.dart';

/// Monto monetario del resumen/REPORTES.
///
/// Centraliza tres reglas que antes se repetían por pantalla:
/// 1. Formato contable RD con separador de miles y dos decimales
///    (`1,000.00`, `25,350.50`, `1,250,000.00`) vía [formatRdCurrency].
/// 2. Conserva el prefijo `RD$ ` que ya usaba la tarjeta (no lo duplica).
/// 3. Nunca desborda la tarjeta: `FittedBox(scaleDown)` reduce sólo si hace
///    falta, sin ocultar ni truncar el valor.
class MoneyMetricText extends StatelessWidget {
  const MoneyMetricText({
    super.key,
    required this.amount,
    this.style,
    this.prefix = 'RD\$ ',
    this.textAlign = TextAlign.start,
  });

  /// Monto a mostrar. Acepta `num` para no forzar conversiones en los builders.
  final num amount;

  /// Estilo base; el tamaño se define en la tarjeta que lo usa.
  final TextStyle? style;

  /// Prefijo de moneda. Por defecto `RD$ ` (formato ya presente en la UI).
  final String prefix;

  final TextAlign textAlign;

  /// Texto final, sin build de UI: útil para tests y para exports.
  static String format(num amount, {String prefix = 'RD\$ '}) =>
      '$prefix${formatRdCurrency(amount)}';

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: textAlign == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: Text(
        format(amount, prefix: prefix),
        style: style,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
      ),
    );
  }
}
