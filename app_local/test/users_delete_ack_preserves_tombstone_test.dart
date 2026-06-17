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
    tempDirectory = await Directory.systemTemp.createTemp(
      'users_delete_ack_tombstone_',
    );
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

  test('users_delete_ack_preserves_tombstone_test', () async {
    final created = await authService.createUser(
      nombre: 'Supervisor Baja',
      email: 'supervisor.baja@test.local',
      password: 'Supervisor123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(module: PermissionCatalog.sales, read: true),
      ],
    );

    await authService.deleteUser(created.id!);

    final db = await appDatabase.database;
    final beforeRows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['sync_id', 'sync_status', 'deleted_at'],
      where: 'id = ?',
      whereArgs: [created.id],
      limit: 1,
    );

    expect(beforeRows, hasLength(1));
    expect(
      beforeRows.first['sync_status'],
      DatabaseSchema.syncStatusPendingDelete,
    );
    expect((beforeRows.first['deleted_at'] as String?)?.isNotEmpty, isTrue);

    final syncId = beforeRows.first['sync_id'] as String;
    await usersSyncRepository.markAsSynced([syncId]);

    final afterRows = await db.query(
      DatabaseSchema.usersTable,
      columns: ['deleted_at', 'sync_status', 'activo'],
      where: 'id = ?',
      whereArgs: [created.id],
      limit: 1,
    );

    expect(afterRows, hasLength(1));
    expect((afterRows.first['deleted_at'] as String?)?.isNotEmpty, isTrue);
    expect(afterRows.first['sync_status'], DatabaseSchema.syncStatusSynced);
    expect(afterRows.first['activo'], 0);
  });
}
