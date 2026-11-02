import '../../../shared/widgets/entity_admin_dialog.dart';
import '../domain/client.dart';

/// FASE 04B — campos del diálogo administrativo de cliente.
///
/// `name` es OBLIGATORIO en el backend: `validateClientIdentity` rechaza con
/// `INVALID_CLIENT_NAME` cualquier nombre de menos de 3 caracteres, así que
/// omitir el campo hacía que toda edición de identidad devolviera 400.
List<EntityAdminField> buildClientIdentityFields(Client client) {
  return [
    EntityAdminField(
      key: 'name',
      label: 'Nombre',
      initial: client.fullName,
    ),
    EntityAdminField(
      key: 'document',
      label: 'Cédula / documento',
      initial: client.documentId,
    ),
    EntityAdminField(
      key: 'phone',
      label: 'Teléfono',
      initial: client.phone ?? '',
    ),
    EntityAdminField(
      key: 'address',
      label: 'Dirección',
      initial: client.address ?? '',
    ),
  ];
}
