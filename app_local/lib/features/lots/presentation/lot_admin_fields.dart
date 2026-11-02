import '../../../shared/widgets/entity_admin_dialog.dart';
import '../domain/lot.dart';

/// FASE 04B — campos del diálogo administrativo de solar.
///
/// Contrato crítico: `price` es **precio por metro cuadrado**, que es lo que
/// persiste el backend en `Lot.price` (misma semántica que `lotDto.price` /
/// `pricePerSquareMeter` y que el alta de solares). Enviar aquí el precio
/// TOTAL corrompe el catálogo: un solar de 200 m² a 3,000/m² (total 600,000)
/// quedaba guardado como 600,000 por m² y su total pasaba a 120,000,000.
///
/// El precio total sigue visible en `summaryLines` del diálogo, pero no se
/// edita como si fuese el unitario.
List<EntityAdminField> buildLotAdminFields(Lot lot, String action) {
  if (action != 'update_details' && action != 'update_status') {
    return const <EntityAdminField>[];
  }

  return [
    if (action == 'update_details') ...[
      EntityAdminField(
        key: 'block',
        label: 'Manzana',
        initial: lot.blockNumber,
      ),
      EntityAdminField(
        key: 'number',
        label: 'Solar',
        initial: lot.lotNumber,
      ),
      EntityAdminField(
        key: 'area',
        label: 'Área (m²)',
        initial: lot.area.toStringAsFixed(2),
        numeric: true,
      ),
      EntityAdminField(
        key: 'price',
        label: 'Precio por metro cuadrado',
        initial: lot.pricePerSquareMeter.toStringAsFixed(2),
        numeric: true,
      ),
    ],
    if (action == 'update_status')
      EntityAdminField(
        key: 'status',
        label: 'Estado: disponible, reservado, bloqueado, mantenimiento',
        initial: lot.status,
      ),
  ];
}

/// Resumen de impacto mostrado antes de aplicar el cambio.
///
/// Incluye explícitamente el precio por m² y el total para que el operador
/// distinga cuál está editando.
List<String> buildLotAdminSummary(Lot lot) {
  return [
    lot.displayCode,
    'Estado actual: ${lot.status}',
    'Área: ${lot.area.toStringAsFixed(2)} m²',
    'Precio por m²: ${lot.pricePerSquareMeter.toStringAsFixed(2)}',
    'Precio total: ${lot.totalPrice.toStringAsFixed(2)}',
  ];
}
