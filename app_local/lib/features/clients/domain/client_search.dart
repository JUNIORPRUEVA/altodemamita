import 'client.dart';

/// Normalizacion de busqueda de clientes.
///
/// Problema real corregido aqui: la busqueda de clientes dependia de
/// `LIKE` en SQLite (que solo ignora mayusculas ASCII) y de `contains`
/// insensible en PostgreSQL (que no pliega acentos). Consecuencia:
/// "jose" NO encontraba a "Jose", "pena" NO encontraba a "Pena" con enie
/// y una consulta de dos palabras no casaba si no eran contiguas.
///
/// La misma normalizacion debe aplicarse en desktop (cache/offline) y en el
/// backend (nube) para que el resultado de una busqueda no cambie segun la
/// disponibilidad de red.
const Map<String, String> _accentFoldMap = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Minusculas, sin acentos, sin espacios repetidos y recortado.
String foldClientSearchText(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (final character in value.toLowerCase().split('')) {
    buffer.write(_accentFoldMap[character] ?? character);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Palabras significativas de la consulta (maximo 6).
List<String> clientSearchTokens(String? query) {
  final folded = foldClientSearchText(query);
  if (folded.isEmpty) {
    return const <String>[];
  }
  return folded
      .split(' ')
      .where((token) => token.isNotEmpty)
      .take(6)
      .toList(growable: false);
}

/// `true` si el cliente coincide con la consulta.
///
/// Reglas (identicas a la busqueda autoritativa en la nube):
/// - Todas las palabras deben aparecer en nombre, cedula, telefono o direccion.
/// - El orden de las palabras no importa.
/// - Si la consulta aporta al menos 2 digitos, tambien se compara contra
///   cedula/telefono sin separadores (809-555-1234 = 8095551234).
bool clientMatchesSearch(Client client, String? query) {
  final tokens = clientSearchTokens(query);
  final digits = (query ?? '').replaceAll(RegExp(r'\D+'), '');
  if (tokens.isEmpty && digits.length < 2) {
    return true;
  }

  final haystack = foldClientSearchText(
    <String>[
      client.fullName,
      client.documentId,
      client.phone ?? '',
      client.address ?? '',
    ].join(' '),
  );

  final tokensMatch = tokens.every(haystack.contains);
  if (tokensMatch && tokens.isNotEmpty) {
    return true;
  }

  if (digits.length >= 2) {
    final digitsHaystack = <String>[client.documentId, client.phone ?? '']
        .join(' ')
        .replaceAll(RegExp(r'\D+'), '');
    return digitsHaystack.contains(digits);
  }

  return false;
}
