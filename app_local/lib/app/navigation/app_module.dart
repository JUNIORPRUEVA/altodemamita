import 'package:flutter/material.dart';

import '../../features/auth/domain/permission_model.dart';

enum AppModule {
  dashboard,
  sales,
  globalSearch,
  clients,
  lots,
  payments,
  installments,
  sellers,
  settings,
}

extension AppModuleX on AppModule {
  String get permissionKey {
    switch (this) {
      case AppModule.dashboard:
        return PermissionCatalog.dashboard;
      case AppModule.sales:
        return PermissionCatalog.sales;
      case AppModule.globalSearch:
        return PermissionCatalog.search;
      case AppModule.clients:
        return PermissionCatalog.clients;
      case AppModule.lots:
        return PermissionCatalog.lots;
      case AppModule.payments:
        return PermissionCatalog.payments;
      case AppModule.installments:
        return PermissionCatalog.installments;
      case AppModule.sellers:
        return PermissionCatalog.sellers;
      case AppModule.settings:
        return PermissionCatalog.settings;
    }
  }

  String get label {
    switch (this) {
      case AppModule.dashboard:
        return 'Resumen';
      case AppModule.sales:
        return 'Ventas';
      case AppModule.globalSearch:
        return 'Buscador';
      case AppModule.clients:
        return 'Clientes';
      case AppModule.lots:
        return 'Solares';
      case AppModule.payments:
        return 'Pagos';
      case AppModule.installments:
        return 'Cuotas';
      case AppModule.sellers:
        return 'Vendedores';
      case AppModule.settings:
        return 'Configuración';
    }
  }

  IconData get icon {
    switch (this) {
      case AppModule.dashboard:
        return Icons.space_dashboard_outlined;
      case AppModule.sales:
        return Icons.point_of_sale_outlined;
      case AppModule.globalSearch:
        return Icons.search_outlined;
      case AppModule.clients:
        return Icons.people_outline;
      case AppModule.lots:
        return Icons.map_outlined;
      case AppModule.payments:
        return Icons.payments_outlined;
      case AppModule.installments:
        return Icons.event_note_outlined;
      case AppModule.sellers:
        return Icons.storefront_outlined;
      case AppModule.settings:
        return Icons.settings_outlined;
    }
  }
}
