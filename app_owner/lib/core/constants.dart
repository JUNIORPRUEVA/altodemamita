const String baseUrl = String.fromEnvironment(
  'OWNER_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);
const String companyTenantKey = 'alto-dona-mamita-sistema-solares';
const Duration ownerRefreshInterval = Duration(seconds: 3);

enum OwnerModule {
  dashboard('Resumen', null),
  clients('Clientes', null),
  lots('Solares', null),
  sales('Ventas', null),
  installments('Cuotas', null),
  payments('Pagos', null),
  sellers('Vendedores', null);

  const OwnerModule(this.title, this.icon);

  final String title;
  final Object? icon; // IconData cannot be imported here; keep generic and map in UI
}
