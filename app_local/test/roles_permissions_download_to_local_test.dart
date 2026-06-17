import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/roles_sync_repository.dart';
import 'package:sistema_solares/repositories/user_roles_sync_repository.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late UsersSyncRepository usersRepository;
  late RolesSyncRepository rolesRepository;
  late UserRolesSyncRepository userRolesRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'roles_permissions_local_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'sync.db'));
    await appDatabase.initialize();
    final db = await appDatabase.database;
    await db.execute('ALTER TABLE roles ADD COLUMN sync_id TEXT');
    await db.execute('ALTER TABLE user_roles ADD COLUMN sync_id TEXT');
    usersRepository = UsersSyncRepository(appDatabase: appDatabase);
    rolesRepository = RolesSyncRepository(appDatabase: appDatabase);
    userRolesRepository = UserRolesSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('roles_permissions_download_to_local_test', () async {
    await usersRepository.mergeRemoteRecords([
      {
        'id': 'user-remote-1',
        'sync_id': 'user-sync-1',
        'version': 1,
        'full_name': 'Admin Local',
        'email': 'admin@test.local',
        'username': 'admin',
        'password_hash': 'hash-local',
        'password_reset_required': false,
        'role': 'admin',
        'is_active': true,
        'permissions': ['settings.read', 'sales.read', 'sales.update'],
        'created_at': '2026-05-05T09:00:00.000Z',
        'updated_at': '2026-05-05T10:00:00.000Z',
        'deleted_at': null,
        'sync_status': 'synced',
      },
    ]);
    await rolesRepository.mergeRemoteRecords([
      {
        'id': 'role-remote-1',
        'sync_id': 'role-sync-1',
        'version': 1,
        'code': 'SUPER_ADMIN',
        'name': 'Super Admin',
        'description': 'Rol completo',
        'created_at': '2026-05-05T09:00:00.000Z',
        'updated_at': '2026-05-05T10:00:00.000Z',
        'deleted_at': null,
        'sync_status': 'synced',
      },
    ]);
    await userRolesRepository.mergeRemoteRecords([
      {
        'id': 'user-role-remote-1',
        'sync_id': 'user-sync-1:role-sync-1',
        'version': 1,
        'user_id': 'user-remote-1',
        'role_id': 'role-remote-1',
        'user_sync_id': 'user-sync-1',
        'role_sync_id': 'role-sync-1',
        'created_at': '2026-05-05T09:00:00.000Z',
        'updated_at': '2026-05-05T10:00:00.000Z',
        'deleted_at': null,
        'sync_status': 'synced',
      },
    ]);

    final db = await appDatabase.database;
    final roles = await db.query(DatabaseSchema.rolesTable);
    final userRoles = await db.query(DatabaseSchema.userRolesTable);
    final permissions = await db.query(DatabaseSchema.permissionsTable);

    expect(roles, hasLength(1));
    expect(userRoles, hasLength(1));
    expect(permissions, isNotEmpty);
  });
}
