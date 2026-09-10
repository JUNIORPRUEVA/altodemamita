/// Modelo de permisos y roles
class Permission {
  const Permission({
    this.id,
    required this.usuarioId,
    required this.modulo,
    required this.acciones,
    required this.fechaCreacion,
  });

  final int? id;
  final int usuarioId;
  final String modulo; // 'clientes', 'solares', 'ventas', 'cuotas', 'pagos', 'busqueda', 'configuracion', 'backup'
  final String acciones; // JSON string con array de acciones permitidas
  final DateTime fechaCreacion;

  static const List<String> availableModules = [
    'clientes',
    'solares',
    'ventas',
    'cuotas',
    'pagos',
    'busqueda',
    'configuracion',
    'backup',
  ];

  static const List<String> availableActions = [
    'ver',
    'crear',
    'editar',
    'eliminar',
    'anular',
    'imprimir',
    'registrar_pagos',
  ];

  /// Acciones ofrecidas por modulo. `anular` solo aplica a Pagos: es la
  /// operacion financiera segura (no existe borrado fisico de pagos).
  static const Map<String, List<String>> _actionsByModule = {
    'pagos': ['ver', 'crear', 'editar', 'anular'],
    'ventas': ['ver', 'crear', 'editar', 'eliminar'],
    'cuotas': ['ver', 'crear', 'editar'],
    'clientes': ['ver', 'crear', 'editar', 'eliminar'],
    'solares': ['ver', 'crear', 'editar', 'eliminar'],
  };

  static List<String> actionsFor(String module) {
    return _actionsByModule[module] ?? availableActions;
  }

  factory Permission.empty({required int usuarioId}) {
    return Permission(
      usuarioId: usuarioId,
      modulo: 'clientes',
      acciones: '["ver"]',
      fechaCreacion: DateTime.now(),
    );
  }

  factory Permission.fromMap(Map<String, Object?> map) {
    return Permission(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int? ?? 0,
      modulo: map['modulo'] as String? ?? '',
      acciones: map['acciones'] as String? ?? '[]',
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'usuario_id': usuarioId,
      'modulo': modulo,
      'acciones': acciones,
      'fecha_creacion': fechaCreacion.toIso8601String(),
    };
  }

  List<String> getActionsList() {
    try {
      final decoded = acciones.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').split(',');
      return decoded.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }

  bool hasAction(String action) {
    return getActionsList().contains(action);
  }

  Permission copyWith({
    int? id,
    int? usuarioId,
    String? modulo,
    String? acciones,
    DateTime? fechaCreacion,
  }) {
    return Permission(
      id: id ?? this.id,
      usuarioId: usuarioId ?? this.usuarioId,
      modulo: modulo ?? this.modulo,
      acciones: acciones ?? this.acciones,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
    );
  }
}
