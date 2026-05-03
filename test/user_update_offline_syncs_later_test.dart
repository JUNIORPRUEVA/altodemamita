import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recoveryCode = 'ABCD-EFGH-JKLM-NPQR';

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late AuthService authService;
  late UsersSyncRepository usersSyncRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('user_update_offline_sync_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();
    authService = AuthService(appDatabase: appDatabase);
    usersSyncRepository = UsersSyncRepository(appDatabase: appDatabase);

    await authService.completeInitialSetup(
      nombre: 'Admin Local',
      email: 'admin@local.test',
      password: 'AdminLocal123',
      recoveryCode: recoveryCode,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('user update while offline remains pending and can be marked synced later', () async {
    final created = await authService.createUser(
      nombre: 'Vendedor Uno',
      email: 'vendedor1@test.local',
      password: 'Vendedor123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(module: PermissionCatalog.sales, read: true),
      ],
    );

    final updated = await authService.updateUser(
      user: created,
      nombre: 'Vendedor Actualizado',
      email: 'vendedor1@test.local',
      role: UserRole.user,
      active: true,
      permissions: const [
        PermissionModel(module: PermissionCatalog.sales, read: true, update: true),
      ],
    );

    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['sync_id', 'sync_status'],
      where: 'id = ?',
      whereArgs: [updated.id],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusPendingUpdate);

    final syncId = rows.first['sync_id'] as String;
    await usersSyncRepository.markAsSynced([syncId]);

    final syncedRows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['sync_status'],
      where: 'id = ?',
      whereArgs: [updated.id],
      limit: 1,
    );
    expect(syncedRows.first['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}
