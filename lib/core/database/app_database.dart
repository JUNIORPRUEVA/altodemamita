import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../resilience/app_paths.dart';
import 'database_schema.dart';

class AppDatabase {
  AppDatabase._({
    String? customDatabasePath,
    AppPaths? appPaths,
    Future<String?> Function(DatabaseFactory)? legacyDatabaseLocator,
  }) : _customDatabasePath = customDatabasePath,
       _appPaths = appPaths,
       _legacyDatabaseLocator = legacyDatabaseLocator;

  factory AppDatabase.test(String databasePath) {
    return AppDatabase._(customDatabasePath: databasePath);
  }

  factory AppDatabase.forStorage({
    required AppPaths appPaths,
    Future<String?> Function(DatabaseFactory)? legacyDatabaseLocator,
  }) {
    return AppDatabase._(
      appPaths: appPaths,
      legacyDatabaseLocator: legacyDatabaseLocator,
    );
  }

  static final AppDatabase instance = AppDatabase._();

  final String? _customDatabasePath;
  final AppPaths? _appPaths;
  final Future<String?> Function(DatabaseFactory)? _legacyDatabaseLocator;
  Database? _database;
  Future<Database>? _openingDatabase;

  AppPaths get appPaths => _appPaths ?? AppPaths();

  Future<void> initialize() async {
    await database;
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final pendingDatabase = _openingDatabase;
    if (pendingDatabase != null) {
      return pendingDatabase;
    }

    final stopwatch = Stopwatch()..start();
    final openFuture = _openDatabase();
    _openingDatabase = openFuture;
    try {
      final openedDatabase = await openFuture;
      _database = openedDatabase;

      if (kDebugMode) {
        debugPrint(
          'Base de datos lista en ${stopwatch.elapsedMilliseconds} ms.',
        );
      }
      return openedDatabase;
    } finally {
      if (identical(_openingDatabase, openFuture)) {
        _openingDatabase = null;
      }
    }
  }

  Future<String> get databasePath async {
    _initializeFactory();

    if (_customDatabasePath != null) {
      final customDatabasePath = _customDatabasePath;
      await Directory(path.dirname(customDatabasePath)).create(recursive: true);
      return customDatabasePath;
    }

    await appPaths.ensureCriticalDirectories();
    final targetPath = appPaths.databasePath;
    await _migrateLegacyDatabaseIfNeeded(targetPath);
    return targetPath;
  }

  Future<void> close() async {
    final currentDatabase = _database;
    _database = null;
    _openingDatabase = null;

    if (currentDatabase != null) {
      try {
        await currentDatabase.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {
        // Best effort checkpoint before close.
      }
      await currentDatabase.close();
    }
  }

  Future<Database> _openDatabase() async {
    final dbPath = await databasePath;

    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.databaseVersion,
        onConfigure: (db) async => DatabaseSchema.configure(db),
        onCreate: (db, version) async {
          await DatabaseSchema.createTables(db);
          await DatabaseSchema.seedDefaults(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await DatabaseSchema.migrate(db, oldVersion, newVersion);
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          throw UnsupportedError(
            'No se admite abrir una base con una version de esquema superior a la soportada por esta compilacion.',
          );
        },
        onOpen: (db) async {
          await DatabaseSchema.seedDefaults(db);
        },
      ),
    );
  }

  void _initializeFactory() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  Future<void> _migrateLegacyDatabaseIfNeeded(String targetPath) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return;
    }

    final legacyPath = await _resolveLegacyDatabasePath(targetPath);
    if (legacyPath == null) {
      return;
    }

    final normalizedTarget = path.normalize(targetPath);
    final normalizedLegacy = path.normalize(legacyPath);
    if (normalizedTarget == normalizedLegacy) {
      return;
    }

    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists() || await legacyFile.length() <= 0) {
      return;
    }

    await targetFile.parent.create(recursive: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await _moveFile(legacyFile, targetFile);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final legacySidecar = File('$legacyPath$suffix');
      if (!await legacySidecar.exists()) {
        continue;
      }

      final targetSidecar = File('$targetPath$suffix');
      if (await targetSidecar.exists()) {
        await targetSidecar.delete();
      }
      await _moveFile(legacySidecar, targetSidecar);
    }
  }

  Future<String?> _resolveLegacyDatabasePath(String targetPath) async {
    final customLocator = _legacyDatabaseLocator;
    if (customLocator != null) {
      return customLocator(databaseFactory);
    }

    final legacyDirectory = await databaseFactory.getDatabasesPath();
    await Directory(legacyDirectory).create(recursive: true);
    return path.join(legacyDirectory, DatabaseSchema.databaseName);
  }

  Future<void> _moveFile(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }
}
