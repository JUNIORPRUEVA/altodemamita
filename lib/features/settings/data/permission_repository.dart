import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import '../domain/permission.dart';

class PermissionRepository {
  const PermissionRepository(this.database);

  final Database database;

  Future<List<Permission>> getPermissionsByUser(int usuarioId) async {
    try {
      final maps = await database.query(
        DatabaseSchema.permissionsTable,
        where: 'usuario_id = ?',
        whereArgs: [usuarioId],
      );
      return maps.map((map) => Permission.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Permission?> getPermission(int usuarioId, String modulo) async {
    try {
      final maps = await database.query(
        DatabaseSchema.permissionsTable,
        where: 'usuario_id = ? AND modulo = ?',
        whereArgs: [usuarioId, modulo],
      );

      if (maps.isEmpty) {
        return null;
      }

      return Permission.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  Future<Permission> savePermission(Permission permission) async {
    SystemConfigService.instance.ensureWritable();

    final existing = await getPermission(permission.usuarioId, permission.modulo);
    final now = DateTime.now().toIso8601String();

    // Mark permission as pending sync when modified
    final permissionMap = permission.toMap();
    permissionMap['sync_status'] = existing != null ? 'pending_update' : 'pending_create';

    if (existing != null) {
      await database.update(
        DatabaseSchema.permissionsTable,
        permissionMap,
        where: 'usuario_id = ? AND modulo = ?',
        whereArgs: [permission.usuarioId, permission.modulo],
      );
      await _markUserPendingUpdate(permission.usuarioId, now);
      return permission.copyWith(id: existing.id);
    } else {
      final id = await database.insert(
        DatabaseSchema.permissionsTable,
        permissionMap,
      );
      await _markUserPendingUpdate(permission.usuarioId, now);
      return permission.copyWith(id: id);
    }
  }

  Future<void> deletePermissionsForUser(int usuarioId) async {
    SystemConfigService.instance.ensureWritable();

    final now = DateTime.now().toIso8601String();
    // Soft-delete: mark as pending deletion for sync instead of hard-deleting
    await database.update(
      DatabaseSchema.permissionsTable,
      {
        'sync_status': 'pending_delete',
        'fecha_actualizacion': now,
      },
      where: 'usuario_id = ? AND sync_status != ?',
      whereArgs: [usuarioId, 'pending_delete'],
    );
    await _markUserPendingUpdate(usuarioId, now);
  }

  Future<void> _markUserPendingUpdate(int usuarioId, String now) async {
    await database.update(
      DatabaseSchema.usersTable,
      {
        'sync_status': DatabaseSchema.syncStatusPendingUpdate,
        'fecha_actualizacion': now,
        'last_modified_local': now,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [usuarioId],
    );
  }

  Future<bool> userHasAction(int usuarioId, String modulo, String accion) async {
    final permission = await getPermission(usuarioId, modulo);
    if (permission == null) {
      return false;
    }
    return permission.hasAction(accion);
  }

  Future<List<String>> getUserModules(int usuarioId) async {
    final permissions = await getPermissionsByUser(usuarioId);
    return permissions.map((p) => p.modulo).toList();
  }
}
