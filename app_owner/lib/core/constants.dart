/// URL base del backend para la app Owner.
///
/// Desarrollo (emulador Android):
///   flutter run --dart-define=OWNER_API_BASE_URL=http://10.0.2.2:3000
///
/// Producción:
///   flutter run --dart-define=OWNER_API_BASE_URL=https://altodemanita-backend.onqyr1.easypanel.host
///
const String baseUrl = String.fromEnvironment(
  'OWNER_API_BASE_URL',
  defaultValue: 'https://altodemanita-backend.onqyr1.easypanel.host',
);
const String companyTenantKey = 'alto-dona-mamita-sistema-solares';
const Duration ownerRefreshInterval = Duration(seconds: 20);

enum OwnerModule {
  dashboard('Resumen', null),
  clients('Clientes', null),
  lots('Solares', null),
  sales('Ventas', null),
  installments('Cuotas', null),
  payments('Pagos', null),
  sellers('Vendedores', null),
  documentation('Documentación', null);

  const OwnerModule(this.title, this.icon);

  final String title;
  // IconData cannot be imported here; keep generic and map in UI.
  final Object? icon;
}
