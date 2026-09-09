import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../resilience/app_paths.dart';

class CloudFoundationDatabases {
  CloudFoundationDatabases({
    AppPaths? appPaths,
    DatabaseFactory? databaseFactoryOverride,
  }) : _appPaths = appPaths ?? AppPaths(),
       _databaseFactory = databaseFactoryOverride ?? databaseFactoryFfi;

  final AppPaths _appPaths;
  final DatabaseFactory _databaseFactory;

  Database? _cache;
  Database? _outbox;
  Database? _deviceState;

  AppPaths get appPaths => _appPaths;

  Future<void> initialize() async {
    sqfliteFfiInit();
    await _appPaths.ensureCriticalDirectories();
    await Future.wait([cache, outbox, deviceState]);
  }

  Future<Database> get cache async {
    _cache ??= await _open(
      _appPaths.cacheDatabasePath,
      version: 1,
      onCreate: _createCacheSchema,
      onUpgrade: _migrateCacheSchema,
    );
    return _cache!;
  }

  Future<Database> get outbox async {
    _outbox ??= await _open(
      _appPaths.outboxDatabasePath,
      version: 1,
      onCreate: _createOutboxSchema,
      onUpgrade: _migrateOutboxSchema,
    );
    return _outbox!;
  }

  Future<Database> get deviceState async {
    _deviceState ??= await _open(
      _appPaths.deviceStateDatabasePath,
      version: 1,
      onCreate: _createDeviceStateSchema,
      onUpgrade: _migrateDeviceStateSchema,
    );
    return _deviceState!;
  }

  Future<void> close() async {
    for (final db in [_cache, _outbox, _deviceState]) {
      await db?.close();
    }
    _cache = null;
    _outbox = null;
    _deviceState = null;
  }

  Future<void> deleteCacheOnlyForRebuild() async {
    await _cache?.close();
    _cache = null;
    await _deleteDatabaseFileSet(_appPaths.cacheDatabasePath);
  }

  Future<Database> _open(
    String databasePath, {
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) async {
    await Directory(path.dirname(databasePath)).create(recursive: true);
    return _databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: onCreate,
        onUpgrade: onUpgrade,
      ),
    );
  }
}

Future<void> _createCacheSchema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE cache_records (
      entity TEXT NOT NULL,
      id TEXT NOT NULL,
      sync_id TEXT,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'CONFIRMED',
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      PRIMARY KEY(entity, id)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_cache_records_entity_sync ON cache_records(entity, sync_id)',
  );
  await db.execute(
    'CREATE INDEX idx_cache_records_updated ON cache_records(entity, updated_at)',
  );
  await db.execute('''
    CREATE TABLE cache_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
}

Future<void> _migrateCacheSchema(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 1) {
    await _createCacheSchema(db, newVersion);
  }
}

Future<void> _createOutboxSchema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE outbox_operations (
      operation_id TEXT PRIMARY KEY,
      operation_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      status TEXT NOT NULL,
      dependency_key TEXT,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_attempt_at TEXT,
      next_retry_at TEXT,
      last_safe_error TEXT,
      server_ack TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_outbox_status_retry ON outbox_operations(status, next_retry_at)',
  );
  await db.execute(
    'CREATE INDEX idx_outbox_dependency ON outbox_operations(dependency_key)',
  );
}

Future<void> _migrateOutboxSchema(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 1) {
    await _createOutboxSchema(db, newVersion);
  }
}

Future<void> _createDeviceStateSchema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE device_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE sync_cursors (
      scope TEXT PRIMARY KEY,
      cursor TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
}

Future<void> _migrateDeviceStateSchema(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 1) {
    await _createDeviceStateSchema(db, newVersion);
  }
}

Future<void> _deleteDatabaseFileSet(String databasePath) async {
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('$databasePath$suffix');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
