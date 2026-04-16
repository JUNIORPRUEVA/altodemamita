import '../../../models/sync/sync_status.dart';

class Client {
  const Client({
    this.id,
    this.syncId,
    this.version = 1,
    required this.fullName,
    required this.documentId,
    this.phone,
    this.address,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.synced,
  });

  final int? id;
  final String? syncId;
  final int version;
  final String fullName;
  final String documentId;
  final String? phone;
  final String? address;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  factory Client.empty() {
    final now = DateTime.now();
    return Client(fullName: '', documentId: '', createdAt: now, updatedAt: now);
  }

  factory Client.fromMap(Map<String, Object?> map) {
    return Client(
      id: map['id'] as int?,
      syncId: (map['sync_id'] as String?)?.trim(),
      version: _readInt(map['version']) ?? 1,
      fullName: map['nombre'] as String? ?? '',
      documentId: map['cedula'] as String? ?? '',
      phone: map['telefono'] as String?,
      address: map['direccion'] as String?,
      createdAt: DateTime.parse(map['fecha_creacion'] as String),
      updatedAt: DateTime.parse(map['fecha_actualizacion'] as String),
      deletedAt: _readNullableDate(map['deleted_at']),
      syncStatus: SyncStatus.fromStorage(map['sync_status']),
    );
  }

  factory Client.fromSyncMap(Map<String, dynamic> map) {
    return Client(
      id: _readInt(map['id']),
      syncId: (map['sync_id'] as String?)?.trim(),
      version: _readInt(map['version']) ?? 1,
      fullName: map['full_name'] as String? ?? '',
      documentId: map['document_id'] as String? ?? '',
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: _readNullableDate(map['deleted_at']),
      syncStatus: SyncStatus.fromStorage(map['sync_status']),
    );
  }

  Client copyWith({
    int? id,
    String? syncId,
    int? version,
    String? fullName,
    String? documentId,
    String? phone,
    String? address,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    SyncStatus? syncStatus,
  }) {
    return Client(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      version: version ?? this.version,
      fullName: fullName ?? this.fullName,
      documentId: documentId ?? this.documentId,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'sync_id': syncId,
      'version': version,
      'nombre': fullName,
      'cedula': documentId,
      'telefono': phone,
      'direccion': address,
      'fecha_creacion': createdAt.toIso8601String(),
      'fecha_actualizacion': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'sync_status': syncStatus.storageValue,
    };
  }

  Map<String, Object?> toSyncPayload() {
    return {
      'id': id,
      'sync_id': syncId,
      'version': version,
      'full_name': fullName,
      'document_id': documentId,
      'phone': phone,
      'address': address,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'sync_status': syncStatus.storageValue,
    };
  }

  static DateTime? _readNullableDate(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized);
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
