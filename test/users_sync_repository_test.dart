import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late UsersSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('users_sync_repo_test_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'sync.db'));
    await appDatabase.initialize();
    repository = UsersSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('mergeRemoteRecords deduplicates existing local user by email', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(DatabaseSchema.usersTable, {
      'sync_id': 'local-user-1',
      'nombre': 'Usuario Local',
      'email': 'user@test.local',
      'password_hash': 'hash-local',
      'password_reset_required': 0,
      'rol': 'vendedor',
      'activo': 1,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingCreate,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-user-001',
        'sync_id': 'remote-sync-001',
        'version': 2,
        'full_name': 'Usuario Remoto',
        'email': 'user@test.local',
        'password_hash': 'hash-remote',
        'password_reset_required': false,
        'role': 'vendedor',
        'is_active': true,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.usersTable,
      where: 'LOWER(email) = ?',
      whereArgs: ['user@test.local'],
    );

    expect(rows, hasLength(1));
    expect(rows.first['sync_id'], 'remote-sync-001');
    expect(rows.first['id_remote'], 'remote-user-001');
    expect(rows.first['remote_auth_id'], 'remote-user-001');
  });

  test('getPendingRecords includes pending_update and pending_delete', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(DatabaseSchema.usersTable, {
      'sync_id': 'user-update',
      'nombre': 'Update',
      'email': 'update@test.local',
      'password_hash': 'hash',
      'password_reset_required': 0,
      'rol': 'vendedor',
      'activo': 1,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    await db.insert(DatabaseSchema.usersTable, {
      'sync_id': 'user-delete',
      'nombre': 'Delete',
      'email': 'delete@test.local',
      'password_hash': 'hash',
      'password_reset_required': 0,
      'rol': 'vendedor',
      'activo': 0,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingDelete,
    });

    final pending = await repository.getPendingRecords();
    final syncIds = pending
        .map((row) => row['sync_id']?.toString())
        .whereType<String>()
        .toSet();

    expect(syncIds, contains('user-update'));
    expect(syncIds, contains('user-delete'));
  });
}
