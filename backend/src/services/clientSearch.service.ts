/**
 * Normalizacion de busqueda de clientes (nube).
 *
 * Debe producir EXACTAMENTE el mismo resultado que la normalizacion del
 * desktop (`app_local/lib/features/clients/domain/client_search.dart`):
 * minusculas, sin acentos, palabras separadas y comparacion por TODAS las
 * palabras en cualquier orden.
 *
 * Motivo: PostgreSQL `mode: 'insensitive'` pliega mayusculas pero NO acentos,
 * y `contains` exige la subcadena contigua. Con clientes dominicanos reales
 * ("Jose Ramon Pena", "Nunez", "Iluminada Rodriguez") eso hacia que buscar
 * "jose pena" devolviera cero resultados.
 */

const accentFrom = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const accentTo = 'aaaaaeeeeiiiiooooouuuunc';

/** Minusculas, sin acentos, sin espacios repetidos y recortado. */
export function foldSearchText(value: string | null | undefined): string {
  if (!value) return '';
  let out = '';
  for (const character of value.toLowerCase()) {
    const index = accentFrom.indexOf(character);
    out += index >= 0 ? accentTo[index] : character;
  }
  return out.replace(/\s+/g, ' ').trim();
}

/** Palabras significativas de la consulta (maximo 6). */
export function searchTokens(value: string | null | undefined): string[] {
  const folded = foldSearchText(value);
  if (!folded) return [];
  return folded.split(' ').filter((token) => token.length > 0).slice(0, 6);
}

/** Solo digitos (cedula/telefono sin separadores). */
export function searchDigits(value: string | null | undefined): string {
  return value?.replace(/\D+/g, '') ?? '';
}

/** Expresion SQL que pliega un campo igual que `foldSearchText`. */
export function foldedColumnSql(column: string): string {
  return `translate(lower(coalesce(${column}, '')), '${accentFrom}', '${accentTo}')`;
}
