/// URL base del backend para la app Owner.
///
/// Desarrollo (emulador Android):
///   flutter run --dart-define=OWNER_API_BASE_URL=http://10.0.2.2:3000
///
/// Producción:
///   flutter build apk --release --dart-define=OWNER_API_BASE_URL=https://altomamita-backend.gcdndd.easypanel.host --dart-define=OWNER_ACCESS_TOKEN=TOKEN
///
const String baseUrl = String.fromEnvironment(
  'OWNER_API_BASE_URL',
  defaultValue: 'https://altomamita-backend.gcdndd.easypanel.host',
);
const String ownerAccessToken = String.fromEnvironment('OWNER_ACCESS_TOKEN');
const String ownerUserName = String.fromEnvironment(
  'OWNER_USER_NAME',
  defaultValue: 'Dueño',
);
const String ownerUserEmail = String.fromEnvironment('OWNER_USER_EMAIL');
const String companyTenantKey = 'alto-dona-mamita-sistema-solares';
const Duration ownerRefreshInterval = Duration(seconds: 20);

const List<OwnerModule> customerVisibleModules = [
  OwnerModule.dashboard,
  OwnerModule.sales,
  OwnerModule.lots,
  OwnerModule.installments,
  OwnerModule.payments,
  OwnerModule.documentation,
];

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
