enum PermissionAction { read, create, update, delete, cancel }

extension PermissionActionX on PermissionAction {
  String get key {
    switch (this) {
      case PermissionAction.read:
        return 'read';
      case PermissionAction.create:
        return 'create';
      case PermissionAction.update:
        return 'update';
      case PermissionAction.delete:
        return 'delete';
      case PermissionAction.cancel:
        return 'anular';
    }
  }

  String get label {
    switch (this) {
      case PermissionAction.read:
        return 'Ver';
      case PermissionAction.create:
        return 'Crear';
      case PermissionAction.update:
        return 'Editar';
      case PermissionAction.delete:
        return 'Eliminar';
      case PermissionAction.cancel:
        return 'Anular pagos';
    }
  }

  static PermissionAction fromLegacy(String action) {
    switch (action.trim().toLowerCase()) {
      case 'ver':
      case 'read':
        return PermissionAction.read;
      case 'crear':
      case 'create':
        return PermissionAction.create;
      case 'editar':
      case 'update':
        return PermissionAction.update;
      case 'eliminar':
      case 'delete':
        return PermissionAction.delete;
      case 'anular':
      case 'cancelar':
      case 'cancel':
        return PermissionAction.cancel;
      default:
        throw ArgumentError('Accion no soportada: $action');
    }
  }
}

class PermissionModuleDefinition {
  const PermissionModuleDefinition({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;
}

class PermissionCatalog {
  PermissionCatalog._();

  static const String dashboard = 'resumen';
  static const String sales = 'ventas';
  static const String payments = 'pagos';
  static const String installments = 'cuotas';
  static const String clients = 'clientes';
  static const String sellers = 'vendedores';
  static const String settings = 'configuracion';
  static const String lots = 'solares';
  static const String search = 'busqueda';

  static const List<PermissionModuleDefinition> modules = [
    PermissionModuleDefinition(
      key: dashboard,
      label: 'Resumen',
      description: 'Panel general y metricas operativas',
    ),
    PermissionModuleDefinition(
      key: sales,
      label: 'Ventas',
      description: 'Gestion de ventas y operaciones comerciales',
    ),
    PermissionModuleDefinition(
      key: payments,
      label: 'Pagos',
      description: 'Registro de pagos y recibos',
    ),
    PermissionModuleDefinition(
      key: installments,
      label: 'Cuotas',
      description: 'Seguimiento de cuotas y vencimientos',
    ),
    PermissionModuleDefinition(
      key: clients,
      label: 'Clientes',
      description: 'Mantenimiento del padron de clientes',
    ),
    PermissionModuleDefinition(
      key: sellers,
      label: 'Vendedores',
      description: 'Gestion de vendedores y asesores',
    ),
    PermissionModuleDefinition(
      key: settings,
      label: 'Configuracion',
      description: 'Parametros generales y administracion',
    ),
    PermissionModuleDefinition(
      key: lots,
      label: 'Solares',
      description: 'Inventario y disponibilidad de solares',
    ),
    PermissionModuleDefinition(
      key: search,
      label: 'Buscador',
      description: 'Consulta global rapida del sistema',
    ),
  ];

  static PermissionModuleDefinition byKey(String key) {
    for (final module in modules) {
      if (module.key == key) {
        return module;
      }
    }

    return PermissionModuleDefinition(
      key: key,
      label: key,
      description: key,
    );
  }
}

class PermissionModel {
  const PermissionModel({
    required this.module,
    this.read = false,
    this.create = false,
    this.update = false,
    this.delete = false,
    this.cancel = false,
  });

  final String module;
  final bool read;
  final bool create;
  final bool update;
  final bool delete;

  /// Permiso granular para anular pagos. Es independiente de crear, ver o
  /// editar pagos: el backend lo valida por separado.
  final bool cancel;

  factory PermissionModel.empty(String module) {
    return PermissionModel(module: module);
  }

  factory PermissionModel.full(String module) {
    return PermissionModel(
      module: module,
      read: true,
      create: true,
      update: true,
      delete: true,
      cancel: true,
    );
  }

  factory PermissionModel.fromLegacy({
    required String module,
    required Iterable<String> actions,
  }) {
    final normalized = <PermissionAction>{};
    for (final action in actions) {
      normalized.add(PermissionActionX.fromLegacy(action));
    }

    return PermissionModel(
      module: module,
      read: normalized.contains(PermissionAction.read),
      create: normalized.contains(PermissionAction.create),
      update: normalized.contains(PermissionAction.update),
      delete: normalized.contains(PermissionAction.delete),
      cancel: normalized.contains(PermissionAction.cancel),
    );
  }

  bool allows(PermissionAction action) {
    switch (action) {
      case PermissionAction.read:
        return read;
      case PermissionAction.create:
        return create;
      case PermissionAction.update:
        return update;
      case PermissionAction.delete:
        return delete;
      case PermissionAction.cancel:
        return cancel;
    }
  }

  List<String> toLegacyActions() {
    final actions = <String>[];
    if (read) {
      actions.add('ver');
    }
    if (create) {
      actions.add('crear');
    }
    if (update) {
      actions.add('editar');
    }
    if (delete) {
      actions.add('eliminar');
    }
    if (cancel) {
      actions.add('anular');
    }
    return actions;
  }

  PermissionModel copyWith({
    String? module,
    bool? read,
    bool? create,
    bool? update,
    bool? delete,
    bool? cancel,
  }) {
    return PermissionModel(
      module: module ?? this.module,
      read: read ?? this.read,
      create: create ?? this.create,
      update: update ?? this.update,
      delete: delete ?? this.delete,
      cancel: cancel ?? this.cancel,
    );
  }
}