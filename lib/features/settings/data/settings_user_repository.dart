import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import '../domain/settings_user.dart';

class SettingsUserRepository {
  const SettingsUserRepository(this.database);

  final Database database;

  Future<List<SettingsUser>> getAllUsers() async {
    try {
      final maps = await database.query(
        DatabaseSchema.usersTable,
        where: 'deleted_at IS NULL',
        orderBy: 'nombre ASC',
      );
      return maps.map((map) => SettingsUser.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<SettingsUser?> getUserById(int id) async {
    try {
      final maps = await database.query(
        DatabaseSchema.usersTable,
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );

      if (maps.isEmpty) {
        return null;
      }

      return SettingsUser.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  Future<SettingsUser> createUser(SettingsUser user) async {
    SystemConfigService.instance.ensureWritable();

    final id = await database.insert(
      DatabaseSchema.usersTable,
      user.toMap(),
    );
    return user.copyWith(id: id);
  }

  Future<void> updateUser(SettingsUser user) async {
    SystemConfigService.instance.ensureWritable();

    if (user.id == null) {
      throw Exception('User ID cannot be null');
    }

    await database.update(
      DatabaseSchema.usersTable,
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> deleteUser(int id) async {
    SystemConfigService.instance.ensureWritable();

    final now = DateTime.now().toIso8601String();
    await database.update(
      DatabaseSchema.usersTable,
      {
        'activo': 0,
        'deleted_at': now,
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
        'fecha_actualizacion': now,
        'last_modified_local': now,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  Future<void> toggleUserStatus(int id, bool activo) async {
    final user = await getUserById(id);
    if (user != null) {
      await updateUser(user.copyWith(activo: activo));
    }
  }

  Future<List<SettingsUser>> getUsersByRole(String rol) async {
    try {
      final maps = await database.query(
        DatabaseSchema.usersTable,
        where: 'rol = ? AND deleted_at IS NULL',
        whereArgs: [rol],
        orderBy: 'nombre ASC',
      );
      return maps.map((map) => SettingsUser.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<SettingsUser>> getActiveUsers() async {
    try {
      final maps = await database.query(
        DatabaseSchema.usersTable,
        where: 'activo = ? AND deleted_at IS NULL',
        whereArgs: [1],
        orderBy: 'nombre ASC',
      );
      return maps.map((map) => SettingsUser.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }
}
