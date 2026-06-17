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
    tempDirectory = await Directory.systemTemp.createTemp('merge_preserve_hash_');
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

  test('remote merge preserves local password hash when remote hash is missing/null/empty', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    const localHash = 'hash-local-keep';

    await db.insert(DatabaseSchema.usersTable, {
      'sync_id': 'local-sync-1',
      'id_remote': 'remote-user-001',
      'remote_auth_id': 'remote-user-001',
      'nombre': 'Usuario Local',
      'email': 'admin@gmail.com',
      'password_hash': localHash,
      'password_reset_required': 0,
      'rol': 'admin',
      'activo': 1,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': now,
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    for (final payload in [
      {
        'id': 'remote-user-001',
        'sync_id': 'local-sync-1',
        'version': 2,
        'full_name': 'Usuario Remoto',
        'email': 'admin@gmail.com',
        'password_reset_required': false,
        'role': 'admin',
        'is_active': true,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      },
      {
        'id': 'remote-user-001',
        'sync_id': 'local-sync-1',
        'version': 3,
        'full_name': 'Usuario Remoto',
        'email': 'admin@gmail.com',
        'password_hash': null,
        'password_reset_required': false,
        'role': 'admin',
        'is_active': true,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      },
      {
        'id': 'remote-user-001',
        'sync_id': 'local-sync-1',
        'version': 4,
        'full_name': 'Usuario Remoto',
        'email': 'admin@gmail.com',
        'password_hash': '',
        'password_reset_required': false,
        'role': 'admin',
        'is_active': true,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      },
    ]) {
      await repository.mergeRemoteRecords([payload]);
    }

    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['password_hash'],
      where: 'LOWER(email) = ?',
      whereArgs: ['admin@gmail.com'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['password_hash'], localHash);
  });
}
