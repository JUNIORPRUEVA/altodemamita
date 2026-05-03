import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/backend_config.dart';
import '../../features/sales/domain/sale_calculator.dart';
import '../config/app_flags.dart';
import '../security/password_hasher.dart';

class DatabaseSchema {
  static const String databaseName = 'sistema_solares.db';
  static const int databaseVersion = 20;
  static const String defaultSyncBaseUrl = BASE_URL;

  static const String clientsTable = 'clientes';
  static const String usersTable = 'usuarios';
  static const String lotsTable = 'solares';
  static const String sellersTable = 'vendedores';
  static const String salesTable = 'ventas';
  static const String installmentsTable = 'cuotas';
  static const String paymentsTable = 'pagos';
  static const String settingsTable = 'configuracion';

  // New settings module tables
  static const String companyInfoTable = 'informacion_empresa';
  static const String permissionsTable = 'permisos';
  static const String printerConfigTable = 'configuracion_impresoras';
  static const String financialParamsTable = 'parametros_financieros';
  static const String backupInfoTable = 'informacion_backups';
  static const String backupPreferencesTable = 'preferencias_backup';
  static const String authSessionsTable = 'sesiones_auth';
  static const String rolesTable = 'roles';
  static const String userRolesTable = 'user_roles';
  static const String rolePermissionsTable = 'role_permissions';
  static const String companyProfilesTable = 'company_profiles';
  static const String syncQueueTable = 'sync_queue';
  static const String conflictLogsTable = 'conflict_logs';
  static const String uploadStatusPending = 'pending_upload';
  static const String uploadStatusUploading = 'uploading';
  static const String uploadStatusSynced = 'uploaded';
  static const String uploadStatusFailed = 'failed';
  static const String syncStatusPending = 'pending';
  static const String syncStatusPendingSync = 'pending_sync';
  static const String syncStatusPendingCreate = 'pending_create';
  static const String syncStatusPendingUpdate = 'pending_update';
  static const String syncStatusPendingDelete = 'pending_delete';
  static const String syncStatusSynced = 'synced';
  static const String syncStatusConflict = 'conflict';
  static const String syncStatusFailed = 'failed';
  static const List<String> writableSyncStatuses = [
    syncStatusPending,
    syncStatusPendingSync,
    syncStatusPendingCreate,
    syncStatusPendingUpdate,
    syncStatusPendingDelete,
    syncStatusConflict,
    syncStatusFailed,
  ];
  static const Set<String> criticalTables = {
    clientsTable,
    usersTable,
    lotsTable,
    salesTable,
    installmentsTable,
    paymentsTable,
    settingsTable,
  };
  static const List<String> syncMetadataTables = [
    clientsTable,
    usersTable,
    sellersTable,
    lotsTable,
    salesTable,
    installmentsTable,
    paymentsTable,
    companyInfoTable,
    permissionsTable,
    printerConfigTable,
    financialParamsTable,
    backupInfoTable,
    backupPreferencesTable,
    authSessionsTable,
    rolesTable,
    userRolesTable,
    rolePermissionsTable,
    companyProfilesTable,
  ];
  static const List<String> syncEnabledTables = [
    usersTable,
    rolesTable,
    userRolesTable,
    rolePermissionsTable,
    permissionsTable,
    clientsTable,
    sellersTable,
    lotsTable,
    salesTable,
    installmentsTable,
    paymentsTable,
  ];

  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.execute('PRAGMA synchronous = FULL');
    await db.execute('PRAGMA journal_size_limit = 67108864');
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }

  static Future<void> createTables(Database db) async {
    await _createVersion2Tables(db, ifNotExists: false);
    await _migrateToVersion4(db);
    await _migrateToVersion5(db);
    await _migrateToVersion6(db);
    await _migrateToVersion7(db);
    await _migrateToVersion8(db);
    await _migrateToVersion9(db);
    await _migrateToVersion10(db);
    await _migrateToVersion11(db);
    await _migrateToVersion12(db);
    await _migrateToVersion13(db);
    await _migrateToVersion14(db);
    await _migrateToVersion15(db);
    await _migrateToVersion16(db);
    await _migrateToVersion17(db);
    await _migrateToVersion18(db);
    await _migrateToVersion19(db);
    await _migrateToVersion20(db);
  }

  static Future<void> ensureCoreStructures(DatabaseExecutor db) async {
    await _createVersion2Tables(db, ifNotExists: true);
    await _migrateToVersion4(db);
    await _migrateToVersion5(db);
    await _migrateToVersion6(db);
    await _migrateToVersion7(db);
    await _migrateToVersion8(db);
    await _migrateToVersion9(db);
    await _migrateToVersion10(db);
    await _migrateToVersion11(db);
    await _migrateToVersion12(db);
    await _migrateToVersion13(db);
    await _migrateToVersion14(db);
    await _migrateToVersion15(db);
    await _migrateToVersion16(db);
    await _migrateToVersion17(db);
    await _migrateToVersion18(db);
    await _migrateToVersion19(db);
    await _migrateToVersion20(db);
    await seedDefaults(db);
  }

  static Future<List<String>> missingCriticalTables(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final available = rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    return criticalTables
        .where((tableName) => !available.contains(tableName))
        .toList();
  }

  static Future<void> seedDefaults(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    batch.insert(usersTable, {
      'id': 1,
      'nombre': 'Administrador principal',
      'email': PasswordHasher.defaultAdminEmail,
      'password_hash': '',
      'password_reset_required': 1,
      'rol': 'admin',
      'activo': 1,
      'telefono': null,
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'password_updated_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final defaults = <Map<String, Object?>>[
      {
        'clave': 'business_name',
        'valor': 'EL ALTO DE DONA MAMITA',
        'fecha_actualizacion': now,
      },
      {'clave': 'currency_symbol', 'valor': 'RD\$', 'fecha_actualizacion': now},
      {
        'clave': 'default_payment_method',
        'valor': 'efectivo',
        'fecha_actualizacion': now,
      },
      {
        'clave': 'sale_default_down_payment_percentage',
        'valor': '10',
        'fecha_actualizacion': now,
      },
      {
        'clave': 'sale_default_monthly_interest',
        'valor': '1',
        'fecha_actualizacion': now,
      },
      {
        'clave': 'sale_default_installment_count',
        'valor': '12',
        'fecha_actualizacion': now,
      },
    ];

    for (final item in defaults) {
      batch.insert(
        settingsTable,
        item,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
    await _ensureAdminCredentials(db, now);
  }

  static Future<void> _ensureAdminCredentials(
    DatabaseExecutor db,
    String now,
  ) async {
    final rows = await db.rawQuery(
      'SELECT id, email, password_hash, password_reset_required, rol, activo, '
      'fecha_actualizacion '
      'FROM $usersTable WHERE id = 1 LIMIT 1',
    );
    final bootstrapHash = PasswordHasher.hashPassword(
      PasswordHasher.generateRandomToken(),
    );

    if (rows.isEmpty) {
      await db.rawInsert(
        'INSERT INTO $usersTable '
        '(id, nombre, email, password_hash, password_reset_required, rol, activo, telefono, fecha_creacion, fecha_actualizacion, password_updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          1,
          'Administrador principal',
          PasswordHasher.defaultAdminEmail,
          bootstrapHash,
          1,
          'admin',
          1,
          null,
          now,
          now,
          null,
        ],
      );
      return;
    }

    final row = rows.first;
    final email = (row['email'] as String? ?? '').trim().toLowerCase();
    final passwordHash = (row['password_hash'] as String? ?? '').trim();
    final passwordResetRequired =
        (row['password_reset_required'] as int? ?? 0) == 1;
    final role = (row['rol'] as String? ?? '').trim().toLowerCase();
    final active = row['activo'] as int? ?? 0;
    final updatedAt = (row['fecha_actualizacion'] as String? ?? '').trim();
    final requiresBootstrap =
        passwordHash.isEmpty ||
        passwordResetRequired ||
        PasswordHasher.verifyPassword(
          PasswordHasher.legacyDefaultAdminPassword,
          passwordHash,
        ) ||
        PasswordHasher.verifyPassword(
          PasswordHasher.legacyMigratedPassword,
          passwordHash,
        );

    if (email.isNotEmpty &&
        role == 'admin' &&
        active == 1 &&
        updatedAt.isNotEmpty &&
        !requiresBootstrap) {
      return;
    }

    await db.rawUpdate(
      'UPDATE $usersTable '
      'SET email = ?, password_hash = ?, password_reset_required = ?, rol = ?, activo = ?, fecha_actualizacion = ? '
      'WHERE id = 1',
      [
        email.isEmpty ? PasswordHasher.defaultAdminEmail : email,
        requiresBootstrap ? bootstrapHash : passwordHash,
        requiresBootstrap ? 1 : 0,
        'admin',
        1,
        updatedAt.isEmpty ? now : updatedAt,
      ],
    );
  }

  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await _migrateToVersion2(db);
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await _migrateToVersion3(db);
    }
    if (oldVersion < 4 && newVersion >= 4) {
      await _migrateToVersion4(db);
    }
    if (oldVersion < 5 && newVersion >= 5) {
      await _migrateToVersion5(db);
    }
    if (oldVersion < 6 && newVersion >= 6) {
      await _migrateToVersion6(db);
    }
    if (oldVersion < 7 && newVersion >= 7) {
      await _migrateToVersion7(db);
    }
    if (oldVersion < 8 && newVersion >= 8) {
      await _migrateToVersion8(db);
    }
    if (oldVersion < 9 && newVersion >= 9) {
      await _migrateToVersion9(db);
    }
    if (oldVersion < 10 && newVersion >= 10) {
      await _migrateToVersion10(db);
    }
    if (oldVersion < 11 && newVersion >= 11) {
      await _migrateToVersion11(db);
    }
    if (oldVersion < 12 && newVersion >= 12) {
      await _migrateToVersion12(db);
    }
    if (oldVersion < 13 && newVersion >= 13) {
      await _migrateToVersion13(db);
    }
    if (oldVersion < 14 && newVersion >= 14) {
      await _migrateToVersion14(db);
    }
    if (oldVersion < 15 && newVersion >= 15) {
      await _migrateToVersion15(db);
    }
    if (oldVersion < 16 && newVersion >= 16) {
      await _migrateToVersion16(db);
    }
    if (oldVersion < 17 && newVersion >= 17) {
      await _migrateToVersion17(db);
    }

    if (oldVersion < 18 && newVersion >= 18) {
      await _migrateToVersion18(db);
    }

    if (oldVersion < 19 && newVersion >= 19) {
      await _migrateToVersion19(db);
    }

    if (oldVersion < 20 && newVersion >= 20) {
      await _migrateToVersion20(db);
    }

    await seedDefaults(db);
  }

  static Future<void> _migrateToVersion19(DatabaseExecutor db) async {
    for (final tableName in syncMetadataTables) {
      if (!await _tableExists(db, tableName)) {
        continue;
      }

      final hasFechaActualizacion = await _columnExists(
        db,
        tableName,
        'fecha_actualizacion',
      );
      final hasFechaCreacion = await _columnExists(
        db,
        tableName,
        'fecha_creacion',
      );
      final hasCreatedAt = await _columnExists(db, tableName, 'created_at');
      final hasSyncStatus = await _columnExists(db, tableName, 'sync_status');
      final updatedColumn = hasFechaActualizacion
          ? 'fecha_actualizacion'
          : (hasCreatedAt ? 'created_at' : null);
      final createdColumn = hasFechaCreacion
          ? 'fecha_creacion'
          : (hasCreatedAt ? 'created_at' : null);

      if (!await _columnExists(db, tableName, 'id_local')) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN id_local INTEGER');
      }
      if (!await _columnExists(db, tableName, 'id_remote')) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN id_remote TEXT');
      }
      if (!await _columnExists(db, tableName, 'last_modified_local')) {
        await db.execute(
          'ALTER TABLE $tableName ADD COLUMN last_modified_local TEXT',
        );
      }
      if (!await _columnExists(db, tableName, 'last_modified_remote')) {
        await db.execute(
          'ALTER TABLE $tableName ADD COLUMN last_modified_remote TEXT',
        );
      }

      await db.execute(
        'UPDATE $tableName SET id_local = id WHERE id_local IS NULL',
      );
      final localTimestampParts = [
        "NULLIF(TRIM(last_modified_local), '')",
        if (updatedColumn != null) "NULLIF(TRIM($updatedColumn), '')",
        if (createdColumn != null && createdColumn != updatedColumn)
          "NULLIF(TRIM($createdColumn), '')",
      ];
      final localSql = localTimestampParts.length == 1
          ? localTimestampParts.first
          : 'COALESCE(${localTimestampParts.join(', ')})';
      await db.execute('''
        UPDATE $tableName
        SET last_modified_local = $localSql
      ''');

      final remoteTimestampParts = [
        if (updatedColumn != null) "NULLIF(TRIM($updatedColumn), '')",
        if (createdColumn != null && createdColumn != updatedColumn)
          "NULLIF(TRIM($createdColumn), '')",
      ];
      if (remoteTimestampParts.isNotEmpty && hasSyncStatus) {
        final remoteFallbackSql = remoteTimestampParts.length == 1
            ? remoteTimestampParts.first
            : 'COALESCE(${remoteTimestampParts.join(', ')})';
        await db.execute('''
          UPDATE $tableName
          SET last_modified_remote = COALESCE(
            NULLIF(TRIM(last_modified_remote), ''),
            CASE
              WHEN sync_status = '$syncStatusSynced' THEN $remoteFallbackSql
              ELSE last_modified_remote
            END
          )
        ''');
      }

      if (tableName == usersTable &&
          await _columnExists(db, tableName, 'remote_auth_id')) {
        await db.execute('''
          UPDATE $tableName
          SET id_remote = COALESCE(NULLIF(TRIM(id_remote), ''), NULLIF(TRIM(remote_auth_id), ''))
        ''');
      }

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_id_local ON $tableName(id_local)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_id_remote ON $tableName(id_remote)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_last_modified_local ON $tableName(last_modified_local)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_last_modified_remote ON $tableName(last_modified_remote)',
      );
    }

    for (final statusTable in syncEnabledTables) {
      if (!await _tableExists(db, statusTable)) {
        continue;
      }
      final hasSyncStatus = await _columnExists(db, statusTable, 'sync_status');
      final hasIdRemote = await _columnExists(db, statusTable, 'id_remote');
      final hasDeletedAt = await _columnExists(db, statusTable, 'deleted_at');
      if (!hasSyncStatus || !hasIdRemote || !hasDeletedAt) {
        continue;
      }

      await db.execute('''
        UPDATE $statusTable
        SET sync_status = '$syncStatusPendingCreate'
        WHERE sync_status = '$syncStatusPending'
          AND id_remote IS NULL
          AND deleted_at IS NULL
      ''');
      await db.execute('''
        UPDATE $statusTable
        SET sync_status = '$syncStatusPendingUpdate'
        WHERE sync_status IN ('$syncStatusPending', '$syncStatusPendingSync')
          AND id_remote IS NOT NULL
          AND deleted_at IS NULL
      ''');
      await db.execute('''
        UPDATE $statusTable
        SET sync_status = '$syncStatusPendingDelete'
        WHERE deleted_at IS NOT NULL
          AND sync_status IN (
            '$syncStatusPending',
            '$syncStatusPendingSync',
            '$syncStatusConflict',
            '$syncStatusFailed'
          )
      ''');
    }
  }

  static Future<void> _migrateToVersion20(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $rolesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        id_local INTEGER,
        id_remote TEXT,
        sync_status TEXT NOT NULL DEFAULT '$syncStatusSynced',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_modified_local TEXT,
        last_modified_remote TEXT,
        deleted_at TEXT,
        UNIQUE(code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $userRolesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        role_id INTEGER NOT NULL,
        id_local INTEGER,
        id_remote TEXT,
        sync_status TEXT NOT NULL DEFAULT '$syncStatusSynced',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_modified_local TEXT,
        last_modified_remote TEXT,
        deleted_at TEXT,
        UNIQUE(user_id, role_id),
        FOREIGN KEY(user_id) REFERENCES $usersTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        FOREIGN KEY(role_id) REFERENCES $rolesTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $rolePermissionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role_id INTEGER NOT NULL,
        permission_id INTEGER,
        id_local INTEGER,
        id_remote TEXT,
        sync_status TEXT NOT NULL DEFAULT '$syncStatusSynced',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_modified_local TEXT,
        last_modified_remote TEXT,
        deleted_at TEXT,
        UNIQUE(role_id, permission_id),
        FOREIGN KEY(role_id) REFERENCES $rolesTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        FOREIGN KEY(permission_id) REFERENCES $permissionsTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $companyProfilesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        logo_base64 TEXT,
        local_path TEXT,
        remote_url TEXT,
        upload_status TEXT NOT NULL DEFAULT '$uploadStatusSynced',
        id_local INTEGER,
        id_remote TEXT,
        sync_status TEXT NOT NULL DEFAULT '$syncStatusSynced',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_modified_local TEXT,
        last_modified_remote TEXT,
        deleted_at TEXT
      )
    ''');

    for (final columnName in ['local_path', 'remote_url', 'upload_status']) {
      if (!await _columnExists(db, companyInfoTable, columnName)) {
        if (columnName == 'upload_status') {
          await db.execute(
            "ALTER TABLE $companyInfoTable ADD COLUMN upload_status TEXT NOT NULL DEFAULT '$uploadStatusSynced'",
          );
        } else {
          await db.execute(
            'ALTER TABLE $companyInfoTable ADD COLUMN $columnName TEXT',
          );
        }
      }
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_roles_id_remote ON $rolesTable(id_remote)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_roles_sync_status ON $rolesTable(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_roles_id_remote ON $userRolesTable(id_remote)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_roles_sync_status ON $userRolesTable(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_role_permissions_id_remote ON $rolePermissionsTable(id_remote)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_role_permissions_sync_status ON $rolePermissionsTable(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_company_profiles_id_remote ON $companyProfilesTable(id_remote)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_company_profiles_upload_status ON $companyProfilesTable(upload_status)',
    );

    if (await _tableExists(db, companyInfoTable)) {
      final now = DateTime.now().toIso8601String();
      await db.execute('''
        INSERT INTO $companyProfilesTable (
          name,
          phone,
          address,
          logo_base64,
          local_path,
          remote_url,
          upload_status,
          id_local,
          id_remote,
          sync_status,
          created_at,
          updated_at,
          last_modified_local,
          last_modified_remote,
          deleted_at
        )
        SELECT
          COALESCE(NULLIF(TRIM(nombre), ''), 'Empresa'),
          telefono,
          direccion,
          logo_base64,
          local_path,
          remote_url,
          COALESCE(NULLIF(TRIM(upload_status), ''), '$uploadStatusSynced'),
          id,
          id_remote,
          COALESCE(NULLIF(TRIM(sync_status), ''), '$syncStatusSynced'),
          COALESCE(NULLIF(TRIM(fecha_creacion), ''), '$now'),
          COALESCE(NULLIF(TRIM(fecha_actualizacion), ''), '$now'),
          COALESCE(
            NULLIF(TRIM(last_modified_local), ''),
            NULLIF(TRIM(fecha_actualizacion), ''),
            '$now'
          ),
          COALESCE(
            NULLIF(TRIM(last_modified_remote), ''),
            NULLIF(TRIM(fecha_actualizacion), '')
          ),
          deleted_at
        FROM $companyInfoTable
        WHERE NOT EXISTS (SELECT 1 FROM $companyProfilesTable)
      ''');
    }
  }

  static Future<void> _migrateToVersion18(DatabaseExecutor db) async {
    if (!await _tableExists(db, conflictLogsTable)) {
      return;
    }

    // Deduplicate open conflicts (same scope + record_sync_id) by keeping only
    // the latest row and auto-resolving older duplicates.
    await db.execute('''
      UPDATE $conflictLogsTable
      SET
        resolution = COALESCE(resolution, 'deduped'),
        resolved_at = COALESCE(
          resolved_at,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
      WHERE resolved_at IS NULL
        AND id NOT IN (
          SELECT MAX(id)
          FROM $conflictLogsTable
          WHERE resolved_at IS NULL
          GROUP BY scope, record_sync_id
        )
    ''');

    // Prevent future duplicates for unresolved conflicts.
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_conflict_logs_open
      ON $conflictLogsTable(scope, record_sync_id)
      WHERE resolved_at IS NULL
    ''');

    // Existing clients might be stuck because older builds marked records as
    // sync_status='conflict' and removed them from the queue. There's no UI to
    // manually resolve conflicts yet, so we unblock by:
    // 1) resetting scope tables back to sync_status='synced'
    // 2) marking any remaining open conflict logs as resolved.
    final now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
    final scopeToTable = <String, String>{
      'clients': clientsTable,
      'sellers': sellersTable,
      'products': lotsTable,
      'sales': salesTable,
      'installments': installmentsTable,
      'payments': paymentsTable,
    };

    for (final entry in scopeToTable.entries) {
      final scope = entry.key;
      final tableName = entry.value;
      if (!await _tableExists(db, tableName)) {
        continue;
      }

      await db.execute('''
        UPDATE $tableName
        SET sync_status = '$syncStatusSynced'
        WHERE sync_status = '$syncStatusConflict'
          AND sync_id IN (
            SELECT record_sync_id
            FROM $conflictLogsTable
            WHERE scope = '$scope' AND resolved_at IS NULL
          )
      ''');
    }

    await db.execute('''
      UPDATE $conflictLogsTable
      SET
        resolution = COALESCE(resolution, 'migrated_autoresolved'),
        resolved_at = COALESCE(resolved_at, $now)
      WHERE resolved_at IS NULL
    ''');
  }

  static Future<void> _migrateToVersion17(DatabaseExecutor db) async {
    if (!await _columnExists(db, usersTable, 'remote_auth_id')) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN remote_auth_id TEXT',
      );
    }
    if (!await _columnExists(db, usersTable, 'auth_source')) {
      await db.execute(
        "ALTER TABLE $usersTable ADD COLUMN auth_source TEXT NOT NULL DEFAULT 'local'",
      );
    }
    if (!await _columnExists(db, usersTable, 'last_online_login_at')) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN last_online_login_at TEXT',
      );
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_remote_auth_id ON $usersTable(remote_auth_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_usuarios_auth_source ON $usersTable(auth_source)',
    );
  }

  static Future<void> _migrateToVersion16(DatabaseExecutor db) async {
    for (final tableName in syncMetadataTables) {
      if (!await _tableExists(db, tableName)) {
        continue;
      }

      if (!await _columnExists(db, tableName, 'version')) {
        await db.execute(
          'ALTER TABLE $tableName ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
        );
      }

      await db.execute(
        'UPDATE $tableName SET version = 1 WHERE version IS NULL OR version < 1',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_version ON $tableName(version)',
      );
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${tableName}_version_update
        AFTER UPDATE ON $tableName
        FOR EACH ROW
        WHEN NEW.version <= OLD.version
        BEGIN
          UPDATE $tableName
          SET version = OLD.version + 1
          WHERE rowid = NEW.rowid;
        END;
      ''');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $conflictLogsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL,
        record_sync_id TEXT NOT NULL,
        local_version INTEGER,
        server_version INTEGER,
        strategy TEXT NOT NULL,
        local_payload_json TEXT,
        server_payload_json TEXT,
        message TEXT,
        resolution TEXT,
        detected_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_conflict_logs_scope_record ON $conflictLogsTable(scope, record_sync_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_conflict_logs_resolved_at ON $conflictLogsTable(resolved_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_conflict_logs_detected_at ON $conflictLogsTable(detected_at)',
    );
  }

  static Future<void> _migrateToVersion15(DatabaseExecutor db) async {
    if (await _tableExists(db, paymentsTable) &&
        !await _columnExists(db, paymentsTable, 'fecha_actualizacion')) {
      await db.execute(
        'ALTER TABLE $paymentsTable ADD COLUMN fecha_actualizacion TEXT',
      );
      await db.execute(
        "UPDATE $paymentsTable SET fecha_actualizacion = fecha_creacion WHERE fecha_actualizacion IS NULL OR trim(fecha_actualizacion) = ''",
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncQueueTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL,
        record_sync_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK(operation IN ('upsert', 'delete')),
        payload_json TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        next_attempt_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(scope, record_sync_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_due ON $syncQueueTable(next_attempt_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_scope ON $syncQueueTable(scope)',
    );
  }

  static Future<void> _migrateToVersion14(DatabaseExecutor db) async {
    for (final tableName in syncMetadataTables) {
      if (!await _tableExists(db, tableName)) {
        continue;
      }

      if (!await _columnExists(db, tableName, 'sync_id')) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN sync_id TEXT');
      }
      if (!await _columnExists(db, tableName, 'deleted_at')) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN deleted_at TEXT');
      }
      if (!await _columnExists(db, tableName, 'sync_status')) {
        await db.execute(
          "ALTER TABLE $tableName ADD COLUMN sync_status TEXT NOT NULL DEFAULT '$syncStatusSynced'",
        );
      }

      await db.execute(
        "UPDATE $tableName SET sync_id = lower(hex(randomblob(16))) WHERE sync_id IS NULL OR trim(sync_id) = ''",
      );
      await db.execute(
        "UPDATE $tableName SET sync_status = '$syncStatusSynced' WHERE sync_status IS NULL OR trim(sync_status) = ''",
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tableName}_sync_id ON $tableName(sync_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_sync_status ON $tableName(sync_status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_deleted_at ON $tableName(deleted_at)',
      );
    }
  }

  static Future<void> _migrateToVersion13(DatabaseExecutor db) async {
    if (!await _tableExists(db, lotsTable)) {
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info($lotsTable)');
    final columnNames = columns
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    if (!columnNames.contains('precio_por_metro')) {
      await db.execute(
        'ALTER TABLE $lotsTable ADD COLUMN precio_por_metro REAL NOT NULL DEFAULT 0',
      );
    }

    if (columnNames.contains('precio')) {
      await db.execute('''
        UPDATE $lotsTable
        SET precio_por_metro = CASE
          WHEN COALESCE(precio_por_metro, 0) > 0 THEN precio_por_metro
          WHEN COALESCE(metros_cuadrados, 0) > 0 THEN COALESCE(precio, 0) / metros_cuadrados
          ELSE 0
        END
      ''');
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_solares_estado ON $lotsTable(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_solares_manzana_solar ON $lotsTable(manzana_numero, solar_numero)',
    );
  }

  static Future<void> _migrateToVersion12(DatabaseExecutor db) async {
    final sales = await db.query(
      salesTable,
      columns: [
        'id',
        'saldo_pendiente',
        'interes_mensual',
        'cantidad_cuotas',
        'estado',
      ],
      where: 'saldo_pendiente > 0 AND cantidad_cuotas > 0',
    );

    final updatedAt = DateTime.now();

    for (final sale in sales) {
      final saleId = sale['id'] as int?;
      if (saleId == null) {
        continue;
      }

      final installmentRows = await db.query(
        installmentsTable,
        where: 'venta_id = ?',
        whereArgs: [saleId],
        orderBy: 'numero_cuota ASC',
      );
      if (installmentRows.isEmpty) {
        continue;
      }

      final openInstallments = installmentRows
          .where((row) {
            final status = (row['estado'] as String? ?? 'pendiente')
                .toLowerCase();
            return status != 'pagada' && status != 'ajustada';
          })
          .toList(growable: false);
      if (openInstallments.isEmpty) {
        continue;
      }

      final touchedOpenInstallments = openInstallments
          .where((row) {
            final status = (row['estado'] as String? ?? 'pendiente')
                .toLowerCase();
            final paidAmount = _toDouble(row['monto_pagado']);
            return status == 'parcial' || paidAmount > 0.009;
          })
          .toList(growable: false);

      final lastTouchedInstallmentNumber = touchedOpenInstallments.fold<int>(
        0,
        (current, row) {
          final installmentNumber = row['numero_cuota'] as int? ?? 0;
          return installmentNumber > current ? installmentNumber : current;
        },
      );

      final preservedOpenInstallments = lastTouchedInstallmentNumber <= 0
          ? const <Map<String, Object?>>[]
          : openInstallments
                .where((row) {
                  final installmentNumber = row['numero_cuota'] as int? ?? 0;
                  return installmentNumber <= lastTouchedInstallmentNumber;
                })
                .toList(growable: false);

      final installmentsToRebuild = openInstallments
          .where((row) {
            final installmentNumber = row['numero_cuota'] as int? ?? 0;
            return installmentNumber > lastTouchedInstallmentNumber;
          })
          .toList(growable: false);

      if (installmentsToRebuild.isEmpty &&
          preservedOpenInstallments.isNotEmpty) {
        continue;
      }

      final preservedOutstandingPrincipal = preservedOpenInstallments
          .fold<double>(0, (sum, row) {
            final remainingPrincipal =
                _toDouble(row['capital_cuota']) -
                _toDouble(row['capital_pagado']);
            return sum + remainingPrincipal.clamp(0, double.infinity);
          });

      final principalToRebuild = _roundCurrency(
        (_toDouble(sale['saldo_pendiente']) - preservedOutstandingPrincipal)
            .clamp(0, double.infinity),
      );

      final targetInstallments = installmentsToRebuild.isEmpty
          ? openInstallments
          : installmentsToRebuild;

      final rebuilt = SaleCalculator.buildInstallmentScheduleForDueDates(
        saleId: saleId,
        dueDates: targetInstallments
            .map((row) => DateTime.parse(row['fecha_vencimiento'] as String))
            .toList(growable: false),
        financedBalance: installmentsToRebuild.isEmpty
            ? _toDouble(sale['saldo_pendiente'])
            : principalToRebuild,
        monthlyInterest: _toDouble(sale['interes_mensual']),
        createdAt: DateTime.parse(
          targetInstallments.first['fecha_creacion'] as String,
        ),
        updatedAt: updatedAt,
        startingInstallmentNumber:
            targetInstallments.first['numero_cuota'] as int? ?? 1,
        installmentIds: targetInstallments
            .map((row) => row['id'] as int?)
            .toList(growable: false),
      );

      for (var index = 0; index < rebuilt.length; index++) {
        final installment = rebuilt[index];
        final installmentId = targetInstallments[index]['id'] as int?;
        if (installmentId == null) {
          continue;
        }

        await db.update(
          installmentsTable,
          {
            'saldo_inicial': installment.openingBalance,
            'capital_cuota': installment.principalAmount,
            'interes_cuota': installment.interestAmount,
            'monto_cuota': installment.totalAmount,
            'monto_pagado': 0,
            'capital_pagado': 0,
            'interes_pagado': 0,
            'saldo_final': installment.endingBalance,
            'estado': 'pendiente',
            'fecha_actualizacion': updatedAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [installmentId],
        );
      }

      if (installmentsToRebuild.isNotEmpty && principalToRebuild <= 0.009) {
        for (final row in installmentsToRebuild) {
          final installmentId = row['id'] as int?;
          if (installmentId == null) {
            continue;
          }

          await db.update(
            installmentsTable,
            {
              'saldo_inicial': 0,
              'capital_cuota': 0,
              'interes_cuota': 0,
              'monto_cuota': 0,
              'monto_pagado': 0,
              'capital_pagado': 0,
              'interes_pagado': 0,
              'saldo_final': 0,
              'estado': 'ajustada',
              'fecha_actualizacion': updatedAt.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [installmentId],
          );
        }
      }
    }
  }

  static Future<void> _migrateToVersion8(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clientes_cedula ON $clientsTable(cedula)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pagos_fecha_pago ON $paymentsTable(fecha_pago)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ventas_fecha_venta ON $salesTable(fecha_venta)',
    );
  }

  static Future<void> _migrateToVersion9(DatabaseExecutor db) async {
    final hasEmail = await _columnExists(db, usersTable, 'email');
    final hasPasswordHash = await _columnExists(
      db,
      usersTable,
      'password_hash',
    );
    final hasActivo = await _columnExists(db, usersTable, 'activo');
    final hasTelefono = await _columnExists(db, usersTable, 'telefono');
    final hasFechaActualizacion = await _columnExists(
      db,
      usersTable,
      'fecha_actualizacion',
    );
    final now = DateTime.now().toIso8601String();
    const defaultMigratedPassword = 'Temporal12345';

    if (!hasEmail) {
      await db.execute('ALTER TABLE $usersTable ADD COLUMN email TEXT');
    }
    if (!hasPasswordHash) {
      await db.execute(
        "ALTER TABLE $usersTable ADD COLUMN password_hash TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!hasActivo) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN activo INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!hasTelefono) {
      await db.execute('ALTER TABLE $usersTable ADD COLUMN telefono TEXT');
    }
    if (!hasFechaActualizacion) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN fecha_actualizacion TEXT',
      );
    }

    final rows = await db.query(
      usersTable,
      columns: [
        'id',
        'email',
        'password_hash',
        'rol',
        'activo',
        'fecha_creacion',
        'fecha_actualizacion',
      ],
      orderBy: 'id ASC',
    );

    final usedEmails = <String>{};
    final migratedUserHash = PasswordHasher.hashPassword(
      defaultMigratedPassword,
    );

    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) {
        continue;
      }

      final rawEmail = (row['email'] as String? ?? '').trim().toLowerCase();
      final resolvedEmail = _resolveUserEmail(
        id: id,
        rawEmail: rawEmail,
        usedEmails: usedEmails,
      );
      usedEmails.add(resolvedEmail);

      final rawPasswordHash = (row['password_hash'] as String? ?? '').trim();
      final rawRole = (row['rol'] as String? ?? '').trim().toLowerCase();
      final role = rawRole == 'admin' ? 'admin' : 'vendedor';
      final active = row['activo'] as int? ?? 1;
      final createdAt = (row['fecha_creacion'] as String? ?? '').trim();
      final updatedAt = (row['fecha_actualizacion'] as String? ?? '').trim();

      await db.update(
        usersTable,
        {
          'email': resolvedEmail,
          'password_hash': rawPasswordHash.isEmpty
              ? migratedUserHash
              : rawPasswordHash,
          'rol': role,
          'activo': active == 1 ? 1 : 0,
          'fecha_actualizacion': updatedAt.isEmpty
              ? (createdAt.isEmpty ? now : createdAt)
              : updatedAt,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_email ON $usersTable(email)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON $usersTable(rol)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_usuarios_activo ON $usersTable(activo)',
    );
  }

  static Future<void> _migrateToVersion10(DatabaseExecutor db) async {
    if (!await _columnExists(db, usersTable, 'password_reset_required')) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN password_reset_required INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(db, usersTable, 'password_updated_at')) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN password_updated_at TEXT',
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $authSessionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        selector TEXT NOT NULL UNIQUE,
        token_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_used_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        revoked_at TEXT,
        FOREIGN KEY(usuario_id) REFERENCES $usersTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sesiones_auth_usuario_id ON $authSessionsTable(usuario_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sesiones_auth_selector ON $authSessionsTable(selector)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sesiones_auth_expires_at ON $authSessionsTable(expires_at)',
    );

    final rows = await db.query(
      usersTable,
      columns: ['id', 'password_hash', 'rol'],
      orderBy: 'id ASC',
    );
    final now = DateTime.now().toIso8601String();

    for (final row in rows) {
      final userId = row['id'] as int?;
      if (userId == null) {
        continue;
      }

      final passwordHash = (row['password_hash'] as String? ?? '').trim();
      final role = (row['rol'] as String? ?? '').trim().toLowerCase();
      final weakPassword =
          passwordHash.isEmpty ||
          PasswordHasher.verifyPassword(
            PasswordHasher.legacyDefaultAdminPassword,
            passwordHash,
          ) ||
          PasswordHasher.verifyPassword(
            PasswordHasher.legacyMigratedPassword,
            passwordHash,
          );

      if (!weakPassword) {
        continue;
      }

      await db.update(
        usersTable,
        {
          'password_hash': PasswordHasher.hashPassword(
            PasswordHasher.generateRandomToken(),
          ),
          'password_reset_required': 1,
          'password_updated_at': null,
          'fecha_actualizacion': now,
          if (role == 'admin') 'rol': 'admin',
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    }
  }

  static Future<void> _migrateToVersion11(DatabaseExecutor db) async {
    if (!await _columnExists(db, paymentsTable, 'usuario_id')) {
      await db.execute(
        'ALTER TABLE $paymentsTable ADD COLUMN usuario_id INTEGER',
      );
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pagos_usuario_id ON $paymentsTable(usuario_id)',
    );

    await db.execute('''
      UPDATE $paymentsTable
      SET usuario_id = (
        SELECT v.usuario_id
        FROM $salesTable v
        WHERE v.id = $paymentsTable.venta_id
      )
      WHERE usuario_id IS NULL
    ''');
  }

  static String _resolveUserEmail({
    required int id,
    required String rawEmail,
    required Set<String> usedEmails,
  }) {
    if (id == 1) {
      return PasswordHasher.defaultAdminEmail;
    }

    if (rawEmail.isNotEmpty && !usedEmails.contains(rawEmail)) {
      return rawEmail;
    }

    var candidate = 'usuario_$id@local';
    var suffix = 1;
    while (usedEmails.contains(candidate)) {
      candidate = 'usuario_${id}_$suffix@local';
      suffix++;
    }
    return candidate;
  }

  static Future<void> _migrateToVersion6(DatabaseExecutor db) async {
    // Añade columna ano_a_pagar a la tabla de pagos
    if (!await _columnExists(db, paymentsTable, 'ano_a_pagar')) {
      await db.execute(
        'ALTER TABLE $paymentsTable ADD COLUMN ano_a_pagar TEXT',
      );
    }
  }

  static Future<void> _migrateToVersion7(DatabaseExecutor db) async {
    if (!await _columnExists(db, salesTable, 'monto_inicial_requerido')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN monto_inicial_requerido REAL NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(db, salesTable, 'monto_inicial_pagado')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN monto_inicial_pagado REAL NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(db, salesTable, 'monto_inicial_pendiente')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN monto_inicial_pendiente REAL NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(db, salesTable, 'monto_apartado_minimo')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN monto_apartado_minimo REAL',
      );
    }
    if (!await _columnExists(db, salesTable, 'fecha_limite_inicial')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN fecha_limite_inicial TEXT',
      );
    }
    if (!await _columnExists(db, salesTable, 'fecha_activacion')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN fecha_activacion TEXT',
      );
    }

    final migrationTimestamp = DateTime.now().toIso8601String();
    await db.execute('''
      UPDATE $salesTable
      SET
        monto_inicial_requerido = CASE
          WHEN monto_inicial_requerido <= 0 THEN inicial_monto
          ELSE monto_inicial_requerido
        END,
        monto_inicial_pagado = CASE
          WHEN monto_inicial_pagado <= 0 AND estado IN ('activa', 'pagada') THEN inicial_monto
          ELSE monto_inicial_pagado
        END,
        monto_inicial_pendiente = CASE
          WHEN estado IN ('activa', 'pagada') THEN 0
          ELSE MAX(
            0,
            CASE
              WHEN monto_inicial_requerido <= 0 THEN inicial_monto
              ELSE monto_inicial_requerido
            END -
            CASE
              WHEN monto_inicial_pagado <= 0 AND estado IN ('activa', 'pagada') THEN inicial_monto
              ELSE monto_inicial_pagado
            END
          )
        END,
        fecha_activacion = CASE
          WHEN fecha_activacion IS NULL AND estado IN ('activa', 'pagada') THEN fecha_venta
          ELSE fecha_activacion
        END,
        estado = CASE
          WHEN estado = 'activa' OR estado = 'pagada' OR estado = 'cancelada' THEN estado
          WHEN COALESCE(monto_inicial_pagado, 0) <= 0 THEN 'apartado'
          ELSE 'inicial_incompleto'
        END,
        fecha_actualizacion = '$migrationTimestamp'
    ''');

    await db.execute('''
      UPDATE $lotsTable
      SET estado = CASE
        WHEN EXISTS (
          SELECT 1 FROM $salesTable v
          WHERE v.solar_id = $lotsTable.id AND v.estado IN ('activa', 'pagada')
        ) THEN 'vendido'
        WHEN EXISTS (
          SELECT 1 FROM $salesTable v
          WHERE v.solar_id = $lotsTable.id AND v.estado IN ('apartado', 'inicial_incompleto')
        ) THEN 'reservado'
        ELSE estado
      END
    ''');
  }

  static Future<void> _migrateToVersion4(DatabaseExecutor db) async {
    // Create sellers table
    const createPrefix = 'IF NOT EXISTS ';
    await db.execute('''
      CREATE TABLE $createPrefix$sellersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        cedula TEXT NOT NULL UNIQUE,
        telefono TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    // Add vendedor_id column to sales table if it doesn't exist
    if (!await _columnExists(db, salesTable, 'vendedor_id')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN vendedor_id INTEGER',
      );
    }

    // Create index for sellers
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vendedores_cedula ON $sellersTable(cedula)',
    );

    // Create index for sales.vendedor_id
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ventas_vendedor_id ON $salesTable(vendedor_id)',
    );
  }

  static Future<void> _migrateToVersion5(DatabaseExecutor db) async {
    const createPrefix = 'IF NOT EXISTS ';

    // Company info table
    await db.execute('''
      CREATE TABLE $createPrefix$companyInfoTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        telefono TEXT,
        direccion TEXT,
        logo_base64 TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    // Permissions table
    await db.execute('''
      CREATE TABLE $createPrefix$permissionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        modulo TEXT NOT NULL,
        acciones TEXT NOT NULL DEFAULT '[]',
        fecha_creacion TEXT NOT NULL,
        UNIQUE(usuario_id, modulo),
        FOREIGN KEY(usuario_id) REFERENCES $usersTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    // Printer config table
    await db.execute('''
      CREATE TABLE $createPrefix$printerConfigTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        modelo TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK(tipo IN ('térmica', 'laser', 'digital')),
        es_predeterminada INTEGER NOT NULL DEFAULT 0,
        configuracion_json TEXT NOT NULL DEFAULT '{}',
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    // Financial params table
    await db.execute('''
      CREATE TABLE $createPrefix$financialParamsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inicial_porcentaje TEXT NOT NULL DEFAULT '10.0',
        interes_mensual TEXT NOT NULL DEFAULT '1.0',
        cantidad_cuotas TEXT NOT NULL DEFAULT '12',
        simbolo_moneda TEXT NOT NULL DEFAULT 'RD\$',
        lugares_decimales TEXT NOT NULL DEFAULT '2',
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    // Backup info table
    await db.execute('''
      CREATE TABLE $createPrefix$backupInfoTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre_archivo TEXT NOT NULL UNIQUE,
        fecha_creacion TEXT NOT NULL,
        tamano_bytes INTEGER NOT NULL DEFAULT 0,
        descripcion TEXT
      )
    ''');

    // Backup preferences table
    await db.execute('''
      CREATE TABLE $createPrefix$backupPreferencesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ultima_fecha_backup TEXT NOT NULL,
        auto_backup_habilitado INTEGER NOT NULL DEFAULT 1,
        intervalo_dias INTEGER NOT NULL DEFAULT 7,
        ruta_personalizada TEXT
      )
    ''');

    // Update usuarios table to add email and activo columns if they don't exist
    if (!await _columnExists(db, usersTable, 'email')) {
      await db.execute('ALTER TABLE $usersTable ADD COLUMN email TEXT');
    }

    if (!await _columnExists(db, usersTable, 'activo')) {
      await db.execute(
        'ALTER TABLE $usersTable ADD COLUMN activo INTEGER NOT NULL DEFAULT 1',
      );
    }

    // Create indexes
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_permisos_usuario_id ON $permissionsTable(usuario_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_backups_fecha ON $backupInfoTable(fecha_creacion)',
    );
  }

  static Future<void> _createVersion2Tables(
    DatabaseExecutor db, {
    required bool ifNotExists,
  }) async {
    final createPrefix = ifNotExists ? 'IF NOT EXISTS ' : '';

    await db.execute('''
      CREATE TABLE $createPrefix$clientsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        cedula TEXT NOT NULL UNIQUE,
        telefono TEXT,
        direccion TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$usersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        rol TEXT NOT NULL CHECK(rol IN ('admin', 'vendedor')),
        telefono TEXT,
        fecha_creacion TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$sellersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        cedula TEXT NOT NULL UNIQUE,
        telefono TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$lotsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        manzana_numero TEXT NOT NULL,
        solar_numero TEXT NOT NULL,
        metros_cuadrados REAL NOT NULL DEFAULT 0,
        precio_por_metro REAL NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'disponible'
          CHECK(estado IN ('disponible', 'reservado', 'vendido')),
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        UNIQUE(manzana_numero, solar_numero)
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$salesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL,
        solar_id INTEGER NOT NULL UNIQUE,
        usuario_id INTEGER NOT NULL,
        vendedor_id INTEGER,
        fecha_venta TEXT NOT NULL,
        precio_venta REAL NOT NULL DEFAULT 0,
        inicial_porcentaje REAL NOT NULL DEFAULT 0,
        inicial_monto REAL NOT NULL DEFAULT 0,
        monto_inicial_requerido REAL NOT NULL DEFAULT 0,
        monto_inicial_pagado REAL NOT NULL DEFAULT 0,
        monto_inicial_pendiente REAL NOT NULL DEFAULT 0,
        monto_apartado_minimo REAL,
        fecha_limite_inicial TEXT,
        fecha_activacion TEXT,
        saldo_financiado REAL NOT NULL DEFAULT 0,
        saldo_pendiente REAL NOT NULL DEFAULT 0,
        interes_mensual REAL NOT NULL DEFAULT 0,
        cantidad_cuotas INTEGER NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'apartado',
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        FOREIGN KEY(cliente_id) REFERENCES $clientsTable(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(solar_id) REFERENCES $lotsTable(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(usuario_id) REFERENCES $usersTable(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(vendedor_id) REFERENCES $sellersTable(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$installmentsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER NOT NULL,
        numero_cuota INTEGER NOT NULL,
        fecha_vencimiento TEXT NOT NULL,
        saldo_inicial REAL NOT NULL DEFAULT 0,
        capital_cuota REAL NOT NULL DEFAULT 0,
        interes_cuota REAL NOT NULL DEFAULT 0,
        monto_cuota REAL NOT NULL DEFAULT 0,
        monto_pagado REAL NOT NULL DEFAULT 0,
        capital_pagado REAL NOT NULL DEFAULT 0,
        interes_pagado REAL NOT NULL DEFAULT 0,
        saldo_final REAL NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'pendiente',
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        UNIQUE(venta_id, numero_cuota),
        FOREIGN KEY(venta_id) REFERENCES $salesTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$paymentsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER NOT NULL,
        cliente_id INTEGER NOT NULL,
        usuario_id INTEGER,
        cuota_id INTEGER,
        fecha_pago TEXT NOT NULL,
        monto_pagado REAL NOT NULL DEFAULT 0,
        metodo_pago TEXT,
        tipo_pago TEXT NOT NULL DEFAULT 'cuota',
        referencia TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        FOREIGN KEY(venta_id) REFERENCES $salesTable(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        FOREIGN KEY(cliente_id) REFERENCES $clientsTable(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY(usuario_id) REFERENCES $usersTable(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL,
        FOREIGN KEY(cuota_id) REFERENCES $installmentsTable(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $createPrefix$settingsTable (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');

    final indexPrefix = ifNotExists ? 'IF NOT EXISTS ' : '';
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_clientes_nombre ON $clientsTable(nombre)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_vendedores_cedula ON $sellersTable(cedula)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_solares_estado ON $lotsTable(estado)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_solares_manzana_solar ON $lotsTable(manzana_numero, solar_numero)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_ventas_cliente_id ON $salesTable(cliente_id)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_ventas_usuario_id ON $salesTable(usuario_id)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_ventas_vendedor_id ON $salesTable(vendedor_id)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_ventas_estado ON $salesTable(estado)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_cuotas_venta_id ON $installmentsTable(venta_id)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_pagos_venta_id ON $paymentsTable(venta_id)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_pagos_cliente_id ON $paymentsTable(cliente_id)',
    );
    await db.execute(
      'CREATE INDEX ${indexPrefix}idx_pagos_usuario_id ON $paymentsTable(usuario_id)',
    );
  }

  static Future<void> _migrateToVersion2(DatabaseExecutor db) async {
    await _createVersion2Tables(db, ifNotExists: true);
    await seedDefaults(db);

    if (!allowLegacyMigration) {
      await _dropLegacyTables(db);
      return;
    }

    final legacySalesClientMap = await _loadLegacySalesClientMap(db);

    await _migrateClients(db);
    await _migrateLots(db);
    await _migrateSales(db);
    await _migrateInstallments(db);
    await _migratePayments(db, legacySalesClientMap);
    await _migrateSettings(db);
    await _dropLegacyTables(db);
  }

  static Future<void> _migrateToVersion3(DatabaseExecutor db) async {
    final migrationTimestamp = DateTime.now().toIso8601String();

    if (!await _columnExists(db, salesTable, 'saldo_pendiente')) {
      await db.execute(
        'ALTER TABLE $salesTable ADD COLUMN saldo_pendiente REAL NOT NULL DEFAULT 0',
      );
    }

    if (!await _columnExists(db, installmentsTable, 'monto_pagado')) {
      await db.execute(
        'ALTER TABLE $installmentsTable ADD COLUMN monto_pagado REAL NOT NULL DEFAULT 0',
      );
    }

    if (!await _columnExists(db, installmentsTable, 'capital_pagado')) {
      await db.execute(
        'ALTER TABLE $installmentsTable ADD COLUMN capital_pagado REAL NOT NULL DEFAULT 0',
      );
    }

    if (!await _columnExists(db, installmentsTable, 'interes_pagado')) {
      await db.execute(
        'ALTER TABLE $installmentsTable ADD COLUMN interes_pagado REAL NOT NULL DEFAULT 0',
      );
    }

    await db.execute(
      'UPDATE $salesTable SET saldo_pendiente = saldo_financiado WHERE saldo_pendiente <= 0',
    );

    await db.execute('''
      UPDATE $installmentsTable
      SET
        monto_pagado = MIN(
          monto_cuota,
          COALESCE(
            (
              SELECT SUM(p.monto_pagado)
              FROM $paymentsTable p
              WHERE p.cuota_id = $installmentsTable.id
            ),
            0
          )
        ),
        interes_pagado = MIN(
          interes_cuota,
          MIN(
            monto_cuota,
            COALESCE(
              (
                SELECT SUM(p.monto_pagado)
                FROM $paymentsTable p
                WHERE p.cuota_id = $installmentsTable.id
              ),
              0
            )
          )
        ),
        capital_pagado = MAX(
          0,
          MIN(
            monto_cuota,
            COALESCE(
              (
                SELECT SUM(p.monto_pagado)
                FROM $paymentsTable p
                WHERE p.cuota_id = $installmentsTable.id
              ),
              0
            )
          ) - MIN(
            interes_cuota,
            MIN(
              monto_cuota,
              COALESCE(
                (
                  SELECT SUM(p.monto_pagado)
                  FROM $paymentsTable p
                  WHERE p.cuota_id = $installmentsTable.id
                ),
                0
              )
            )
          )
        ),
        estado = CASE
          WHEN MIN(
            monto_cuota,
            COALESCE(
              (
                SELECT SUM(p.monto_pagado)
                FROM $paymentsTable p
                WHERE p.cuota_id = $installmentsTable.id
              ),
              0
            )
          ) <= 0 THEN COALESCE(estado, 'pendiente')
          WHEN MIN(
            monto_cuota,
            COALESCE(
              (
                SELECT SUM(p.monto_pagado)
                FROM $paymentsTable p
                WHERE p.cuota_id = $installmentsTable.id
              ),
              0
            )
          ) >= monto_cuota THEN 'pagada'
          ELSE 'parcial'
        END,
        fecha_actualizacion = '$migrationTimestamp'
      ''');

    await db.execute('''
      UPDATE $salesTable
      SET
        saldo_pendiente = MAX(
          0,
          saldo_financiado
            - COALESCE(
              (
                SELECT SUM(q.capital_pagado)
                FROM $installmentsTable q
                WHERE q.venta_id = $salesTable.id
              ),
              0
            )
            - COALESCE(
              (
                SELECT SUM(p.monto_pagado)
                FROM $paymentsTable p
                WHERE p.venta_id = $salesTable.id
                  AND p.tipo_pago = 'abono_capital'
              ),
              0
            )
        ),
        estado = CASE
          WHEN MAX(
            0,
            saldo_financiado
              - COALESCE(
                (
                  SELECT SUM(q.capital_pagado)
                  FROM $installmentsTable q
                  WHERE q.venta_id = $salesTable.id
                ),
                0
              )
              - COALESCE(
                (
                  SELECT SUM(p.monto_pagado)
                  FROM $paymentsTable p
                  WHERE p.venta_id = $salesTable.id
                    AND p.tipo_pago = 'abono_capital'
                ),
                0
              )
          ) <= 0 THEN 'pagada'
          ELSE COALESCE(estado, 'activa')
        END,
        fecha_actualizacion = '$migrationTimestamp'
      ''');
  }

  static Future<Map<int, int>> _loadLegacySalesClientMap(
    DatabaseExecutor db,
  ) async {
    if (!await _tableExists(db, 'sales')) {
      return const {};
    }

    final rows = await db.query('sales', columns: ['id', 'client_id']);
    return {
      for (final row in rows)
        (row['id'] as int? ?? 0): (row['client_id'] as int? ?? 0),
    };
  }

  static Future<void> _migrateClients(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'clients')) {
      return;
    }

    final rows = await db.query('clients', orderBy: 'id ASC');
    final usedDocuments = <String>{};

    for (final row in rows) {
      final id = row['id'] as int?;
      final documentId = _buildUniqueDocumentId(
        rawValue: row['document_id'],
        clientId: id,
        usedDocuments: usedDocuments,
      );

      await db.insert(clientsTable, {
        'id': id,
        'nombre': _normalizeText(row['full_name']) ?? 'Cliente sin nombre',
        'cedula': documentId,
        'telefono': _normalizeText(row['phone']),
        'direccion': _normalizeText(row['address']),
        'fecha_creacion': _readDateValue(row['created_at']),
        'fecha_actualizacion': _readDateValue(
          row['updated_at'],
          fallback: row['created_at'],
        ),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _migrateLots(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'lots')) {
      return;
    }

    final rows = await db.query('lots', orderBy: 'id ASC');
    final usedKeys = <String>{};

    for (final row in rows) {
      final id = row['id'] as int? ?? 0;
      var blockNumber = _normalizeText(row['block']);
      var lotNumber = _normalizeText(row['number']);

      blockNumber ??= 'M$id';
      lotNumber ??= 'S$id';

      var compositeKey = '$blockNumber::$lotNumber';
      if (usedKeys.contains(compositeKey)) {
        lotNumber = '$lotNumber-$id';
        compositeKey = '$blockNumber::$lotNumber';
      }
      usedKeys.add(compositeKey);

      await db.insert(lotsTable, {
        'id': id,
        'manzana_numero': blockNumber,
        'solar_numero': lotNumber,
        'metros_cuadrados': _toDouble(row['area']),
        'precio_por_metro': _toDouble(row['area']) <= 0
            ? 0
            : _toDouble(row['price']) / _toDouble(row['area']),
        'estado': _normalizeLotStatus(row['status']),
        'fecha_creacion': _readDateValue(row['created_at']),
        'fecha_actualizacion': _readDateValue(
          row['updated_at'],
          fallback: row['created_at'],
        ),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _migrateSales(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'sales')) {
      return;
    }

    final rows = await db.query('sales', orderBy: 'id ASC');

    for (final row in rows) {
      final salePrice = _toDouble(row['sale_price']);
      final downPayment = _toDouble(row['down_payment']);

      await db.insert(salesTable, {
        'id': row['id'],
        'cliente_id': row['client_id'],
        'solar_id': row['lot_id'],
        'usuario_id': 1,
        'fecha_venta': _readDateValue(row['sale_date']),
        'precio_venta': salePrice,
        'inicial_porcentaje': salePrice <= 0
            ? 0
            : (downPayment / salePrice) * 100,
        'inicial_monto': downPayment,
        'monto_inicial_requerido': downPayment,
        'monto_inicial_pagado': downPayment,
        'monto_inicial_pendiente': 0,
        'saldo_financiado': salePrice - downPayment,
        'saldo_pendiente': salePrice - downPayment,
        'interes_mensual': 0,
        'cantidad_cuotas': row['installment_count'] as int? ?? 0,
        'estado': _normalizeSaleStatus(row['status']),
        'fecha_activacion': _readDateValue(row['sale_date']),
        'fecha_creacion': _readDateValue(row['created_at']),
        'fecha_actualizacion': _readDateValue(
          row['updated_at'],
          fallback: row['created_at'],
        ),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _migrateInstallments(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'installments')) {
      return;
    }

    final rows = await db.query('installments', orderBy: 'id ASC');

    for (final row in rows) {
      final openingBalance =
          _toDouble(row['principal_amount']) +
          _toDouble(row['interest_amount']);
      final totalAmount = _toDouble(row['total_amount']);
      final paidAmount = _toDouble(row['paid_amount']);

      await db.insert(installmentsTable, {
        'id': row['id'],
        'venta_id': row['sale_id'],
        'numero_cuota': row['installment_number'],
        'fecha_vencimiento': _readDateValue(row['due_date']),
        'saldo_inicial': openingBalance,
        'capital_cuota': _toDouble(row['principal_amount']),
        'interes_cuota': _toDouble(row['interest_amount']),
        'monto_cuota': totalAmount,
        'monto_pagado': paidAmount,
        'capital_pagado': paidAmount > _toDouble(row['interest_amount'])
            ? paidAmount - _toDouble(row['interest_amount'])
            : 0,
        'interes_pagado': paidAmount > _toDouble(row['interest_amount'])
            ? _toDouble(row['interest_amount'])
            : paidAmount,
        'saldo_final': (openingBalance - paidAmount).clamp(0, double.infinity),
        'estado': _normalizeInstallmentStatus(row['status']),
        'fecha_creacion': _readDateValue(row['created_at']),
        'fecha_actualizacion': _readDateValue(
          row['updated_at'],
          fallback: row['created_at'],
        ),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _migratePayments(
    DatabaseExecutor db,
    Map<int, int> legacySalesClientMap,
  ) async {
    if (!await _tableExists(db, 'payments')) {
      return;
    }

    final rows = await db.query('payments', orderBy: 'id ASC');

    for (final row in rows) {
      final saleId = row['sale_id'] as int? ?? 0;

      await db.insert(paymentsTable, {
        'id': row['id'],
        'venta_id': saleId,
        'cliente_id': legacySalesClientMap[saleId],
        'cuota_id': row['installment_id'],
        'fecha_pago': _readDateValue(row['payment_date']),
        'monto_pagado': _toDouble(row['amount']),
        'metodo_pago': _normalizeText(row['method']),
        'tipo_pago': 'cuota',
        'referencia': _normalizeText(row['reference']),
        'fecha_creacion': _readDateValue(row['created_at']),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _migrateSettings(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'settings')) {
      return;
    }

    final rows = await db.query('settings', orderBy: 'setting_key ASC');

    for (final row in rows) {
      await db.insert(settingsTable, {
        'clave': row['setting_key'],
        'valor': row['setting_value'],
        'fecha_actualizacion': _readDateValue(row['updated_at']),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<void> _dropLegacyTables(DatabaseExecutor db) async {
    const legacyTables = [
      'payments',
      'installments',
      'sales',
      'lots',
      'clients',
      'settings',
    ];

    for (final table in legacyTables) {
      if (await _tableExists(db, table)) {
        await db.execute('DROP TABLE $table');
      }
    }
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _columnExists(
    DatabaseExecutor db,
    String tableName,
    String columnName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows.any((row) => row['name'] == columnName);
  }

  static String _buildUniqueDocumentId({
    required Object? rawValue,
    required int? clientId,
    required Set<String> usedDocuments,
  }) {
    final baseValue = _normalizeText(rawValue) ?? 'SIN_CEDULA_${clientId ?? 0}';
    var candidate = baseValue;
    var sequence = 1;

    while (usedDocuments.contains(candidate)) {
      candidate = '${baseValue}_$sequence';
      sequence++;
    }

    usedDocuments.add(candidate);
    return candidate;
  }

  static String _readDateValue(Object? value, {Object? fallback}) {
    final primary = _normalizeText(value);
    if (primary != null) {
      return primary;
    }

    final secondary = _normalizeText(fallback);
    if (secondary != null) {
      return secondary;
    }

    return DateTime.now().toIso8601String();
  }

  static String? _normalizeText(Object? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizeLotStatus(Object? value) {
    final normalized = _normalizeText(value)?.toLowerCase();
    switch (normalized) {
      case 'reservado':
      case 'vendido':
        return normalized!;
      default:
        return 'disponible';
    }
  }

  static String _normalizeSaleStatus(Object? value) {
    final normalized = _normalizeText(value)?.toLowerCase();
    if (normalized == null) {
      return 'activa';
    }

    return normalized;
  }

  static String _normalizeInstallmentStatus(Object? value) {
    final normalized = _normalizeText(value)?.toLowerCase();
    if (normalized == null) {
      return 'pendiente';
    }

    return normalized;
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  static double _roundCurrency(double value) {
    return (value * 100).roundToDouble() / 100;
  }
}
