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
      'user_delete_offline_sync_',
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

  test(
    'user delete while offline remains as tombstone after sync ack',
    () async {
      final created = await authService.createUser(
        nombre: 'Vendedor Baja',
        email: 'vendedor.baja@test.local',
        password: 'Vendedor123',
        role: UserRole.user,
        permissions: const [
          PermissionModel(module: PermissionCatalog.sales, read: true),
        ],
      );

      await authService.deleteUser(created.id!);

      final db = await appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.usersTable,
        columns: ['sync_id', 'sync_status', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [created.id],
        limit: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.first['sync_status'], DatabaseSchema.syncStatusPendingDelete);
      expect((rows.first['deleted_at'] as String?)?.isNotEmpty, isTrue);

      final syncId = rows.first['sync_id'] as String;
      await usersSyncRepository.markAsSynced([syncId]);

      final syncedRows = await db.query(
        DatabaseSchema.usersTable,
        where: 'id = ?',
        whereArgs: [created.id],
        limit: 1,
      );
      expect(syncedRows, hasLength(1));
      expect(syncedRows.first['deleted_at'], isNotNull);
      expect(syncedRows.first['sync_status'], DatabaseSchema.syncStatusSynced);
      expect(syncedRows.first['activo'], 0);
    },
  );
}
