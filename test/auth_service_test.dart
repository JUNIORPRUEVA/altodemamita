import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/security/password_hasher.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recoveryCode = 'ABCD-EFGH-JKLM-NPQR';

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_auth_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'auth.db'));
    await appDatabase.initialize();
    authService = AuthService(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'exige bootstrap inicial y luego permite entrar al administrador',
    () async {
      expect(await authService.requiresInitialSetup(), isTrue);

      await expectLater(
        authService.signIn(
          email: PasswordHasher.defaultAdminEmail,
          password: PasswordHasher.legacyDefaultAdminPassword,
        ),
        throwsA(isA<AuthException>()),
      );

      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      expect(await authService.requiresInitialSetup(), isFalse);

      final user = await authService.signIn(
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
      );

      expect(user.isAdmin, isTrue);
      expect(user.email, 'admin@local.test');
    },
  );

  test(
    'permite entrar con usuario o correo y recorta espacios en la clave',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Programador',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final signedInByName = await authService.signIn(
        email: 'programador',
        password: '  AdminLocalSegura123  ',
      );

      final signedInByEmail = await authService.signIn(
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
      );

      expect(signedInByName.isAdmin, isTrue);
      expect(signedInByName.nombre, 'Programador');
      expect(signedInByEmail.email, 'admin@local.test');
    },
  );

  test('crea usuario con permisos y restaura su sesion por token', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final createdUser = await authService.createUser(
      nombre: 'Operador Caja',
      email: 'caja@local.test',
      password: 'CajaSegura123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(
          module: PermissionCatalog.payments,
          read: true,
          create: true,
        ),
        PermissionModel(module: PermissionCatalog.clients, read: true),
      ],
    );

    final signedInUser = await authService.signIn(
      email: 'caja@local.test',
      password: 'CajaSegura123',
    );
    final restoredUser = await authService.restoreSession();

    expect(createdUser.id, isNotNull);
    expect(signedInUser.id, createdUser.id);
    expect(
      restoredUser?.allows(PermissionCatalog.payments, PermissionAction.create),
      isTrue,
    );
    expect(
      restoredUser?.allows(PermissionCatalog.sales, PermissionAction.read),
      isFalse,
    );
  });

  test(
    'valida la clave de un administrador sin cambiar la sesion activa',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final isApproved = await authService.verifyAdminPassword(
        password: 'AdminLocalSegura123',
      );

      expect(isApproved, isTrue);
      expect(await authService.restoreSession(), isNull);
    },
  );

  test('rechaza claves de usuarios que no son administradores', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    await authService.createUser(
      nombre: 'Operador Caja',
      email: 'caja@local.test',
      password: 'CajaSegura123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(module: PermissionCatalog.payments, read: true),
      ],
    );

    final isApproved = await authService.verifyAdminPassword(
      password: 'CajaSegura123',
    );

    expect(isApproved, isFalse);
  });

  test('permite al usuario cambiar su propia contraseña', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final createdUser = await authService.createUser(
      nombre: 'Operador Caja',
      email: 'caja@local.test',
      password: 'CajaSegura123',
      role: UserRole.user,
      permissions: const [
        PermissionModel(module: PermissionCatalog.payments, read: true),
      ],
    );

    final updatedUser = await authService.changeOwnPassword(
      userId: createdUser.id!,
      currentPassword: 'CajaSegura123',
      newPassword: 'CajaSegura456',
    );

    final signedInUser = await authService.signIn(
      email: 'caja@local.test',
      password: 'CajaSegura456',
    );

    expect(updatedUser.passwordUpdatedAt, isNotNull);
    expect(signedInUser.id, createdUser.id);
  });

  test(
    'rechaza el cambio de contraseña si la clave actual no coincide',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final createdUser = await authService.createUser(
        nombre: 'Operador Caja',
        email: 'caja@local.test',
        password: 'CajaSegura123',
        role: UserRole.user,
        permissions: const [
          PermissionModel(module: PermissionCatalog.payments, read: true),
        ],
      );

      await expectLater(
        authService.changeOwnPassword(
          userId: createdUser.id!,
          currentPassword: 'ClaveIncorrecta123',
          newPassword: 'CajaSegura456',
        ),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test('impide degradar o desactivar al ultimo administrador activo', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final admin = await authService.getUserById(1);
    expect(admin, isNotNull);

    await expectLater(
      authService.updateUser(
        user: admin!,
        nombre: admin.nombre,
        email: admin.email,
        role: UserRole.user,
        active: true,
        permissions: const [],
      ),
      throwsA(isA<AuthException>()),
    );

    await expectLater(
      authService.setUserActive(user: admin, active: false),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'genera y conserva la clave de recuperacion del administrador',
    () async {
      final configuredCode = await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final storedCode = await authService.getOrCreateAdminRecoveryCode();

      expect(configuredCode, recoveryCode);
      expect(storedCode, recoveryCode);
    },
  );

  test('permite ver las credenciales actuales con la clave unica', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final credentials = await authService.revealAdminCredentials(
      recoveryCode: recoveryCode,
    );

    expect(credentials.nombre, 'Admin General');
    expect(credentials.email, 'admin@local.test');
    expect(credentials.password, 'AdminLocalSegura123');
  });

  test(
    'sincroniza los datos visibles al editar el admin sin cambiar clave',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final admin = await authService.getUserById(1);
      final updated = await authService.updateUser(
        user: admin!,
        nombre: 'Admin Principal',
        email: 'principal@local.test',
        role: UserRole.admin,
        active: true,
        permissions: const [],
      );
      final credentials = await authService.revealAdminCredentials(
        recoveryCode: recoveryCode,
      );

      expect(updated.email, 'principal@local.test');
      expect(credentials.nombre, 'Admin Principal');
      expect(credentials.email, 'principal@local.test');
      expect(credentials.password, 'AdminLocalSegura123');
    },
  );

  test(
    'sincroniza la contrasena visible cuando el admin cambia su clave',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      await authService.changeOwnPassword(
        userId: 1,
        currentPassword: 'AdminLocalSegura123',
        newPassword: 'AdminVisible456',
      );
      final credentials = await authService.revealAdminCredentials(
        recoveryCode: recoveryCode,
      );

      expect(credentials.email, 'admin@local.test');
      expect(credentials.password, 'AdminVisible456');
    },
  );

  test(
    'permite recuperar el acceso del administrador con la clave unica',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final recovered = await authService.recoverAdminAccess(
        recoveryCode: recoveryCode,
        nombre: 'Admin Recuperado',
        email: 'nuevo-admin@local.test',
        newPassword: 'AdminNueva123',
      );

      expect(recovered.email, 'nuevo-admin@local.test');
      expect(recovered.nombre, 'Admin Recuperado');
      expect(recovered.isAdmin, isTrue);

      final credentials = await authService.revealAdminCredentials(
        recoveryCode: recoveryCode,
      );
      expect(credentials.email, 'nuevo-admin@local.test');
      expect(credentials.password, 'AdminNueva123');
    },
  );

  test('rechaza la recuperacion cuando la clave unica no coincide', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    await expectLater(
      authService.recoverAdminAccess(
        recoveryCode: 'XXXX-XXXX-XXXX-XXXX',
        nombre: 'Admin Recuperado',
        email: 'nuevo-admin@local.test',
        newPassword: 'AdminNueva123',
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'permite recuperar acceso en instalaciones viejas sin datos visibles',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final db = await appDatabase.database;
      await db.delete(
        DatabaseSchema.settingsTable,
        where: 'clave = ?',
        whereArgs: ['admin_recovery_credentials_snapshot'],
      );

      await expectLater(
        authService.revealAdminCredentials(recoveryCode: recoveryCode),
        throwsA(isA<AuthException>()),
      );

      final recovered = await authService.recoverAdminAccess(
        recoveryCode: recoveryCode,
        nombre: 'Admin Recuperado',
        email: 'admin-recuperado@local.test',
        newPassword: 'AdminNueva123',
      );

      expect(recovered.email, 'admin-recuperado@local.test');

      final credentials = await authService.revealAdminCredentials(
        recoveryCode: recoveryCode,
      );
      expect(credentials.email, 'admin-recuperado@local.test');
      expect(credentials.password, 'AdminNueva123');
    },
  );

  test(
    'ignora snapshots protegidos ilegibles al preparar el prefill debug',
    () async {
      await authService.completeInitialSetup(
        nombre: 'Admin General',
        email: 'admin@local.test',
        password: 'AdminLocalSegura123',
        recoveryCode: recoveryCode,
      );

      final db = await appDatabase.database;
      await db.update(
        DatabaseSchema.settingsTable,
        {
          'valor': 'snapshot-corrupto',
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        },
        where: 'clave = ?',
        whereArgs: ['admin_recovery_credentials_snapshot'],
      );

      final credentials = await authService.getDebugAdminPrefillCredentials();

      expect(credentials, isNotNull);
      expect(credentials?.nombre, 'Admin General');
      expect(credentials?.email, 'admin@local.test');
      expect(credentials?.password, isEmpty);
    },
  );

  test('permite regenerar la clave de recuperacion', () async {
    await authService.completeInitialSetup(
      nombre: 'Admin General',
      email: 'admin@local.test',
      password: 'AdminLocalSegura123',
      recoveryCode: recoveryCode,
    );

    final regeneratedCode = await authService.regenerateAdminRecoveryCode();

    expect(regeneratedCode, isNot(recoveryCode));
    expect(await authService.getOrCreateAdminRecoveryCode(), regeneratedCode);
  });
}
