/// Utilidades canonicas para el codigo de solar (manzana + numero).
///
/// El backend puede almacenar la manzana ya con el prefijo (`M-N`, `M-Ñ`),
/// mientras que instalaciones legacy guardan solo la manzana (`N`, `Ñ`).
/// Sin normalizar ese prefijo el codigo mostrado se duplicaba
/// (`MM-N-S493`), lo que confundia al operador y rompia la busqueda por el
/// codigo que el cliente conoce.
///
/// Este helper es la UNICA fuente de verdad para:
///  * el codigo mostrado (`M-N-S493`),
///  * el codigo usado en busqueda (tolerante a `493`, `M-N 493`, `M-N-S493`,
///    `MN-S493`, espacios, guiones y mayusculas/minusculas),
///  * mantener la distincion real entre `N` y `Ñ` (nunca se pliegan acentos).
class LotCode {
  const LotCode._();

  /// Manzana sin el prefijo `M`/`M-`.
  ///
  /// `M-N` -> `N`, `M-Ñ` -> `Ñ`, `M` -> ``, `N` -> `N`, `A` -> `A`.
  static String canonicalBlock(String blockNumber) {
    var block = blockNumber.trim().toUpperCase();
    if (block.startsWith('M-') || block.startsWith('M ')) {
      block = block.substring(2).trim();
    } else if (block == 'M') {
      block = '';
    }
    return block;
  }

  /// Codigo canonico mostrado al operador: `M` + manzana + `-S` + numero.
  ///
  /// Nunca duplica el prefijo: `('M-N','493')` y `('N','493')` producen
  /// ambos `MN-S493`.
  static String canonicalCode({
    required String blockNumber,
    required String lotNumber,
  }) {
    final block = canonicalBlock(blockNumber);
    final number = lotNumber.trim();
    return 'M$block-S$number';
  }

  /// Compacta un texto para comparacion tolerante.
  ///
  /// Mayusculas, sin separadores y conservando `Ñ` (`M-N 493` -> `MN493`).
  static String compact(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toUpperCase().runes) {
      final char = String.fromCharCode(rune);
      if (char == 'Ñ') {
        buffer.write('Ñ');
      } else if (_isAsciiAlphanumeric(char)) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static bool _isAsciiAlphanumeric(String char) {
    final code = char.codeUnitAt(0);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isUpper = code >= 0x41 && code <= 0x5A;
    return isDigit || isUpper;
  }

  /// `true` si [query] puede identificar al solar.
  ///
  /// La coincidencia es por tokens: todos los tokens tecleados deben aparecer
  /// en alguna de las representaciones del solar (codigo canonico, manzana,
  /// numero, area o precios). Una busqueda por numero puede devolver varios
  /// solares de manzanas distintas: el llamador debe exigir seleccion
  /// explicita y NUNCA auto-seleccionar.
  static bool matchesQuery({
    required String blockNumber,
    required String lotNumber,
    required String query,
    double? area,
    double? unitPricePerSquareMeter,
    double? totalPrice,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return true;
    }

    final tokens = trimmed
        .split(RegExp(r'[^0-9A-Za-zÑñ]+'))
        .map(compact)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return true;
    }

    final haystacks = <String>[
      compact('$blockNumber$lotNumber'),
      compact(canonicalCode(blockNumber: blockNumber, lotNumber: lotNumber)),
      compact(canonicalBlock(blockNumber)),
      compact(lotNumber),
      if (area != null) compact(area.toStringAsFixed(2)),
      if (unitPricePerSquareMeter != null)
        compact(unitPricePerSquareMeter.toStringAsFixed(2)),
      if (totalPrice != null) compact(totalPrice.toStringAsFixed(2)),
    ];

    final haystack = haystacks.join('|');
    return tokens.every(haystack.contains);
  }
}
