class Seller {
  const Seller({
    this.id,
    required this.name,
    required this.phone,
    required this.documentId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String phone;
  final String documentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Seller.empty() {
    final now = DateTime.now();
    return Seller(
      name: '',
      phone: '',
      documentId: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Seller.fromMap(Map<String, Object?> map) {
    return Seller(
      id: map['id'] as int?,
      name: map['nombre'] as String? ?? '',
      phone: map['telefono'] as String? ?? '',
      documentId: map['cedula'] as String? ?? '',
      createdAt: DateTime.parse(map['fecha_creacion'] as String),
      updatedAt: DateTime.parse(map['fecha_actualizacion'] as String),
    );
  }

  Seller copyWith({
    int? id,
    String? name,
    String? phone,
    String? documentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Seller(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      documentId: documentId ?? this.documentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'nombre': name,
      'telefono': phone,
      'cedula': documentId,
      'fecha_creacion': createdAt.toIso8601String(),
      'fecha_actualizacion': updatedAt.toIso8601String(),
    };
  }
}
